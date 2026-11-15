import Foundation

/// Meeting-Leiser (0.29.0, SECURE-DESIGN G53, specs/2026-11-15-gnotchi-lautstaerkemixer-meeting-leiser.md Stufe 1): Nutzt eine
/// gewählte Meeting-App das Mikrofon, senkt Gnotchi die Lautstärke von Spotify und Musik auf einen Anteil und blendet sie
/// danach zurück. **Nie leise hängen lassen:** Die ursprüngliche Lautstärke wird gemerkt (in den Einstellungen, nicht nur im
/// Speicher) und beim Ende des Meetings, beim Beenden und beim nächsten Start wiederhergestellt. Ändert Michael die Lautstärke
/// selbst, gilt sein Wert – Gnotchi überschreibt ihn nie.
enum DuckLogic {
    nonisolated static let defaultPercent = 30
    nonisolated static let percentChoices = [20, 30, 50]
    /// Namen, wie macOS sie für die Apps anzeigt (so meldet sie `PrivacyMonitor`).
    nonisolated static let defaultMeetingApps = ["Microsoft Teams", "zoom.us", "FaceTime", "Webex", "Slack"]
    nonisolated static let maxApps = 32
    nonisolated static let maxNameLength = 64
    /// So weit darf die aktuelle Lautstärke vom gesenkten Wert abweichen, ohne dass es als eigene Änderung gilt.
    nonisolated static let tolerance = 3

    struct Saved: Equatable, Sendable {
        let original: Int
        let ducked: Int
    }

    nonisolated static func validPercent(_ v: Any?) -> Int {
        guard let n = v as? Int, percentChoices.contains(n) else { return defaultPercent }
        return n
    }

    /// Gesenkter Wert: Anteil der ursprünglichen Lautstärke, nie höher als sie, nie 0 (das wäre stumm, nicht leiser).
    nonisolated static func target(original: Int, percent: Int) -> Int {
        guard original > 0 else { return 0 }
        return max(1, min(original, Int((Double(original) * Double(percent) / 100).rounded())))
    }

    /// Wiederherstellen nur, wenn die Lautstärke noch beim gesenkten Wert steht – sonst hat Michael sie selbst geändert.
    nonisolated static func shouldRestore(current: Int, ducked: Int) -> Bool {
        abs(current - ducked) <= tolerance
    }

    nonisolated static func isMeeting(micApps: [String], meetingApps: Set<String>) -> Bool {
        let wanted = Set(meetingApps.map { $0.lowercased() })
        return micApps.contains { wanted.contains($0.lowercased()) }
    }

    /// Gespeicherte Namen: nur Texte, getrimmt, nicht leer, nicht zu lang, ohne Steuerzeichen, einmalig, höchstens 32.
    nonisolated static func validApps(_ stored: Any?) -> [String]? {
        guard let list = stored as? [Any] else { return nil }
        var seen = Set<String>(), out: [String] = []
        for case let s as String in list {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= maxNameLength, !t.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
                  seen.insert(t).inserted, out.count < maxApps else { continue }
            out.append(t)
        }
        return out
    }

    /// Gemerkte Lautstärken (Bundle-ID → [vorher, gesenkt]): nur Spotify/Musik, nur 0…100, gesenkt ≤ vorher.
    nonisolated static func decodeSaved(_ stored: Any?, players: [String]) -> [String: Saved] {
        guard let d = stored as? [String: [Int]] else { return [:] }
        var out: [String: Saved] = [:]
        for (id, v) in d where players.contains(id) && v.count == 2 && v.allSatisfy({ (0...100).contains($0) }) && v[1] <= v[0] {
            out[id] = Saved(original: v[0], ducked: v[1])
        }
        return out
    }

    nonisolated static func encodeSaved(_ saved: [String: Saved]) -> [String: [Int]] {
        saved.mapValues { [$0.original, $0.ducked] }
    }
}

/// Zugriff auf die Lautstärke der Player – austauschbar, damit der Ablauf ohne Spotify getestet werden kann.
@MainActor
protocol PlayerVolume: AnyObject {
    var players: [String] { get }
    func volume(_ action: AppleScriptSource.VolumeAction, bundleID: String) async -> Int?
    nonisolated func volumeSync(_ action: AppleScriptSource.VolumeAction, bundleID: String) -> Int?
}

extension AppleScriptSource: PlayerVolume {
    var players: [String] { Self.supported }
    nonisolated func volumeSync(_ action: VolumeAction, bundleID: String) -> Int? { Self.volumeSync(action, bundleID: bundleID) }
}

@MainActor
final class MeetingDucker {
    static let savedKey = "meetingDuckSaved"

    private let player: PlayerVolume
    private let store: UserDefaults
    private let fadeStep: Duration
    private let watchInterval: Duration

