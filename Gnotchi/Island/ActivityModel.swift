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
    /// Qotti-Kontingent (0.3.0, G22): nur Zahlen. Hält die Insel nicht offen, nur Zeile in der großen Insel.
    private(set) var quota: QottiLink.Snapshot?
    private(set) var notice: Notice?
    private(set) var privacy = Privacy.none
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let noticeDuration: Duration

    // MARK: Live-Aktivitäten (0.4.0) – Logik in ActivityModel+Rotation.swift

    /// Ton läuft über Bluetooth (Kopfhörer-Aktivität). Gerätename bereinigt (OutputDevices.cleanName).
    private(set) var headphones: Headphones?
    /// Gemeldete Updates der Familien-Apps (G23), in fester Reihenfolge.
    private(set) var familyUpdates: [FamilyUpdates.Entry] = []
    /// Gnotchis eigenes Update (Sparkle), nur bei eingeschaltetem „Updates der App-Familie“.
    private(set) var ownUpdate: FamilyUpdates.Entry?
    /// Nächster Termin aus Kalli (0.5.0, G26), nur ab 15 Minuten vor Beginn bis Beginn gesetzt.
    private(set) var upcomingEvent: KalliEvents.Event?
    /// Spiegel (0.5.0, G27): Schalter in den Einstellungen bzw. gerade groß gezeigt.
    var mirrorEnabled = false
    var mirrorActive = false
    /// Eigener Timer (0.5.0); Logik in CountdownTimer.swift. Nur dort setzen.
    var timer: CountdownTimer?
    /// Timer-Auswahl groß gezeigt (Klick auf das Timer-Symbol, solange keiner läuft).
    var timerPickerActive = false
    @ObservationIgnored var timerTask: Task<Void, Never>?
    /// Abgelaufener Timer: Insel pulsiert, bis man klickt (Michael 21.10.: „Töne zu kurz, man überhört es“).
    var timerAlarm = false
    /// Schalter „Timer-Ablauf bis Klick anzeigen“; aus = kurzer Hinweis + ein Ton wie zuvor.
    var timerAlarmEnabled = true
    @ObservationIgnored var alarmSoundTask: Task<Void, Never>?
    /// Angeheftet (Stecknadel, Michael 21.10.): große Insel bleibt offen, Hintergrund durchscheinendes Glas.
    var pinned = false
    /// Einstellung „Wiedergabe immer groß“: Player bleibt die große Ansicht, andere Aktivitäten als Glas-Schicht.
    var playerFirst = false
    /// Einstellung „Wiedergabe-Knöpfe in der kleinen Insel“: Pause/Wiedergabe und Weiter dauerhaft (statt Pegel).
    var compactControls = false
    /// Einstellung „Aufklappen als Band“ (0.5.0): seitlich breit statt nach unten.
    var bandStyle = false
    /// Bei „Wiedergabe immer groß“: in der Leiste gewählte Aktivität, die über dem Player liegt.
    var overlayActivity: LiveActivity?
    /// Welche Aktivität die kleine Insel gerade zeigt; nil oder nicht mehr aktiv = die erste.
    var rotationCursor: LiveActivity?
    /// Maus über einer Insel: Takt steht.
    var rotationPaused = false
    /// Einstellung „Rotation“: aus = immer die erste Aktivität.
    var rotationEnabled = true
    /// Nach einem Trackwechsel 3 s die breitere Form mit Titel · Interpret.
    var trackFlash = false
    @ObservationIgnored var rotationTask: Task<Void, Never>?
    @ObservationIgnored var flashTask: Task<Void, Never>?
    @ObservationIgnored let rotationInterval: Duration
    @ObservationIgnored let flashDuration: Duration

    /// `noticeDuration`, `rotationInterval`, `flashDuration` nur für Tests anders als 3 s / 4 s / 3 s (Michael 20./21.10.).
    init(media: NowPlayingModel, noticeDuration: Duration = .seconds(3), rotationInterval: Duration = .seconds(4),
         flashDuration: Duration = .seconds(3)) {
        self.media = media
        self.noticeDuration = noticeDuration
        self.rotationInterval = rotationInterval
        self.flashDuration = flashDuration
        media.onTrackChange = { [weak self] in self?.flashTrack() }
    }

    /// Insel sichtbar, sobald irgendetwas zu zeigen ist.
    var isVisible: Bool {
        media.isVisible || notice != nil || privacy.isActive || recording != nil || headphones != nil || !allUpdates.isEmpty
            || upcomingEvent != nil || timer != nil || timerAlarm
    }

    func setHeadphones(_ h: Headphones?) {
        if headphones != h { headphones = h }
    }

    func setFamilyUpdates(_ list: [FamilyUpdates.Entry]) {
        if familyUpdates != list { familyUpdates = list }
    }

    func setUpcomingEvent(_ e: KalliEvents.Event?) {
        if upcomingEvent != e { upcomingEvent = e }
    }

    func setOwnUpdate(_ e: FamilyUpdates.Entry?) {
        if ownUpdate?.version != e?.version { ownUpdate = e }
    }

    /// Über Apps im Vollbild nur, was sonst nirgends zu sehen wäre: die Tippi-Aufnahme (Tippi blendet seine
    /// eigene Pille aus, wenn Gnotchi anzeigt). Musik hält sich an die Vollbild-Regel.
    var showsOverFullscreen: Bool { recording != nil || timerAlarm }

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

    func setQuota(_ q: QottiLink.Snapshot?) {
        if quota != q { quota = q }
    }

    var quotaLine: String? { QottiLink.line(quota) }

    func setPrivacy(_ p: Privacy) {
        if privacy != p { privacy = p }
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        notice = nil
    }
}
