import Foundation
import Observation

/// Was die Insel zeigt: Musik und (ab 0.2.0) weitere Aktivitäten. Nur Zusammenfassung – die Quellen
/// laufen getrennt, `AppModel` startet und stoppt sie je Einstellung (specs/2026-10-20-gnotchi-0.2.0.md).
@MainActor
@Observable
final class ActivityModel {

    /// Kurzer Hinweis (Kopfhörer verbunden/getrennt). Gerätenamen vergibt der Nutzer frei → nur
    /// bereinigt übergeben (OutputDevices.cleanName) und als `Text(verbatim:)` zeigen.
    struct Notice: Equatable, Sendable {
        let symbol: String
        let title: String
        let subtitle: String
    }

    /// Mikrofon/Kamera gerade in Gebrauch (0.2.0). App-Namen aus dem lokalen Bundle, nie ins Protokoll.
    struct Privacy: Equatable, Sendable {
        var micApps: [String] = []
        var camera = false

        static let none = Privacy()

        var mic: Bool { !micApps.isEmpty }
        var isActive: Bool { mic || camera }

        /// Kurzform für die kleine Pille ohne Notch.
        var compactLabel: String? {
            switch (mic, camera) {
            case (true, true): "Mikrofon · Kamera"
            case (true, false): "Mikrofon"
            case (false, true): "Kamera"
            case (false, false): nil
            }
        }

        /// Welche Apps das Mikrofon nutzen, für die große Ansicht.
        var micLine: String? { mic ? micApps.joined(separator: ", ") : nil }
    }

    /// Tippi-Diktat (0.2.0): nimmt auf (seit) oder wandelt um.
    enum Recording: Equatable, Sendable {
        case recording(since: Date), transcribing
    }

    let media: NowPlayingModel
    private(set) var recording: Recording?
    /// Pegel getrennt vom Zustand: Nur die Ansicht liest ihn. Die Insel-Steuerung beobachtet `recording` –
    /// läge der Pegel darin, liefe ihr `refresh` (mit Fensterliste) 10×/s.
    private(set) var recordingLevel: Double = 0
    /// Tippis Live-Text (0.3.0, G21). Nur sichtbar, solange `recording` läuft; nie protokollieren.
    private(set) var liveText: String?
    private(set) var notice: Notice?
    private(set) var privacy = Privacy.none
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let noticeDuration: Duration

    /// `noticeDuration` nur für Tests anders als 3 s (Michael 20.10.).
    init(media: NowPlayingModel, noticeDuration: Duration = .seconds(3)) {
        self.media = media
        self.noticeDuration = noticeDuration
    }

    /// Insel sichtbar, sobald irgendetwas zu zeigen ist.
    var isVisible: Bool { media.isVisible || notice != nil || privacy.isActive || recording != nil }

    /// Über Apps im Vollbild nur, was sonst nirgends zu sehen wäre: die Tippi-Aufnahme (Tippi blendet seine
    /// eigene Pille aus, wenn Gnotchi anzeigt). Musik hält sich an die Vollbild-Regel.
    var showsOverFullscreen: Bool { recording != nil }

    func setRecording(_ r: Recording?) {
        if recording != r { recording = r }
        if r == nil, recordingLevel != 0 { recordingLevel = 0 }
        if r == nil, liveText != nil { setLiveText(nil) }
    }

    /// Text ohne laufende Aufnahme wird verworfen: Tippi meldet über distnoted, ob diktiert wird; der
    /// Text allein hält die Insel nicht offen (Tippis Vorschau-Takt hat keine Obergrenze).
    func setLiveText(_ text: String?) {
        let value = (recording == nil || text?.isEmpty == true) ? nil : text
        if liveText != value { liveText = value }
        if hasLiveText != (value != nil) { hasLiveText = value != nil }
    }

    /// Nur „ob“ – die Insel-Steuerung beobachtet das statt des Texts, sonst liefe ihr `refresh`
    /// (mit Fensterliste) bei jedem neuen Wort.
    private(set) var hasLiveText = false

    /// Insel zeigt den Live-Text aufgeklappt (zwei Zeilen, Michael 20.10.).
    var showsLiveText: Bool { recording != nil && hasLiveText }

    func setRecordingLevel(_ level: Double) {
        recordingLevel = level
    }

    /// Hinweis zeigen; ein neuer ersetzt den alten und startet die Dauer neu.
    func post(_ n: Notice) {
        notice = n
        noticeTask?.cancel()
        noticeTask = Task { [weak self, noticeDuration] in
            try? await Task.sleep(for: noticeDuration)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func setPrivacy(_ p: Privacy) {
        if privacy != p { privacy = p }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}