    private(set) var enabled = false
    private var percent = DuckLogic.defaultPercent
    private var meetingApps: Set<String> = []
    private var meetingActive = false
    private(set) var saved: [String: DuckLogic.Saved]

    private var watcher: Task<Void, Never>?
    private var current: Task<Void, Never>?
    private var running = false
    private var rerun = false

    init(player: PlayerVolume = AppleScriptSource(), store: UserDefaults = .standard,
         fadeStep: Duration = .milliseconds(100), watchInterval: Duration = .seconds(5)) {
        self.player = player
        self.store = store
        self.fadeStep = fadeStep
        self.watchInterval = watchInterval
        saved = DuckLogic.decodeSaved(store.object(forKey: Self.savedKey), players: player.players)
    }

    /// Einstellungen (Schalter, Anteil, Meeting-Apps). Auch beim Start: Liegt noch eine gemerkte Lautstärke vor, wird sie
    /// wiederhergestellt, sobald kein Meeting läuft.
    func configure(enabled: Bool, percent: Int, apps: Set<String>) {
        self.enabled = enabled
        self.percent = percent
        meetingApps = apps
        reconcile()
    }

    /// Die Apps, die gerade das Mikrofon nutzen (`PrivacyMonitor`).
    func micAppsChanged(_ names: [String]) {
        let now = DuckLogic.isMeeting(micApps: names, meetingApps: meetingApps)
        guard now != meetingActive else { return }
        meetingActive = now
        reconcile()
    }

    /// Für Tests: wartet, bis der laufende Durchgang fertig ist.
    func settle() async { await current?.value }

    /// Beenden: sofort und blockierend wiederherstellen, dort läuft keine Warteschlange mehr.
    func shutdown() {
        watcher?.cancel()
        watcher = nil
        for (id, s) in saved {
            guard let cur = player.volumeSync(.read, bundleID: id) else { continue }   // läuft nicht: bleibt gemerkt
            if DuckLogic.shouldRestore(current: cur, ducked: s.ducked) { _ = player.volumeSync(.set(s.original), bundleID: id) }
            saved[id] = nil
        }
        persist()
    }

    // MARK: Ablauf

    private var wantDuck: Bool { enabled && meetingActive }

    private func reconcile() {
        if wantDuck || !saved.isEmpty {
            if watcher == nil {
                watcher = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: self?.watchInterval ?? .seconds(5))
                        guard !Task.isCancelled, let self else { return }
                        self.requestStep()
                    }
                }
            }
        } else {
            watcher?.cancel()
            watcher = nil
        }
        requestStep()
    }

    private func requestStep() {
        if running { rerun = true; return }
        running = true
        current = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.rerun = false
                await self.step()
            } while self.rerun
            self.running = false
        }
    }

    private func step() async {
        if wantDuck {
            await dropUserOverrides()
            for id in player.players where saved[id] == nil { await duck(id) }
        } else if !saved.isEmpty {
            await restoreAll()
        }
    }

    private func duck(_ id: String) async {
        guard let original = await player.volume(.read, bundleID: id), original > 0 else { return }
        let target = DuckLogic.target(original: original, percent: percent)
        guard target < original else { return }
        // Erst merken, dann senken: Stürzt Gnotchi dazwischen ab, kennt der nächste Start den ursprünglichen Wert.
        saved[id] = DuckLogic.Saved(original: original, ducked: target)
        persist()
        await fade(id, from: original, to: target)
    }

    /// Hat Michael die Lautstärke während des Meetings selbst geändert, gilt sein Wert: nicht mehr anfassen.
    private func dropUserOverrides() async {
        for (id, s) in saved {
            guard let cur = await player.volume(.read, bundleID: id) else { continue }
            if !DuckLogic.shouldRestore(current: cur, ducked: s.ducked) { saved[id] = nil; persist() }
        }
    }

    private func restoreAll() async {
        for (id, s) in saved {
            guard let cur = await player.volume(.read, bundleID: id) else { continue }   // läuft nicht: später noch einmal
            if DuckLogic.shouldRestore(current: cur, ducked: s.ducked) { await fade(id, from: cur, to: s.original) }
            saved[id] = nil
            persist()
        }
    }

    private func fade(_ id: String, from: Int, to: Int) async {
        let steps = 5
        for i in 1...steps {
            _ = await player.volume(.set(from + (to - from) * i / steps), bundleID: id)
            try? await Task.sleep(for: fadeStep)
        }
    }

    private func persist() {
        if saved.isEmpty { store.removeObject(forKey: Self.savedKey) } else { store.set(DuckLogic.encodeSaved(saved), forKey: Self.savedKey) }
    }
}
