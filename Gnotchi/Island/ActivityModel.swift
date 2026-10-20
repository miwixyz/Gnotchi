import Observation

/// Was die Insel zeigt: Musik und (ab 0.2.0) weitere Aktivitäten. Nur Zusammenfassung – die Quellen
/// laufen getrennt, `AppModel` startet und stoppt sie je Einstellung (specs/2026-10-20-gnotchi-0.2.0.md).
@MainActor
@Observable
final class ActivityModel {

    let media: NowPlayingModel

    init(media: NowPlayingModel) {
        self.media = media
    }

    /// Insel sichtbar, sobald irgendetwas zu zeigen ist.
    var isVisible: Bool { media.isVisible }

    /// Über Apps im Vollbild nur, was sonst nirgends zu sehen wäre. Musik hält sich an die Vollbild-Regel.
    var showsOverFullscreen: Bool { false }
}
