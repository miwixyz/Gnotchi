import AppKit
import CoreServices
import OSLog

/// Rückfall ohne Adapter (docs/SECURE-DESIGN.md G7): Spotify und Musik per AppleScript.
/// Außerdem spult Spotify immer hierüber (`sendSeek`), auch während der Adapter läuft.
/// Alle Skripte sind Konstanten; einzige variable Größe ist die Spulposition als formatierte Zahl.
/// Jedes Skript prüft selbst, ob die App läuft – `tell application` würde sie sonst starten.
@MainActor
final class AppleScriptSource {

    /// Antwort der Statusabfrage als reine Werte – überquert die Queue-Grenze statt des
    /// nicht Sendable `NSAppleEventDescriptor`.
    struct Fields: Equatable, Sendable {
        var title: String?
        var artist: String?
        var state: String?
        var duration: Double?
        var position: Double?
    }

    nonisolated static let spotify = "com.spotify.client"
    nonisolated static let music = "com.apple.Music"
    nonisolated static let supported = [spotify, music]
    /// errAEEventNotPermitted: Nutzer hat die Automation für diese App verweigert.
    nonisolated static let deniedError = -1743
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "medien")

    var onInfo: ((NowPlayingInfo?) -> Void)?
    /// Verweigerte Apps (Bundle-IDs), sobald keine erlaubte, laufende Quelle mehr bleibt; leer = kein Hinweis.
    /// Nur bei Änderung gemeldet.
    var onBlocked: (([String]) -> Void)?

    /// Eigene serielle Queue: Die erste Abfrage wartet auf den Automation-Dialog von macOS
    /// und darf den Hauptthread nicht blockieren.
    private let queue = DispatchQueue(label: "dev.mwlr.gnotchi.applescript", qos: .utility)
    private var timer: Timer?
    private var active: String?
    private var denied = Set<String>()
    private var lastBlocked: [String] = []
    /// Eine Abfrage läuft noch (z. B. hängt am Dialog) – keine weiteren anstauen.
    private var polling = false
    /// Ein Befehl kam, während eine Abfrage lief: deren Antwort ist veraltet, danach erneut fragen.
    private var repollAfterFinish = false
    /// Höchstens ein Befehl auf der Queue; weitere Klicks werden verworfen, nicht angestaut.
    private var commandRunning = false
    /// stop() macht Antworten laufender Abfragen und Befehle ungültig.
    private var generation = 0
    private var lastInfo: NowPlayingInfo?
    /// Fehlernummern von `sendSeek`, die schon im Protokoll stehen – je Nummer einmal.
    private var loggedSeekErrors = Set<Int>()

    func start() {
        guard timer == nil else { return }
        Self.log.info("Rückfall AppleScript an")
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        // .common: auch während ein Menü offen ist (Menüleisten-App).
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        guard timer != nil else { return }
        Self.log.info("Rückfall AppleScript aus")
        timer?.invalidate()
        timer = nil
        active = nil
        polling = false
        repollAfterFinish = false
        commandRunning = false
        generation += 1
        lastInfo = nil
        lastBlocked = []
        // Nach einem Neustart erneut versuchen: vielleicht hat der Nutzer inzwischen erlaubt.
        denied.removeAll()
    }

    func perform(_ call: MediaAdapter.Call) {
        switch call {
        case .stream, .test: return
        case .send, .seek: break
        }
        guard !commandRunning, let id = active else { return }
        let source = Self.script(call, bundleID: id)
        guard !source.isEmpty else { return }
        commandRunning = true
        let gen = generation
        queue.async { [weak self] in
            // Zweite Prüfung direkt vor dem Senden; die dritte steht im Skript selbst.
            if Self.isRunning(id) { _ = Self.execute(source) }
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.commandRunning = false
            }
        }
        // Sofort nachfragen (läuft seriell nach dem Befehl), sonst hinkt die Anzeige bis zu 1 s.
        if polling { repollAfterFinish = true } else { poll() }
    }

    /// Spulen per AppleScript, auch während der Adapter läuft (G7): Spotify Connect ignoriert den
    /// MediaRemote-Spulbefehl und springt zurück (gemessen 18.10.). Unabhängig vom Rückfall-Takt
    /// (`active`); gleiches Skript, gleiche Queue, gleiche Prüfungen wie `perform`, höchstens ein
    /// Befehl gleichzeitig. Nur für die festen Bundle-IDs. `onFailure` bekommt die AppleScript-
    /// Fehlernummer (z. B. -1743 verweigert, Zeitgrenze überschritten) – der Aufrufer weicht aus.
    func sendSeek(_ seconds: TimeInterval, bundleID: String, onFailure: @escaping @MainActor @Sendable (Int) -> Void) {
        guard !commandRunning, let id = Self.supported.first(where: { $0 == bundleID }) else { return }
        let source = Self.script(.seek(seconds), bundleID: id)
        guard !source.isEmpty else { return }
        commandRunning = true
        let gen = generation
        queue.async { [weak self] in
            // Zweite Prüfung direkt vor dem Senden; die dritte steht im Skript selbst.
            let error = Self.isRunning(id) ? Self.execute(source).1 : nil
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.commandRunning = false
                guard let error else { return }
                if self.loggedSeekErrors.insert(error).inserted {
                    // G8: nur Bundle-ID und Fehlernummer, nie Inhalte.
                    Self.log.error("Spulen per AppleScript fehlgeschlagen (\(error, privacy: .public)) für \(id, privacy: .public) – Adapter übernimmt")
                }
                onFailure(error)
            }
        }
    }

    private func poll() {
        guard timer != nil, !polling else { return }
        let running = Self.runningSupported()
        updateBlocked(running: running)
        let candidates = Self.supported.filter { running.contains($0) && !denied.contains($0) }
        guard !candidates.isEmpty else {
            active = nil
            return emit(nil)
        }
        polling = true
        let gen = generation
        queue.async { [weak self] in
            let result = Self.query(candidates)
            Task { @MainActor in self?.finish(gen: gen, best: result.best, deniedNow: result.denied) }
        }
    }

    private func finish(gen: Int, best: (id: String, info: NowPlayingInfo)?, deniedNow: [String]) {
        guard gen == generation else { return }
        polling = false
        if !deniedNow.isEmpty {
            denied.formUnion(deniedNow)
            // G8: nur Bundle-IDs, nie Inhalte.
            Self.log.error("Automation verweigert für \(deniedNow.joined(separator: ","), privacy: .public)")
            updateBlocked(running: Self.runningSupported())
        }
        active = best?.id
        emit(best?.info)
        if repollAfterFinish {
            repollAfterFinish = false
            poll()
        }
    }

    /// „Nichts läuft“ nur einmal melden, nicht jede Sekunde.
    private func emit(_ info: NowPlayingInfo?) {
        if info == nil && lastInfo == nil { return }
        lastInfo = info
        onInfo?(info)
    }

    private func updateBlocked(running: Set<String>) {
        let now = Self.blocked(running: running, denied: denied)
        guard now != lastBlocked else { return }
        lastBlocked = now
        onBlocked?(now)
    }

    private static func runningSupported() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).intersection(supported)
    }

    private nonisolated static func isRunning(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    /// Fragt die Kandidaten nacheinander ab; die spielende App gewinnt, sonst die erste mit Titel.
    private nonisolated static func query(_ ids: [String]) -> (best: (id: String, info: NowPlayingInfo)?, denied: [String]) {
        var best: (id: String, info: NowPlayingInfo)?
        var deniedNow: [String] = []
        for id in ids {
            let result = status(id)
            if result.error == deniedError { deniedNow.append(id); continue }
            guard let info = result.fields.flatMap({ parse($0, bundleID: id, now: Date()) }) else { continue }
            if best == nil || (info.isPlaying && !(best?.info.isPlaying ?? false)) { best = (id, info) }
        }
        return (best, deniedNow)
    }

    /// Statusabfrage einer App; der Descriptor bleibt auf der Queue, heraus gehen nur Werte.
    private nonisolated static func status(_ id: String) -> (fields: Fields?, error: Int?) {
        guard isRunning(id) else { return (nil, nil) }
        let (out, error) = execute(script(.stream, bundleID: id))
        return (out.flatMap(fields(from:)), error)
    }

    /// NSAppleScript ist nicht Sendable – deshalb hier, auf der Queue, erzeugt und nie geteilt.
    private nonisolated static func execute(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        guard !source.isEmpty else { return (nil, nil) }
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (out, err?[NSAppleScript.errorNumber] as? Int)
    }

    // MARK: Reine Teile (getestet)

    /// Leer für jede andere Bundle-ID als Spotify/Musik. Die ID im Skript ist immer eine der
    /// beiden Konstanten, nie der übergebene Wert. Befehle mit Zeitgrenze, die Abfrage ohne –
    /// sie wartet beim ersten Mal auf den Automation-Dialog.
    nonisolated static func script(_ call: MediaAdapter.Call, bundleID: String) -> String {
        guard let id = supported.first(where: { $0 == bundleID }) else { return "" }
        let body: String
        switch call {
        case .stream, .test:
            body = """
            if player state is stopped then return {}
            set t to current track
            return {name of t, artist of t, duration of t, player position, player state as string}
            """
        case .send(.toggle): body = timed("playpause")
        case .send(.play): body = timed("play")
        case .send(.pause): body = timed("pause")
        case .send(.next): body = timed("next track")
        case .send(.previous): body = timed("previous track")
        case .seek(let sec):
            // Wie MediaAdapter.arguments: nie unendlich/NaN, Obergrenze großzügig (7 Tage).
            let secs = sec.isFinite ? min(max(0, sec), 7 * 86_400) : 0
            body = timed("set player position to " + String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), secs))
        }
        return "if application id \"\(id)\" is running then\ntell application id \"\(id)\"\n\(body)\nend tell\nend if"
    }

    private nonisolated static func timed(_ command: String) -> String {
        "with timeout of 3 seconds\n\(command)\nend timeout"
    }

    /// Liste `{Titel, Interpret, Dauer, Position, Zustand}` lesen. Zahlen per Umwandlung:
    /// `doubleValue` gäbe für Text 0,0. `missing value` ergibt nil.
    nonisolated static func fields(from d: NSAppleEventDescriptor) -> Fields? {
        guard d.descriptorType == typeAEList, d.numberOfItems == 5 else { return nil }
        func text(_ i: Int) -> String? { d.atIndex(i)?.stringValue }
        func number(_ i: Int) -> Double? {
            guard let item = d.atIndex(i), ![typeUnicodeText, typeUTF8Text, typeChar].contains(item.descriptorType) else { return nil }
            return item.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue
        }
        return Fields(title: text(1), artist: text(2), state: text(5), duration: number(3), position: number(4))
    }

    /// Spotify liefert die Dauer in Millisekunden, Musik in Sekunden.
    nonisolated static func parse(_ f: Fields, bundleID: String, now: Date) -> NowPlayingInfo? {
        guard supported.contains(bundleID), let title = NowPlayingInfo.sanitize(f.title) else { return nil }
        let dur = f.duration.map { bundleID == spotify ? $0 / 1000 : $0 }.flatMap(NowPlayingInfo.validDuration)
        let pos = f.position.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let playing = f.state == "playing"
        return NowPlayingInfo(title: title, artist: NowPlayingInfo.sanitize(f.artist), album: nil,
                              appBundleID: bundleID, isPlaying: playing, duration: dur,
                              elapsedAtStamp: pos, stamp: now, rate: playing ? 1 : 0,
                              contentID: nil, artworkBase64: nil)
    }

    /// Hinweis nur, wenn keine laufende, erlaubte Quelle bleibt: dann die verweigerten Apps.
    nonisolated static func blocked(running: Set<String>, denied: Set<String>) -> [String] {
        let usable = supported.contains { running.contains($0) && !denied.contains($0) }
        return usable ? [] : supported.filter { denied.contains($0) }
    }

    /// Lokaler, übersetzter App-Name (aus dem Programmpaket, nichts übers Netz); sonst die Bundle-ID.
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
