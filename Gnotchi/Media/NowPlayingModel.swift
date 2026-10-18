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
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var pausedSince: Date?
    @ObservationIgnored private var artworkKey: String?

    init() {
        adapter.onInfo = { [weak self] i in self?.receive(i) }
        adapter.onState = { [weak self] s in
            if case .unavailable(let r) = s { self?.unavailableReason = r } else { self?.unavailableReason = nil }
        }
    }

    func start() { adapter.start() }

    func stop() {
        pending?.cancel()
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

    private func receive(_ new: NowPlayingInfo?) {
        pending?.cancel()
        guard let new, new.isIncomplete else { return apply(new) }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.completeWait)
            guard !Task.isCancelled else { return }
            self?.apply(new)
        }
    }

    private func apply(_ new: NowPlayingInfo?) {
        let wasPlaying = info?.isPlaying ?? false
        info = new
        if let new, !new.isPlaying, wasPlaying || pausedSince == nil { pausedSince = Date() }
        if new?.isPlaying == true || new == nil { pausedSince = nil }
        updateArtwork(new)
        updateVisibility()
    }

    /// G6: Cover dekodieren dauert bis ~0,3 s – nie auf dem Hauptthread. Der Schlüssel entscheidet,
    /// ob überhaupt neu dekodiert wird; ein später fertiges Ergebnis eines schon abgelösten Titels
    /// wird verworfen.
    private func updateArtwork(_ new: NowPlayingInfo?) {
        // „|1“/„|0“: ein Titel, dessen Cover erst mit der vollständigen Meldung kommt, wird nachgeladen.
        let key = new.map { "\($0.appBundleID ?? "")|\($0.contentID ?? $0.title)|\($0.artworkBase64 == nil ? 0 : 1)" }
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        guard let key, let base64 = new?.artworkBase64 else { return }
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { Artwork.decode(base64: base64) }.value
            guard let self, self.artworkKey == key, let image else { return }
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
