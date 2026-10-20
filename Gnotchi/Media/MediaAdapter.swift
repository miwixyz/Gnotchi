import Foundation
import OSLog
import Security

/// Führt `/usr/bin/perl mediaremote-adapter.pl …` als Kindprozess (docs/SECURE-DESIGN.md G2–G10).
/// Pfade nur aus dem signierten Bundle, Argumente fest, keine Shell (G3).
@MainActor
final class MediaAdapter {

    enum Command: Int { case play = 0, pause = 1, toggle = 2, next = 4, previous = 5 }
    enum Call { case stream, test, send(Command), seek(TimeInterval) }
    enum State: Equatable { case starting, running, unavailable(String) }
    /// Was ein Paket des Stroms bewirkt: neuer Titel oder „nichts läuft“.
    enum StreamEvent: Equatable, Sendable { case info(NowPlayingInfo), clear }

    struct Paths: Equatable {
        let script: URL
        let framework: URL
        let testClient: URL

        static func bundled(_ b: Bundle = .main) -> Paths? {
            guard let script = b.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let fw = b.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
                  let client = b.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient"),
                  FileManager.default.fileExists(atPath: fw.path) else { return nil }
            return Paths(script: script, framework: fw, testClient: client)
        }
    }

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "medien")
    nonisolated static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    /// Feste Umgebung für JEDEN Kindprozess (G3, Review 18.10.): Gnotchi erbt sonst z. B.
    /// `PERL5OPT=-M…` aus `launchctl setenv` und Perl lädt fremden Code – ganz ohne Eingriff ins Bundle.
    nonisolated static let cleanEnvironment = ["PATH": "/usr/bin:/bin"]

    var onInfo: ((NowPlayingInfo?) -> Void)?
    var onState: ((State) -> Void)?
    private(set) var state: State = .starting { didSet { if state != oldValue { onState?(state) } } }

    private var paths: Paths?
    private var process: Process?
    private var generation = 0
    private var failures = 0
    /// Gescheiterte Selbsttests in Folge seit dem letzten start() (Staffel `retestDelay`).
    private var testFailures = 0
    private var stopped = true
    private var badLines = 0
    /// Höchstens ein Befehls-Prozess gleichzeitig; weitere Klicks werden verworfen (wie AppleScript).
    private var commands = OneAtATime()
    private var launchedAt = Date.distantPast
    /// Byte-Suche statt String-Umwandlung: die Zeile kann ungültiges UTF-8 enthalten.
    nonisolated static let emptyPayload = Data(#""payload":{}"#.utf8)

    // MARK: Reine Teile (getestet)

    nonisolated static func restartDelay(afterFailures n: Int) -> TimeInterval? {
        switch n {
        case 1: 1
        case 2: 5
        default: nil
        }
    }

    /// Pause vor dem nächsten Selbsttest. Ohne Ende: Am 19.10. scheiterte der Test 1,7 Min. nach dem
    /// Booten und der Hinweis blieb 20 Std. stehen, ein Neustart von Gnotchi behob es (Ursache unbekannt).
    /// Ein Test kostet ~0,1 s Perl plus die Signaturprüfung – alle 5 Min. ist vernachlässigbar.
    nonisolated static func retestDelay(afterFailedTests n: Int) -> TimeInterval {
        switch n {
        case ...1: 5
        case 2: 30
        case 3: 120
        default: 300
        }
    }

    /// Ergebnis des Selbsttests. Fehlerfälle getrennt, damit das Protokoll die Ursache zeigt.
    enum TestOutcome: Equatable, Sendable {
        case ok, timedOut, exitCode(Int32), signal(Int32), launchFailed

        /// Nur Statuscodes – keine Titel, keine App-Namen (Protokollregel der App-Familie).
        var logText: String {
            switch self {
            case .ok: "bestanden"
            case .timedOut: "Zeitlimit 10 s überschritten"
            case .exitCode(let c): "Exit-Code \(c)"
            case .signal(let s): "Signal \(s)"
            case .launchFailed: "Start fehlgeschlagen"
            }
        }
    }

    nonisolated static func testOutcome(launched: Bool, timedOut: Bool,
                                        reason: Process.TerminationReason, status: Int32) -> TestOutcome {
        guard launched else { return .launchFailed }
        if timedOut { return .timedOut }
        if reason == .uncaughtSignal { return .signal(status) }
        return status == 0 ? .ok : .exitCode(status)
    }

    /// Abbruchzähler nach einem Prozessende. Nur ein Lauf ≥ 30 s gilt als gesund und setzt zurück –
    /// nicht jede gelesene Zeile: Der Strom meldet direkt nach dem Start `payload:{}`, ein
    /// „eine Zeile, dann Absturz“-Adapter liefe sonst endlos im 1-s-Takt (Review 18.10.).
    nonisolated static func failuresAfterExit(previous: Int, ranFor: TimeInterval) -> Int {
        ranFor >= 30 ? 1 : previous + 1
    }

    /// Maskiert die Sonderzeichen erweiterter regulärer Ausdrücke (pgrep -f): `Gnotchi (2).app`.
    nonisolated static func ereEscape(_ s: String) -> String {
        let special = Set(#".[]()*+?{}|^$\"#)
        return s.reduce(into: "") { out, ch in
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
    }

    /// G9: nur Waisen (Eltern = launchd, PID 1) und nur der exakte Perl-Aufruf unseres Skripts –
    /// ein `less …/mediaremote-adapter.pl` oder ein laufender Adapter einer anderen Instanz bleibt unberührt.
    nonisolated static func pgrepArguments(scriptPath: String) -> [String] {
        ["-P", "1", "-f", "^" + ereEscape(perl.path + " " + scriptPath) + " "]
    }

    nonisolated static func arguments(_ p: Paths, _ call: Call) -> [String] {
        let base = [p.script.path, p.framework.path]
        switch call {
        case .stream: return base + ["stream", "--no-diff", "--micros", "--debounce=100"]
        case .test: return base + [p.testClient.path, "test"]
        case .send(let c): return base + ["send", String(c.rawValue)]
        case .seek(let s):
            // Unendlich/NaN würde beim Umwandeln in Int64 abstürzen; Obergrenze großzügig (7 Tage).
            let secs = s.isFinite ? min(max(0, s), 7 * 86_400) : 0
            return base + ["seek", String(Int64((secs * 1_000_000).rounded()))]
        }
    }

    /// Je Paket zählt nur die LETZTE brauchbare Zeile (frühere sind schon überholt): von hinten dekodieren,
    /// bis eine Meldung oder ein leeres `payload` („nichts läuft“) kommt. Unlesbare Zeilen danach werden
    /// gezählt und leeren die Anzeige nicht. Läuft auf dem Lese-Thread, nicht auf dem MainActor.
    nonisolated static func latestEvent(in lines: [Data]) -> (event: StreamEvent?, badLines: Int) {
        var bad = 0
        for line in lines.reversed() {
            if line.contains(UInt8(ascii: "{")), let info = NowPlayingInfo.parse(line: line) { return (.info(info), bad) }
            if line.range(of: emptyPayload) != nil { return (.clear, bad) }
            bad += 1
        }
        return (nil, bad)
    }

    /// Einzige Stelle, die einen Perl-Prozess baut (G3): fester Interpreter, feste Umgebung,
    /// Ausgaben verworfen. Wer den Strom lesen will, setzt danach `standardOutput` um.
    nonisolated static func perlProcess(_ args: [String]) -> Process {
        let proc = Process()
        proc.executableURL = perl
        proc.arguments = args
        proc.environment = cleanEnvironment
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        return proc
    }

    // MARK: Betrieb

    func start() {
        guard stopped else { return }
        stopped = false
        state = .starting
        testFailures = 0
        guard let p = Paths.bundled() else { return fail("Adapter fehlt im Programmpaket") }
        paths = p
        // stop() erhöht die Generation: ein schnelles stop()+start() macht diesen Lauf ungültig,
        // sonst liefen am Ende zwei Ströme und einer wäre verwaist.
        let gen = generation
        Task { await self.testThenLaunch(p, generation: gen) }
    }

    /// Selbsttest, bei Erfolg Strom starten. Scheitert er, bleibt der Zustand `unavailable` (der
    /// Rückfall Spotify/Musik läuft weiter) und ein neuer Versuch folgt nach `retestDelay`.
    /// stop() oder ein Signaturfehler (fail) erhöhen die Generation und beenden die Kette.
    private func testThenLaunch(_ p: Paths, generation gen: Int) async {
        guard await verified(), gen == generation else { return }
        await Task.detached { Self.killOrphans(scriptPath: p.script.path) }.value
        let outcome = await Self.runTest(p)
        guard !stopped, gen == generation else { return }
        guard outcome != .ok else {
            if testFailures > 0 { Self.log.notice("Medien-Adapter-Selbsttest bestanden nach \(self.testFailures, privacy: .public) Fehlversuchen") }
            return launchStream()
        }
        testFailures += 1
        let delay = Self.retestDelay(afterFailedTests: testFailures)
        Self.log.error("Medien-Adapter-Selbsttest gescheitert (\(outcome.logText, privacy: .public), Versuch \(self.testFailures, privacy: .public)) – neuer Versuch in \(Int(delay), privacy: .public) s")
        if state == .starting { onInfo?(nil) }
        state = .unavailable("macOS blockiert den Zugriff auf die Wiedergabe")
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard gen == self.generation, !self.stopped else { return }
            await self.testThenLaunch(p, generation: gen)
        }
    }

    /// G2: Bundle-Signatur inkl. Team-Anforderung, vor JEDEM Perl-Start, außerhalb des
    /// Hauptthreads (30–50 ms gemessen, Review 18.10.).
    private func verified() async -> Bool {
        let url = Bundle.main.bundleURL
        let status = await Task.detached { BundleIntegrity.check(url) }.value
        guard !stopped else { return false }
        guard status == errSecSuccess else {
            fail("Signatur des Programmpakets ungültig (OSStatus \(status)) – Adapter nicht gestartet")
            return false
        }
        return true
    }

    func stop() {
        stopped = true
        generation += 1
        terminateProcess()
    }

    func perform(_ call: Call) {
        guard case .running = state, let p = paths else { return }
        if case .stream = call { return }
        if case .test = call { return }
        guard commands.tryStart() else { return }
        let args = Self.arguments(p, call)
        Task {
            defer { self.commands.finish() }
            guard await self.verified() else { return }
            await Task.detached {
                let proc = Self.perlProcess(args)
                try? proc.run()
                proc.waitUntilExit()
            }.value
        }
    }

    /// Endgültig aus (bis stop()/start()): laufenden Strom beenden und Neustarts verwerfen –
    /// sonst liefe nach einer ungültigen Signatur beim Befehl der alte Strom weiter.
    private func fail(_ reason: String) {
        Self.log.error("Medien-Adapter aus: \(reason, privacy: .public)")
        stopped = true   // ein späteres start() versucht es erneut
        generation += 1
        terminateProcess()
        state = .unavailable(reason)
        onInfo?(nil)
    }

    private func launchStream() {
        guard !stopped, let p = paths else { return }
        generation += 1
        let gen = generation
        let reader = StreamReader()   // je Lauf neu: kein halber Zeilenrest aus dem vorigen
        let proc = Self.perlProcess(Self.arguments(p, .stream))
        launchedAt = Date()
        let out = Pipe()
        proc.standardOutput = out
        // Zeilen schneiden und JSON dekodieren auf dem Lese-Thread (Security-Review B3: ein Strom mit
        // 2-MB-Covern blockierte sonst den Hauptthread); zum MainActor geht nur das Ergebnis.
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF: leere Daten. Handler abmelden, sonst ruft Foundation ihn in Dauerschleife auf.
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let result = reader.feed(data)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(result, generation: gen) } }
        }
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.exited(status: status, generation: gen) } }
        }
        do {
            try proc.run()
            process = proc
            state = .running
            Self.log.notice("Medien-Adapter läuft")
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            exited(status: -1, generation: gen)
        }
    }

    /// Leeres `payload` heißt „nichts läuft“ → Anzeige leeren. Eine unlesbare Zeile dagegen
    /// leert NICHT (sonst flackert die Anzeige bei einem kaputten Paket), sie wird nur gezählt.
    private func consume(_ r: StreamReader.Result, generation gen: Int) {
        guard gen == generation else { return }
        if r.droppedLines > 0 { Self.log.error("Medien-Adapter: überlange Zeile verworfen") }
        let before = badLines
        badLines = r.event == nil ? badLines + r.badLines : r.badLines
        if before < 10, badLines >= 10 { Self.log.error("Medien-Adapter: 10 unlesbare Zeilen in Folge") }
        switch r.event {
        case .info(let info)?: onInfo?(info)
        case .clear?: onInfo?(nil)
        case nil: break
        }
    }

    private func exited(status: Int32, generation gen: Int) {
        guard gen == generation, !stopped else { return }
        process = nil
        failures = Self.failuresAfterExit(previous: failures, ranFor: Date().timeIntervalSince(launchedAt))
        Self.log.error("Medien-Adapter beendet (Status \(status, privacy: .public), Abbruch \(self.failures, privacy: .public))")
        guard let delay = Self.restartDelay(afterFailures: failures) else {
            return fail("Adapter bricht wiederholt ab")
        }
        state = .starting
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard gen == self.generation, !self.stopped, await self.verified() else { return }
            self.launchStream()
        }
    }

    private func terminateProcess() {
        guard let proc = process else { return }
        process = nil
        (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
    }

    /// `test` mit 10 s Zeitlimit, außerhalb des Hauptthreads.
    nonisolated static func runTest(_ p: Paths) async -> TestOutcome {
        let args = arguments(p, .test)
        return await Task.detached { runTestBlocking(args) }.value
    }

    /// Synchron, weil `DispatchGroup.wait` in async-Kontexten gesperrt ist (Swift 6).
    private nonisolated static func runTestBlocking(_ args: [String]) -> TestOutcome {
        let proc = perlProcess(args)
        let done = DispatchGroup()
        done.enter()
        proc.terminationHandler = { _ in done.leave() }
        guard (try? proc.run()) != nil else {
            return testOutcome(launched: false, timedOut: false, reason: .exit, status: 0)
        }
        if done.wait(timeout: .now() + 10) == .timedOut {
            proc.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(proc.processIdentifier, SIGKILL) }
            return testOutcome(launched: true, timedOut: true, reason: .uncaughtSignal, status: 0)
        }
        return testOutcome(launched: true, timedOut: false,
                           reason: proc.terminationReason, status: proc.terminationStatus)
    }

    /// G9: verwaiste Adapter-Prozesse DIESES Bundles beenden (nach Absturz von Gnotchi).
    /// Abgleich über den vollständigen Skriptpfad, ohne Shell, eigene PID ausgeschlossen.
    nonisolated static func killOrphans(scriptPath: String) {
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = pgrepArguments(scriptPath: scriptPath)
        pg.environment = cleanEnvironment
        pg.standardError = FileHandle.nullDevice
        let out = Pipe()
        pg.standardOutput = out
        guard (try? pg.run()) != nil else { return }
        // Erst lesen, dann warten: bei voller Pipe blockierte pgrep sonst auf uns und wir auf pgrep.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        pg.waitUntilExit()
        let own = getpid()
        (String(bytes: data, encoding: .utf8) ?? "")
            .split(separator: "\n").compactMap { pid_t($0) }
            .filter { $0 > 1 && $0 != own }
            .forEach { kill($0, SIGTERM) }
    }
}

/// Liest den Strom auf dem Lese-Thread des FileHandle: Zeilen schneiden (G4, 4 MB) und nur die letzte
/// brauchbare Zeile je Paket dekodieren. Foundation ruft den Handler nacheinander auf; das Schloss
/// sichert den Zustand trotzdem ab, falls das je anders wäre.
final class StreamReader: @unchecked Sendable {
    struct Result: Sendable {
        let event: MediaAdapter.StreamEvent?
        let badLines: Int
        let droppedLines: Int
    }

    private let lock = NSLock()
    private var splitter = LineSplitter(maxLineBytes: 4 << 20)

    func feed(_ data: Data) -> Result {
        lock.lock()
        defer { lock.unlock() }
        let before = splitter.dropped
        let lines = splitter.feed(data)
        let (event, bad) = MediaAdapter.latestEvent(in: lines)
        return Result(event: event, badLines: bad, droppedLines: splitter.dropped - before)
    }
}
