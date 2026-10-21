import Foundation

/// Eine Aktivität der kleinen Insel (0.4.0, specs/2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md). Aufnahme und
/// Hinweise gehören nicht dazu: Sie rotieren nicht mit, sie verdrängen.
enum LiveActivity: Hashable, Sendable {
    case media, headphones
    case update(FamilyApp)
}

/// Bluetooth-Ausgang als dauerhafte Aktivität: nur Symbol und bereinigter Gerätename (kein Akku, G19).
struct Headphones: Equatable, Sendable {
    let name: String
    let symbol: String
}

extension ActivityModel {

    // MARK: Reine Teile (getestet)

    /// Feste Reihenfolge: Medien, Kopfhörer, Updates der Familie.
    nonisolated static func rotationItems(media: Bool, headphones: Bool, updates: [FamilyApp]) -> [LiveActivity] {
        (media ? [.media] : []) + (headphones ? [.headphones] : []) + updates.map(LiveActivity.update)
    }

    /// Was gerade zu sehen ist: der Zeiger, solange seine Aktivität noch läuft und die Rotation an ist, sonst die erste.
    nonisolated static func resolve(cursor: LiveActivity?, items: [LiveActivity], enabled: Bool) -> LiveActivity? {
        guard enabled, let cursor, items.contains(cursor) else { return items.first }
        return cursor
    }

    /// Ein Takt: zur nächsten Aktivität (im Kreis). Steht bei Pause, ausgeschalteter Rotation oder nur einer Aktivität.
    nonisolated static func advance(cursor: LiveActivity?, items: [LiveActivity], paused: Bool,
                                    enabled: Bool) -> LiveActivity? {
        let current = resolve(cursor: cursor, items: items, enabled: enabled)
        guard enabled, !paused, items.count > 1, let current, let i = items.firstIndex(of: current) else { return current }
        return items[(i + 1) % items.count]
    }

    // MARK: Zustand

    /// Updates der Familie und Gnotchis eigenes, in fester Reihenfolge.
    var allUpdates: [FamilyUpdates.Entry] {
        familyUpdates + (ownUpdate.map { [$0] } ?? [])
    }

    var rotationItems: [LiveActivity] {
        Self.rotationItems(media: media.isVisible, headphones: headphones != nil, updates: allUpdates.map(\.app))
    }

    /// Aktivität der kleinen Insel.
    var currentActivity: LiveActivity? {
        Self.resolve(cursor: rotationCursor, items: rotationItems, enabled: rotationEnabled)
    }

    func update(for app: FamilyApp) -> FamilyUpdates.Entry? {
        allUpdates.first { $0.app == app }
    }

    /// Breitere Form beim Trackwechsel: nur, solange die Musik auch die gezeigte Aktivität ist.
    var showsTrackFlash: Bool { trackFlash && currentActivity == .media && media.info != nil }

    // MARK: Ablauf

    /// Takt starten (IslandController.start). Wacht alle 4 s auf; wechselt nur bei mehr als einer Aktivität.
    func startRotation() {
        guard rotationTask == nil else { return }
        rotationTask = Task { [weak self, rotationInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: rotationInterval)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    func stopRotation() {
        rotationTask?.cancel()
        rotationTask = nil
        flashTask?.cancel()
        flashTask = nil
        trackFlash = false
        rotationPaused = false
        rotationCursor = nil
    }

    func tick() {
        let next = Self.advance(cursor: rotationCursor, items: rotationItems, paused: rotationPaused || trackFlash,
                                enabled: rotationEnabled)
        if next != rotationCursor { rotationCursor = next }
    }

    func setRotationPaused(_ paused: Bool) {
        if rotationPaused != paused { rotationPaused = paused }
    }

    func setRotationEnabled(_ on: Bool) {
        if rotationEnabled != on { rotationEnabled = on }
    }

    /// Trackwechsel (NowPlayingModel.onTrackChange): Musik nach vorn und 3 s breiter.
    func flashTrack() {
        rotationCursor = .media
        trackFlash = true
        flashTask?.cancel()
        flashTask = Task { [weak self, flashDuration] in
            try? await Task.sleep(for: flashDuration)
            guard !Task.isCancelled else { return }
            self?.trackFlash = false
        }
    }
}
