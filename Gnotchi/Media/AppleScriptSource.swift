import AppKit
import OSLog

/// Rückfall ohne Adapter (docs/SECURE-DESIGN.md G7): Spotify und Musik per AppleScript.
/// Alle Skripte sind Konstanten; einzige variable Größe ist die Spulposition als formatierte Zahl.
/// Abgefragt werden nur Apps, die schon laufen – `tell application` würde sie sonst starten.
@MainActor
final class AppleScriptSource {

    nonisolated static let spotify = "com.spotify.client"
    nonisolated static let music = "com.apple.Music"
    nonisolated static let supported = [spotify, music]
    /// errAEEventNotPermitted: Nutzer hat die Automation für diese App verweigert.
    nonisolated static let deniedError = -1743
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "medien")
    private nonisolated static let sep = "\u{1F}"

    var onInfo: ((NowPlayingInfo?) -> Void)?
    /// Gesetzt, wenn der Nutzer die Automation verweigert hat.
    var onDenied: (() -> Void)?

    /// Eigene serielle Queue: Die erste Abfrage wartet auf den Automation-Dialog von macOS
    /// und darf den Hauptthread nicht blockieren.
    private let queue = DispatchQueue(label: "dev.mwlr.gnotchi.applescript", qos: .utility)
    private var timer: Timer?
    private var active: String?
    private var denied = Set<String>()
    /// Eine Abfrage läuft noch (z. B. hängt am Dialog) – keine weiteren anstauen.
    private var polling = false
    /// stop() macht Antworten laufender Abfragen ungültig.
    private var generation = 0
    private var lastInfo: NowPlayingInfo?

    func start() {
        guard timer == nil else { return }
        Self.log.info("Rückfall AppleScript an")
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
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
        generation += 1
        lastInfo = nil
        // Nach einem Neustart erneut versuchen: vielleicht hat der Nutzer inzwischen erlaubt.
        denied.removeAll()
    }

    func perform(_ call: MediaAdapter.Call) {
        switch call {
        case .stream, .test: return
        case .send, .seek: break
        }
        // Nur an eine App, die noch läuft – ein Befehl an eine beendete würde sie starten.
        guard let id = active, !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty else { return }
        let source = Self.script(call, bundleID: id)
        guard !source.isEmpty else { return }
        queue.async { _ = Self.run(source) }
        // Sofort nachfragen (läuft seriell nach dem Befehl), sonst hinkt die Anzeige bis zu 1 s.
        poll()
    }

    private func poll() {
        guard timer != nil, !polling else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
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
            onDenied?()
        }
        active = best?.id
        emit(best?.info)
    }

    /// „Nichts läuft“ nur einmal melden, nicht jede Sekunde.
    private func emit(_ info: NowPlayingInfo?) {
        if info == nil && lastInfo == nil { return }
        lastInfo = info
        onInfo?(info)
    }

    /// Fragt die Kandidaten nacheinander ab; die spielende App gewinnt, sonst die erste mit Titel.
    private nonisolated static func query(_ ids: [String]) -> (best: (id: String, info: NowPlayingInfo)?, denied: [String]) {
        var best: (id: String, info: NowPlayingInfo)?
        var deniedNow: [String] = []
        for id in ids {
            let result = run(script(.stream, bundleID: id))
            if result.error == deniedError { deniedNow.append(id); continue }
            guard let info = result.text.flatMap({ parse($0, bundleID: id, now: Date()) }) else { continue }
            if best == nil || (info.isPlaying && !(best?.info.isPlaying ?? false)) { best = (id, info) }
        }
        return (best, deniedNow)
    }

    // MARK: Reine Teile (getestet)

    /// Leer für jede andere Bundle-ID als Spotify/Musik. Die ID im Skript ist immer eine der
    /// beiden Konstanten, nie der übergebene Wert.
    nonisolated static func script(_ call: MediaAdapter.Call, bundleID: String) -> String {
        guard let id = supported.first(where: { $0 == bundleID }) else { return "" }
        let body: String
        switch call {
        case .stream, .test:
            body = """
            if player state is stopped then return ""
            set t to current track
            set s to character id 31
            return (name of t) & s & (artist of t) & s & (duration of t) & s & (player position) & s & (player state as string)
            """
        case .send(.toggle): body = "playpause"
        case .send(.play): body = "play"
        case .send(.pause): body = "pause"
        case .send(.next): body = "next track"
        case .send(.previous): body = "previous track"
        case .seek(let sec):
            // Wie MediaAdapter.arguments: nie unendlich/NaN, Obergrenze großzügig (7 Tage).
            let secs = sec.isFinite ? min(max(0, sec), 7 * 86_400) : 0
            body = "set player position to " + String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), secs)
        }
        return "tell application id \"\(id)\"\n\(body)\nend tell"
    }

    /// Spotify liefert die Dauer in Millisekunden, Musik in Sekunden. AppleScript schreibt Zahlen
    /// je nach Systemsprache mit Komma und große Werte in E-Schreibweise („1,08E+4“).
    nonisolated static func parse(_ raw: String, bundleID: String, now: Date) -> NowPlayingInfo? {
        guard supported.contains(bundleID) else { return nil }
        let f = raw.components(separatedBy: sep)
        guard f.count == 5, let title = NowPlayingInfo.sanitize(f[0]) else { return nil }
        let dur = number(f[2]).map { bundleID == spotify ? $0 / 1000 : $0 }.flatMap(NowPlayingInfo.validDuration)
        let pos = number(f[3]).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let playing = f[4] == "playing"
        return NowPlayingInfo(title: title, artist: NowPlayingInfo.sanitize(f[1]), album: nil,
                              appBundleID: bundleID, isPlaying: playing, duration: dur,
                              elapsedAtStamp: pos, stamp: now, rate: playing ? 1 : 0,
                              contentID: nil, artworkBase64: nil)
    }

    private nonisolated static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// NSAppleScript ist nicht Sendable – deshalb hier, auf der Queue, erzeugt; über die Grenze gehen nur Strings/Ints.
    private nonisolated static func run(_ source: String) -> (text: String?, error: Int?) {
        guard !source.isEmpty else { return (nil, nil) }
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (out?.stringValue, err?[NSAppleScript.errorNumber] as? Int)
    }
}
