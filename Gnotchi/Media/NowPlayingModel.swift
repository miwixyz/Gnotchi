import AppKit
import Observation

/// Was die Insel zeigt. Eine Instanz für alle Bildschirme.
@MainActor
@Observable
final class NowPlayingModel {

    nonisolated static let pauseHide: TimeInterval = 5
    /// Halbe Browser-Meldung: so lange auf die vollständige warten (Mitschnitt 18.10.).
    static let completeWait: Duration = .milliseconds(300)

    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    private(set) var isVisible = false
    /// nil = Adapter läuft oder startet; sonst Grund für den Hinweis in den Einstellungen.
    private(set) var unavailableReason: String?

    @ObservationIgnored private let adapter = MediaAdapter()
    /// Wartefrist für unvollständige Meldungen; läuft ab der ERSTEN unvollständigen Meldung.
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// Die jeweils neueste unvollständige Meldung innerhalb der laufenden Frist.
    @ObservationIgnored private var pendingInfo: NowPlayingInfo?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var pausedSince: Date?
    /// Schlüssel des Titels, dessen Cover gerade gilt (oder dekodiert wird).
    @ObservationIgnored private var shownArtworkKey: String?
    /// Schlüssel, für den schon ein Dekodieren gestartet wurde – auch ein gescheitertes wird nicht je Meldung wiederholt.
    @ObservationIgnored private var decodeStartedKey: String?

    init() {
        adapter.onInfo = { [weak self] i in self?.receive(i) }
        adapter.onState = { [weak self] s in
            if case .unavailable(let r) = s { self?.unavailableReason = r } else { self?.unavailableReason = nil }
        }
    }

    func start() { adapter.start() }

    func stop() {
        // unavailableReason bleibt absichtlich stehen: Der Hinweis gehört zum Adapter-Zustand, nicht zum Titel.
        pending?.cancel()
        pending = nil
        pendingInfo = nil
        adapter.stop()
        apply(nil)
    }

    func playPause() { adapter.perform(.send(.toggle)) }
    func next() { adapter.perform(.send(.next)) }
    func previous() { adapter.perform(.send(.previous)) }
    func seek(to seconds: TimeInterval) { adapter.perform(.seek(seconds)) }

    nonisolated static func isVisible(hasInfo: Bool, playing: Bool, pausedSince: Date?, now: Date) -> Bool {
        guard hasInfo else { return false }
        if playing { return true }
        guard let p = pausedSince else { return false }
        return now.timeIntervalSince(p) < pauseHide
    }

    /// Unvollständige Meldungen (Browser, Livestream) warten höchstens 300 ms auf die vollständige.
    /// Die Frist startet nur bei der ersten; spätere ersetzen nur den Inhalt. Sonst würde eine
    /// Quelle, die schneller als alle 300 ms meldet (Livestream ohne Dauer), nie angezeigt.
    private func receive(_ new: NowPlayingInfo?) {
        guard let new, new.isIncomplete else {
            pending?.cancel()
            pending = nil
            pendingInfo = nil
            return apply(new)
        }
        pendingInfo = new
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.completeWait)
            guard !Task.isCancelled else { return }
            self?.flushPending()
        }
    }

    private func flushPending() {
        let latest = pendingInfo
        pending = nil
        pendingInfo = nil
        apply(latest)
    }

    private func apply(_ new: NowPlayingInfo?) {
        let wasPlaying = info?.isPlaying ?? false
        info = new
        pausedSince = Self.nextPausedSince(hasInfo: new != nil, isPlaying: new?.isPlaying ?? false,
                                           wasPlaying: wasPlaying, current: pausedSince, now: Date())
        updateArtwork(new)
        updateVisibility()
    }

    /// Seit wann pausiert: Wiedergabe → Pause setzt `now`, Pause → Pause behält den Zeitpunkt
    /// (sonst verlängerte jede Meldung die 5 s), Spielen oder nichts → nil.
    nonisolated static func nextPausedSince(hasInfo: Bool, isPlaying: Bool, wasPlaying: Bool,
                                            current: Date?, now: Date) -> Date? {
        guard hasInfo, !isPlaying else { return nil }
        return wasPlaying ? now : (current ?? now)
    }

    /// Titel-Identität fürs Cover: gleiche App + gleicher Titel (bzw. contentID) + gleicher Interpret.
    nonisolated static func artworkKey(for info: NowPlayingInfo?) -> String? {
        info.map { "\($0.appBundleID ?? "")|\($0.contentID ?? $0.title)|\($0.artist ?? "")" }
    }

    /// G6: Cover dekodieren dauert bis ~0,3 s – nie auf dem Hauptthread. Anderer Titel: Cover sofort leeren.
    /// Gleicher Titel: vorhandenes Cover behalten, ein fehlendes nachladen, sobald eine Meldung eins mitbringt.
    /// Ein Ergebnis für einen schon abgelösten Titel wird verworfen.
    private func updateArtwork(_ new: NowPlayingInfo?) {
        let key = Self.artworkKey(for: new)
        if key != shownArtworkKey {
            shownArtworkKey = key
            decodeStartedKey = nil
            artwork = nil
        }
        guard let key, artwork == nil, decodeStartedKey != key, let base64 = new?.artworkBase64 else { return }
        decodeStartedKey = key
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { Artwork.decode(base64: base64) }.value
            guard let self, self.shownArtworkKey == key, let image else { return }
            self.artwork = NSImage(cgImage: image, size: .zero)
        }
    }

    private func updateVisibility() {
        isVisible = Self.isVisible(hasInfo: info != nil, playing: info?.isPlaying ?? false,
                                   pausedSince: pausedSince, now: Date())
        hideTask?.cancel()
        guard isVisible, let paused = pausedSince else { return }
        let left = Self.pauseHide - Date().timeIntervalSince(paused)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, left)))
            guard !Task.isCancelled else { return }
            self?.updateVisibility()
        }
    }
}
