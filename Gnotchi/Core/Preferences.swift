import Foundation
import Observation

/// Einstellungen. Nur Schalter, keine Daten fremder Apps (docs/SECURE-DESIGN.md G14):
/// Titel, Interpret und Cover werden nie gespeichert.
@MainActor
@Observable
final class Preferences {

    enum Key {
        static let notchMedia = "notchMedia"
        /// 0.15.0 Musik auf dem Schreibtisch: Schalter (ab Werk aus), Ecke, Größe.
        static let desktopMusic = "desktopMusic"
        /// 0.17.0: Darstellung (Karte | Plattenspieler) und Bildschirm des Plattenspielers.
        static let desktopMusicStyle = "desktopMusicStyle"
        static let desktopMusicScreen = "desktopMusicScreen"
        static let desktopMusicNeon = "desktopMusicNeon"
        static let desktopMusicTonearm = "desktopMusicTonearm"
        /// Abstand des Covers zur gewählten Ecke (nach dem Ziehen), x/y in Punkten.
        /// 0.20.0 Musik auf dem Sperrbildschirm (ab Werk aus) und „Titel verbergen“.
        static let lockScreenMusic = "lockScreenMusic"
        static let lockScreenHideTitle = "lockScreenHideTitle"
        static let expandDelay = "expandDelay"
        static let headphoneNotice = "headphoneNotice"
        static let micCamera = "micCamera"
        /// Tippi liest diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let tippiRecording = "tippiRecording"
        /// Qotti liest diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let qottiQuota = "qottiQuota"
        static let tippiDevice = "tippiDevice"
        /// 0.4.0 Live-Aktivitäten.
        static let liveRotation = "liveRotation"
        static let headphoneActivity = "headphoneActivity"
        /// Familien-Apps lesen diesen Schlüssel (CFPreferences, Domäne dev.mwlr.gnotchi) – nicht umbenennen.
        static let familyUpdates = "familyUpdates"
        /// 0.5.0 Termine aus Kalli (G26).
        static let kalliEvents = "kalliEvents"
        /// 0.5.0 Spiegel (G27).
        static let mirror = "mirror"
        /// 0.5.0 Ton bei Ablauf des Timers (Name aus CountdownTimer.sounds oder familySound, leer = kein Ton).
        static let timerSound = "timerSound"
        /// 0.5.0 Timer-Ablauf: Insel pulsiert bis Klick (aus = kurzer Hinweis).
        static let timerAlarm = "timerAlarm"
        /// 0.5.0 Wiedergabe immer groß (Player als Grundlage, andere Aktivitäten als Glas darüber).
        static let playerFirst = "playerFirst"
        /// 0.5.0 Wiedergabe-Knöpfe in der kleinen Insel.
        static let compactControls = "compactControls"
        /// 0.28.0 Tasten-Ring um die große Insel: Hauptschalter und eingeschaltete Tasten (nur bekannte Kennungen).
        static let ring = "ring"
        static let ringButtons = "ringButtons"
        /// 0.28.0 Mikrofon-Taste immer zeigen (sonst nur im Meeting).
        static let ringMicAlways = "ringMicAlways"
        /// 0.28.0 Batterie in der Ruhe-Insel.
        static let batteryIdle = "batteryIdle"
        /// 0.29.0 Meeting-Leiser (G53): Schalter, Anteil, Meeting-Apps (nur Namen).
        static let meetingDuck = "meetingDuck"
        static let meetingDuckPercent = "meetingDuckPercent"
        static let meetingApps = "meetingApps"
        /// 0.30.0 Mixer Stufe 2 (G55): Regler je App über Prozess-Taps (Freigabe „Audio-Aufnahme“). Ab Werk aus.
        static let appVolume = "appVolume"
        /// 0.5.0 Aufklappen als Band.
        static let bandStyle = "bandStyle"
        /// Medienfilter: nur Bundle-IDs (G25).
        static let mediaExcluded = "mediaExcluded"
        /// 0.6.0 Mitteilungen und Anrufe in der Notch (G28–G30): Schalter, App-Liste (nur Kennungen), Anrufe.
        static let notifications = "notifications"
        static let notifyApps = "notifyApps"
        static let notifyCalls = "notifyCalls"
        /// 0.9.0 Ungelesen-Zahlen aus dem Dock (G33).
        static let notifyBadges = "notifyBadges"
        static let compactUnread = "compactUnread"
        /// 0.9.0 Code & KI (G34/G35): Claude-Code-Sitzungen in der Notch.
        static let claudeCode = "claudeCode"
        static let terminal = "terminal"
        /// 0.35.0 Stream Deck (G59): Socket für das eigene Plugin. Ab Werk aus.
        static let streamDeck = "streamDeck"
        /// Stream Deck, Browser-Weg (G59 Punkt 10): YouTube in Browsern gezielt steuern (Chrome, Edge, Helium, Safari). Ab Werk aus.
        static let deckBrowserTab = "deckBrowserTab"
        /// Stream Deck, Cover auf den Tasten (G59 Punkt 10e). Ab Werk aus.
        static let deckCover = "deckCover"
        /// 0.7.0 Wetter (G31): Schalter, gewählter Ort (Name, Region, Land, gerundete Koordinaten), Einheit.
        static let weather = "weather"
        static let weatherPlace = "weatherPlace"
        static let weatherUnit = "weatherUnit"
        /// 0.8.0 Dateiablage (G32): Schalter, nach dem Rausziehen entfernen.
        static let shelf = "shelf"
        static let shelfRemoveOnDrag = "shelfRemoveOnDrag"
        static let shelfPreview = "shelfPreview"
        static let shelfStripLocation = "shelfStripLocation"
        static let shelfScreenshots = "shelfScreenshots"
        /// 0.16.0: Bildschirmfotos nach so vielen Minuten aus der Ablage nehmen (0 = behalten).
        static let shelfScreenshotMinutes = "shelfScreenshotMinutes"
        /// 0.16.0: ruhige Insel ohne Notch.
        static let quietIsland = "quietIsland"
        /// Bildschirme (UUID), auf denen die Insel nicht erscheint. Leer = überall (ab Werk).
        static let islandHiddenScreens = "islandHiddenScreens"
        /// 0.11.0 Zwischenablage (G37–G41): Schalter, ausgeschlossene Apps, Pause, Seitenansicht, Tastenkürzel.
        static let clipboard = "clipboard"
        static let clipboardExcluded = "clipboardExcluded"
        static let clipboardPausedUntil = "clipboardPausedUntil"
        static let clipboardPanelEdge = "clipboardPanelEdge"
        static let clipboardPanelHotKey = "clipboardPanelHotKey"
        /// G60: Kürzel „Als reinen Text einfügen“, eigener Schalter (ab Werk aus) und Kombination.
        static let plainPaste = "plainPaste"
        static let plainPasteHotKey = "plainPasteHotKey"
        /// Schnelleingabe (G61): eigener Schalter (ab Werk aus) und Kombination.
        static let quickEntry = "quickEntry"
        static let quickEntryHotKey = "quickEntryHotKey"
        /// 0.13.0 Geheimnisse (G43): Schalter, „an seit“, wie viele gespeicherte Geheimnisse schon angeboten wurden.
        /// 0.14.0: Kürzel klappt zuerst aus der Notch herunter, nochmal → große Ansicht am Rand.
        static let clipboardNotchFirst = "clipboardNotchFirst"
        static let clipboardSecrets = "clipboardSecrets"
        static let clipboardSecretsSince = "clipboardSecretsSince"
        static let clipboardSecretsOffered = "clipboardSecretsOffered"
        static let clipboardImageText = "clipboardImageText"
    }

    /// G25: höchstens so viele ausgeschlossene Apps, je Kennung höchstens so lang.
    nonisolated static let maxExcluded = 64
    nonisolated static let maxBundleIDLength = 255

    /// Auswahl „Aufklappen nach“ in Sekunden (Sofort, 0,3 s, 0,6 s, 1 s).
    nonisolated static let expandDelayChoices: [TimeInterval] = [0, 0.3, 0.6, 1.0]
    nonisolated static let defaultExpandDelay: TimeInterval = 0.6

    /// Auswahl „Bildschirmfotos behalten“ in Minuten; 0 = bis man sie selbst entfernt (0.16.0).
    nonisolated static let screenshotMinuteChoices = [5, 15, 30, 60, 0]
    nonisolated static let defaultScreenshotMinutes = 30

    private let defaults: UserDefaults

    /// Musik in der Notch zeigen. Ab Werk an. Aus = weder Adapter noch Insel laufen
    /// (`AppModel.applyNotchSetting`).
    var notchMedia: Bool { didSet { defaults.set(notchMedia, forKey: Key.notchMedia) } }
    /// 0.15.0: Cover + Titel hinter allen Fenstern auf dem Schreibtisch. Ab Werk **aus** (neue Bildschirmfläche).
    var desktopMusic: Bool { didSet { defaults.set(desktopMusic, forKey: Key.desktopMusic) } }
    /// 0.17.0 (Michael 27.10.): Darstellung, ab Werk Karte – seit 0.26.0 das echte Widget (G49).
    var desktopMusicStyle: DesktopStyle { didSet { defaults.set(desktopMusicStyle.rawValue, forKey: Key.desktopMusicStyle) } }
    /// Bildschirm des Plattenspielers als UUID (CGDisplay, übersteht Neustarts); leer = Hauptbildschirm.
    var desktopMusicScreen: String { didSet { defaults.set(desktopMusicScreen, forKey: Key.desktopMusicScreen) } }
    /// Neonschrift „NOW PLAYING“ über dem Plattenspieler (Michael 27.10.: „optional“), ab Werk an.
    var desktopMusicNeon: Bool { didSet { defaults.set(desktopMusicNeon, forKey: Key.desktopMusicNeon) } }
    /// Start/Stopp-Knopf am Plattenspieler (0.17.2, vorher Tonarm anfassen; Schlüssel bleibt), ab Werk aus – sonst pausiert
    /// ein Klick aus Versehen.
    var desktopMusicTonearm: Bool { didSet { defaults.set(desktopMusicTonearm, forKey: Key.desktopMusicTonearm) } }
    /// 0.20.0: Karte auf dem Sperrbildschirm (G46). Ab Werk **aus** – jeder am gesperrten Mac sieht und steuert sie.
    var lockScreenMusic: Bool { didSet { defaults.set(lockScreenMusic, forKey: Key.lockScreenMusic) } }
    /// Nur Musiknote und Knöpfe, kein Cover, kein Text (Michael 06.11.). Ab Werk aus.
    var lockScreenHideTitle: Bool { didSet { defaults.set(lockScreenHideTitle, forKey: Key.lockScreenHideTitle) } }
    /// 0.17.0: Karte (seit 0.26.0 echtes Widget, G49) oder Plattenspieler mittig mit Farbverlauf.
    enum DesktopStyle: String, CaseIterable { case card, turntable }

    /// Wie lange die Maus über der kleinen Insel bleiben muss, bevor sie aufgeht (Michael, 18.10.:
    /// „damit das Überfahren nicht zu schnell auslöst und stört“). Wirkt sofort, ohne Neustart.
    var expandDelay: TimeInterval { didSet { defaults.set(expandDelay, forKey: Key.expandDelay) } }

    /// Kopfhörer verbunden/getrennt 3 s in der Insel zeigen (0.2.0). Ab Werk an.
    var headphoneNotice: Bool { didSet { defaults.set(headphoneNotice, forKey: Key.headphoneNotice) } }

    /// Punkt an der Insel, solange eine App Mikrofon oder Kamera nutzt (0.2.0). Ab Werk an.
    var micCamera: Bool { didSet { defaults.set(micCamera, forKey: Key.micCamera) } }

    /// Tippis Diktat in der Insel zeigen; Tippi blendet dann seine eigene Pille aus (0.2.0). Ab Werk an.
    var tippiRecording: Bool { didSet { defaults.set(tippiRecording, forKey: Key.tippiRecording) } }

    /// Qotti-Kontingent: Warnung bei 80/95 %/Drosselung, Zeile in der großen Insel (0.3.0). Ab Werk an.
    var qottiQuota: Bool { didSet { defaults.set(qottiQuota, forKey: Key.qottiQuota) } }
    /// 0.41.0 (G62): „Läuft gerade“ an Tippis Schreibtischgerät, ab Werk aus.
    var tippiDevice: Bool { didSet { defaults.set(tippiDevice, forKey: Key.tippiDevice) } }

    /// Kleine Insel wechselt alle 4 s zwischen den Aktivitäten (0.4.0). Aus = immer die erste. Ab Werk an.
    var liveRotation: Bool { didSet { defaults.set(liveRotation, forKey: Key.liveRotation) } }

    /// Solange der Ton über Bluetooth läuft, ist das eine eigene Aktivität (0.4.0). Ab Werk an.
    var headphoneActivity: Bool { didSet { defaults.set(headphoneActivity, forKey: Key.headphoneActivity) } }

    /// Updates der App-Familie in der Insel (0.4.0, G23). Ab Werk an.
    var familyUpdates: Bool { didSet { defaults.set(familyUpdates, forKey: Key.familyUpdates) } }

    /// Nächster Termin aus Kalli, 15 Minuten vor Beginn (0.5.0, G26). Aus = Socket weg. Ab Werk an.
    var kalliEvents: Bool { didSet { defaults.set(kalliEvents, forKey: Key.kalliEvents) } }

    /// Spiegel in der großen Insel (0.5.0, G27). Kamera nur nach Klick und nur, solange er sichtbar ist. Ab Werk an.
    var mirror: Bool { didSet { defaults.set(mirror, forKey: Key.mirror) } }

    /// Timer-Ablauf bis Klick anzeigen (0.5.0): Insel pulsiert, Ton wiederholt sich höchstens 1 Minute. Ab Werk an.
    var timerAlarm: Bool { didSet { defaults.set(timerAlarm, forKey: Key.timerAlarm) } }

    /// Wiedergabe immer groß (0.5.0): Player bleibt die große Ansicht, andere Aktivitäten als Glas-Schicht. Ab Werk aus.
    var playerFirst: Bool { didSet { defaults.set(playerFirst, forKey: Key.playerFirst) } }

    /// Wiedergabe-Knöpfe (Pause/Wiedergabe, Weiter) dauerhaft in der kleinen Insel (0.5.0). Ab Werk aus.
    var compactControls: Bool { didSet { defaults.set(compactControls, forKey: Key.compactControls) } }

    /// Tasten-Ring (0.28.0): Werkzeuge als runde Tasten um die große Insel. Ab Werk an; aus = die alte Symbolleiste.
    var ring: Bool { didSet { defaults.set(ring, forKey: Key.ring) } }

    /// Eingeschaltete Ring-Tasten (0.28.0). Gespeichert als Liste von Kennungen; fehlt sie, gelten die Standardtasten.
    private(set) var ringButtons: Set<RingButton> {
        didSet { defaults.set(ringButtons.map(\.rawValue).sorted(), forKey: Key.ringButtons) }
    }

    /// Mikrofon-Taste immer zeigen (0.28.0). Ab Werk aus: Sie erscheint nur, solange eine App das Mikrofon nutzt.
    var ringMicAlways: Bool { didSet { defaults.set(ringMicAlways, forKey: Key.ringMicAlways) } }

    /// Batterie (Prozent, Laden) in der Ruhe-Insel (0.28.0). Ab Werk aus; auf Macs ohne Batterie wirkungslos.
    var batteryIdle: Bool { didSet { defaults.set(batteryIdle, forKey: Key.batteryIdle) } }

    /// Meeting-Leiser (0.29.0): Spotify und Musik leiser, solange eine Meeting-App das Mikrofon nutzt. Ab Werk aus.
    var meetingDuck: Bool { didSet { defaults.set(meetingDuck, forKey: Key.meetingDuck) } }
    /// Auf wie viel Prozent der Lautstärke gesenkt wird (20, 30 oder 50).
    var meetingDuckPercent: Int { didSet { defaults.set(meetingDuckPercent, forKey: Key.meetingDuckPercent) } }
    /// Lautstärke je App über Prozess-Taps (Stufe 2). Ab Werk aus; braucht die Freigabe „Audio-Aufnahme“, erst beim ersten Ziehen gefragt.
    var appVolume: Bool { didSet { defaults.set(appVolume, forKey: Key.appVolume) } }
    /// Namen der Apps, die als Meeting zählen (so zeigt macOS sie an).
    private(set) var meetingApps: [String] { didSet { defaults.set(meetingApps, forKey: Key.meetingApps) } }

    func setMeetingApp(_ name: String, on: Bool) {
        var list = meetingApps.filter { $0 != name }
        if on { list.append(name) }
        let valid = DuckLogic.validApps(list) ?? []
        if valid != meetingApps { meetingApps = valid }
    }

    func isRingButtonOn(_ b: RingButton) -> Bool { b.alwaysOn || ringButtons.contains(b) }

    func setRingButton(_ b: RingButton, on: Bool) {
        guard !b.alwaysOn else { return }
        var s = ringButtons
        if on { s.insert(b) } else { s.remove(b) }
        if s != ringButtons { ringButtons = s }
    }

    /// Aufklappen als Band (0.5.0): seitlich breit in Menüleisten-Höhe statt nach unten. Ab Werk aus (Insel).
    var bandStyle: Bool { didSet { defaults.set(bandStyle, forKey: Key.bandStyle) } }

    /// Ton bei Ablauf des Timers (0.5.0). Nur Namen aus `CountdownTimer.sounds` oder `familySound`; leer = kein Ton.
    var timerSound: String {
        didSet {
            let valid = CountdownTimer.validSound(timerSound)
            if valid != timerSound { timerSound = valid; return }
            defaults.set(timerSound, forKey: Key.timerSound)
        }
    }

    /// Medienfilter (0.4.0, G25): Wiedergabe dieser Apps erscheint nie in der Insel. Nur über `setMediaExcluded`.
    private(set) var mediaExcluded: [String] { didSet { defaults.set(mediaExcluded, forKey: Key.mediaExcluded) } }

    /// Mitteilungen in der Notch (0.6.0). Ab Werk **aus**: braucht das Hilfsprogramm mit Bedienungshilfen (G28).
    var notifications: Bool { didSet { defaults.set(notifications, forKey: Key.notifications) } }
    /// Anrufe in der Notch (0.6.0), wirkt nur bei eingeschalteten Mitteilungen.
    var notifyCalls: Bool { didSet { defaults.set(notifyCalls, forKey: Key.notifyCalls) } }
    /// Ungelesen-Zahlen der ausgewählten Apps (0.9.0, G33), wirkt nur bei eingeschalteten Mitteilungen. Ab Werk aus.
    var notifyBadges: Bool { didSet { defaults.set(notifyBadges, forKey: Key.notifyBadges) } }
    /// Zähler auch in der kleinen Insel (0.9.0). Ab Werk an, wirkt nur mit `notifyBadges`.
    var compactUnread: Bool { didSet { defaults.set(compactUnread, forKey: Key.compactUnread) } }
    /// Claude-Code-Sitzungen in der Notch (0.9.0). Ab Werk **aus**: trägt Hooks in `~/.claude/settings.json` ein (G35).
    var claudeCode: Bool { didSet { defaults.set(claudeCode, forKey: Key.claudeCode) } }
    /// Terminalfenster (0.44.0, G65): Knopf in den Funktionen, der „Gnotchi Terminal“ öffnet. Ab Werk **aus**; aus = kein Knopf.
    var terminal: Bool { didSet { defaults.set(terminal, forKey: Key.terminal) } }
    /// Stream Deck (0.35.0, G59): Befehle vom eigenen, geprüften Plugin. Ab Werk **aus**; aus = kein Socket.
    var streamDeck: Bool { didSet { defaults.set(streamDeck, forKey: Key.streamDeck) } }
    /// Stream Deck: Play/Pause und Titel für YouTube in Browsern per Apple Events am Tab (G59 Punkt 10). Ab Werk **aus**.
    var deckBrowserTab: Bool { didSet { defaults.set(deckBrowserTab, forKey: Key.deckBrowserTab) } }
    /// Stream Deck: Cover auf der Wiedergabe-Taste (G59 Punkt 10e). Ab Werk **aus**: das Bild geht an Elgatos Prozess.
    var deckCover: Bool { didSet { defaults.set(deckCover, forKey: Key.deckCover) } }
    /// Apps, deren Mitteilungen in die Notch dürfen (G29) – nur Kennungen, gleiche Regeln wie G25. Nur über
    /// `setNotifyApp`; `nil` = noch nie eingeschaltet (dann schlägt Gnotchi einmal Nachrichten-Apps vor).
    private(set) var notifyApps: [String]? { didSet { defaults.set(notifyApps, forKey: Key.notifyApps) } }

    /// Wetter in der Notch (0.7.0). Ab Werk **aus**: erster Netzzugriff außer Updates (G31).
    var weather: Bool { didSet { defaults.set(weather, forKey: Key.weather) } }
    /// Dateiablage (0.8.0). Ab Werk an: keine Freigabe, kein Netz (G32).
    var shelf: Bool { didSet { defaults.set(shelf, forKey: Key.shelf) } }
    var shelfRemoveOnDrag: Bool { didSet { defaults.set(shelfRemoveOnDrag, forKey: Key.shelfRemoveOnDrag) } }
    /// 0.42.0 (G64): größere Vorschau in der Insel, wenn der Zeiger auf einer Bild- oder PDF-Kachel ruht. Ab Werk an.
    var shelfPreview: Bool { didSet { defaults.set(shelfPreview, forKey: Key.shelfPreview) } }
    /// 0.43.0 (G63): beim Umwandeln von Bildern Orts- und Kameradaten entfernen. Ab Werk an (Michael 23.11.).
    var shelfStripLocation: Bool { didSet { defaults.set(shelfStripLocation, forKey: Key.shelfStripLocation) } }
    /// 0.10.0 (G36): Bildschirmfotos automatisch ablegen. Ab Werk aus (Michael 23.10.).
    var shelfScreenshots: Bool { didSet { defaults.set(shelfScreenshots, forKey: Key.shelfScreenshots) } }
    /// 0.16.0 (Michael 27.10.): automatisch abgelegte Bildschirmfotos nach so vielen Minuten nur aus der Ablage
    /// nehmen – die Datei bleibt. 0 = behalten.
    var shelfScreenshotMinutes: Int { didSet { defaults.set(shelfScreenshotMinutes, forKey: Key.shelfScreenshotMinutes) } }
    /// 0.16.0 (Michael 27.10.): ohne Hardware-Notch und ohne Live-Aktivität sieht die Insel aus wie die Menüleiste
    /// statt schwarz. Ab Werk an.
    var quietIsland: Bool { didSet { defaults.set(quietIsland, forKey: Key.quietIsland) } }
    /// Bildschirme ohne Insel (UUID). Nur über `setIslandScreen`; ein abgesteckter Bildschirm bleibt eingetragen.
    private(set) var islandHiddenScreens: [String] { didSet { defaults.set(islandHiddenScreens, forKey: Key.islandHiddenScreens) } }
    var weatherUnit: Weather.Unit { didSet { defaults.set(weatherUnit.rawValue, forKey: Key.weatherUnit) } }
    /// 0.11.0 Zwischenablage-Verlauf (G37). Ab Werk **aus**: liest mit, was der Nutzer kopiert (Michael 24.10.).
    var clipboard: Bool { didSet { defaults.set(clipboard, forKey: Key.clipboard) } }
    /// Apps, aus denen nie etwas in den Verlauf kommt (nur Kennungen, Regeln wie G25).
    private(set) var clipboardExcluded: [String] {
        didSet { defaults.set(clipboardExcluded, forKey: Key.clipboardExcluded) }
    }
    /// „30 Min. nicht mitlesen“ – bis zu diesem Zeitpunkt; nil = läuft.
    var clipboardPausedUntil: Date? {
        didSet { defaults.set(clipboardPausedUntil, forKey: Key.clipboardPausedUntil) }
    }
    var clipboardPanelEdge: PanelEdge { didSet { defaults.set(clipboardPanelEdge.rawValue, forKey: Key.clipboardPanelEdge) } }
    /// Seitenansicht öffnen (Vorschlag Ctrl+<, Tastencode wird aufgenommen, nicht fest eingetragen – 24.10. gemessen).
    var clipboardPanelHotKey: HotKey? {
        didSet { defaults.set(clipboardPanelHotKey?.stored, forKey: Key.clipboardPanelHotKey) }
    }
    /// G60: ⇧⌘V (Vorschlag) fügt die aktuelle Kopie als reinen Text ein, danach Original zurück. Ab Werk aus.
    var plainPaste: Bool { didSet { defaults.set(plainPaste, forKey: Key.plainPaste) } }
    var plainPasteHotKey: HotKey? { didSet { defaults.set(plainPasteHotKey?.stored, forKey: Key.plainPasteHotKey) } }
    /// G61: Schnelleingabe in Alltagssprache, gespeichert über Kalli. ⌃⌥N (Vorschlag). Ab Werk aus.
    var quickEntry: Bool { didSet { defaults.set(quickEntry, forKey: Key.quickEntry) } }
    var quickEntryHotKey: HotKey? { didSet { defaults.set(quickEntryHotKey?.stored, forKey: Key.quickEntryHotKey) } }

    /// 0.13.0 (G43): Schlüssel und Tokens erkennen, verdecken, lose nach 5 Min. löschen. Ab Werk **an** – speichert
    /// nur weniger, gibt nichts preis (Michael 26.10.). Einschalten setzt „an seit“ neu (Altbestand: volle 5 Min.).
    var clipboardSecrets: Bool {
        didSet {
            defaults.set(clipboardSecrets, forKey: Key.clipboardSecrets)
            if clipboardSecrets != oldValue { clipboardSecretsSince = clipboardSecrets ? Date() : nil }
        }
    }
    /// G50: Text in Bildern erkennen und durchsuchbar machen (lokal, verschlüsselt). Ab Werk an.
    var clipboardImageText: Bool { didSet { defaults.set(clipboardImageText, forKey: Key.clipboardImageText) } }
    var clipboardSecretsSince: Date? { didSet { defaults.set(clipboardSecretsSince, forKey: Key.clipboardSecretsSince) } }
    /// Anzahl gespeicherter Geheimnisse beim letzten „Später“/Verschieben – das Angebot kommt erst bei mehr wieder.
    var clipboardSecretsOffered: Int { didSet { defaults.set(clipboardSecretsOffered, forKey: Key.clipboardSecretsOffered) } }

    /// Wo die große Ansicht sitzt. `notch` (0.14.0) ist nur intern die heruntergeklappte Stufe – gespeichert wird
    /// nur rechts/links/unten; ob zuerst aus der Notch, entscheidet `clipboardNotchFirst` (Michael 26.10.).
    /// `pointer` (Michael 14.11., aus Hikidashi): große Ansicht dort, wo die Maus steht.
    enum PanelEdge: String, CaseIterable { case right, left, bottom, notch, pointer }
    /// 0.14.0: ⌃< klappt zuerst aus der Notch herunter; nochmal ⌃< oder „Mehr“ → große Ansicht am Rand. Ab Werk an.
    var clipboardNotchFirst: Bool { didSet { defaults.set(clipboardNotchFirst, forKey: Key.clipboardNotchFirst) } }

    /// Tastenkürzel als Carbon-Tastencode + Carbon-Modifikatoren. Gespeichert als zwei Zahlen.
    struct HotKey: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        var stored: [String: Int] { ["key": Int(keyCode), "mods": Int(modifiers)] }
        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
        /// Nur Tastencodes 0…127 und mindestens eine der vier Modifikator-Tasten (sonst würde jede Taste abgefangen).
        init?(stored: Any?) {
            guard let d = stored as? [String: Any], let key = d["key"] as? Int, let mods = d["mods"] as? Int,
                  (0...127).contains(key), mods & Self.allowedModifiers != 0, mods & ~Self.allowedModifiers == 0 else {
                return nil
            }
            self.init(keyCode: UInt32(key), modifiers: UInt32(mods))
        }
        /// cmdKey | shiftKey | optionKey | controlKey (Carbon).
        static let allowedModifiers = 0x0100 | 0x0200 | 0x0800 | 0x1000
    }

    var isClipboardPaused: Bool { (clipboardPausedUntil ?? .distantPast) > Date() }

    func isClipboardExcluded(_ bundleID: String) -> Bool { clipboardExcluded.contains(bundleID) }

    func setClipboardExcluded(_ bundleID: String, _ excluded: Bool) {
        var list = clipboardExcluded.filter { $0 != bundleID }
        if excluded { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != clipboardExcluded { clipboardExcluded = valid }
    }
    /// Gewählter Ort; nur über die Ortssuche gesetzt. Gespeichert nur Name, Region, Land, gerundete Koordinaten.
    var weatherPlace: Weather.Place? {
        didSet {
            guard let p = weatherPlace else { return defaults.removeObject(forKey: Key.weatherPlace) }
            defaults.set(["name": p.name, "region": p.region, "country": p.country, "lat": p.latitude, "lon": p.longitude],
                         forKey: Key.weatherPlace)
        }
    }

    // swiftlint:disable:next function_body_length
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` statt `bool(forKey:)`: ein fehlender Eintrag heißt „ab Werk“ (an),
        // nicht „aus“.
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
        desktopMusic = defaults.object(forKey: Key.desktopMusic) as? Bool ?? false
        (desktopMusicStyle, desktopMusicScreen) = (Self.validStyle(defaults), Self.validScreen(defaults))
        ((desktopMusicNeon, desktopMusicTonearm), (lockScreenMusic, lockScreenHideTitle)) = (Self.turntableFlags(defaults), Self.lockFlags(defaults))
        expandDelay = Self.validExpandDelay(defaults.object(forKey: Key.expandDelay))
        headphoneNotice = defaults.object(forKey: Key.headphoneNotice) as? Bool ?? true
        micCamera = defaults.object(forKey: Key.micCamera) as? Bool ?? true
        tippiRecording = defaults.object(forKey: Key.tippiRecording) as? Bool ?? true
        qottiQuota = defaults.object(forKey: Key.qottiQuota) as? Bool ?? true
        tippiDevice = defaults.object(forKey: Key.tippiDevice) as? Bool ?? false
        liveRotation = defaults.object(forKey: Key.liveRotation) as? Bool ?? true
        headphoneActivity = defaults.object(forKey: Key.headphoneActivity) as? Bool ?? true
        familyUpdates = defaults.object(forKey: Key.familyUpdates) as? Bool ?? true
        kalliEvents = defaults.object(forKey: Key.kalliEvents) as? Bool ?? true
        mirror = defaults.object(forKey: Key.mirror) as? Bool ?? true
        timerSound = CountdownTimer.validSound(defaults.object(forKey: Key.timerSound))
        timerAlarm = defaults.object(forKey: Key.timerAlarm) as? Bool ?? true
        playerFirst = defaults.object(forKey: Key.playerFirst) as? Bool ?? false
        compactControls = defaults.object(forKey: Key.compactControls) as? Bool ?? false
        ring = defaults.object(forKey: Key.ring) as? Bool ?? true
        ringButtons = RingButton.valid(defaults.object(forKey: Key.ringButtons)) ?? RingButton.defaults
        ringMicAlways = defaults.object(forKey: Key.ringMicAlways) as? Bool ?? false
        batteryIdle = defaults.object(forKey: Key.batteryIdle) as? Bool ?? false
        meetingDuck = defaults.object(forKey: Key.meetingDuck) as? Bool ?? false
        appVolume = defaults.object(forKey: Key.appVolume) as? Bool ?? false
        meetingDuckPercent = DuckLogic.validPercent(defaults.object(forKey: Key.meetingDuckPercent))
        meetingApps = DuckLogic.validApps(defaults.object(forKey: Key.meetingApps)) ?? DuckLogic.defaultMeetingApps
        bandStyle = defaults.object(forKey: Key.bandStyle) as? Bool ?? false
        mediaExcluded = Self.validExcluded(defaults.object(forKey: Key.mediaExcluded))
        notifications = defaults.object(forKey: Key.notifications) as? Bool ?? false
        notifyCalls = defaults.object(forKey: Key.notifyCalls) as? Bool ?? true
        notifyBadges = defaults.object(forKey: Key.notifyBadges) as? Bool ?? false
        compactUnread = defaults.object(forKey: Key.compactUnread) as? Bool ?? true
        claudeCode = defaults.object(forKey: Key.claudeCode) as? Bool ?? false
        terminal = defaults.object(forKey: Key.terminal) as? Bool ?? false
        streamDeck = defaults.object(forKey: Key.streamDeck) as? Bool ?? false
        deckBrowserTab = defaults.object(forKey: Key.deckBrowserTab) as? Bool ?? false
        deckCover = defaults.object(forKey: Key.deckCover) as? Bool ?? false
        notifyApps = defaults.object(forKey: Key.notifyApps).map { Self.validExcluded($0) }
        weather = defaults.object(forKey: Key.weather) as? Bool ?? false
        shelf = defaults.object(forKey: Key.shelf) as? Bool ?? true
        shelfRemoveOnDrag = defaults.object(forKey: Key.shelfRemoveOnDrag) as? Bool ?? true
        shelfPreview = defaults.object(forKey: Key.shelfPreview) as? Bool ?? true
        shelfStripLocation = defaults.object(forKey: Key.shelfStripLocation) as? Bool ?? true
        shelfScreenshots = defaults.object(forKey: Key.shelfScreenshots) as? Bool ?? false
        shelfScreenshotMinutes = Self.validScreenshotMinutes(defaults.object(forKey: Key.shelfScreenshotMinutes))
        quietIsland = defaults.object(forKey: Key.quietIsland) as? Bool ?? true
        islandHiddenScreens = Self.validScreens(defaults.object(forKey: Key.islandHiddenScreens))
        weatherUnit = (defaults.string(forKey: Key.weatherUnit)).flatMap(Weather.Unit.init(rawValue:)) ?? .celsius
        weatherPlace = Self.validPlace(defaults.object(forKey: Key.weatherPlace))
        clipboard = defaults.object(forKey: Key.clipboard) as? Bool ?? false
        clipboardExcluded = Self.validExcluded(defaults.object(forKey: Key.clipboardExcluded))
        clipboardPausedUntil = defaults.object(forKey: Key.clipboardPausedUntil) as? Date
        clipboardPanelEdge = defaults.string(forKey: Key.clipboardPanelEdge).flatMap(PanelEdge.init(rawValue:))
            .flatMap { $0 == .notch ? nil : $0 } ?? .right
        clipboardNotchFirst = defaults.object(forKey: Key.clipboardNotchFirst) as? Bool ?? true
        clipboardPanelHotKey = HotKey(stored: defaults.object(forKey: Key.clipboardPanelHotKey))
        plainPaste = defaults.object(forKey: Key.plainPaste) as? Bool ?? false
        plainPasteHotKey = HotKey(stored: defaults.object(forKey: Key.plainPasteHotKey))
        quickEntry = defaults.object(forKey: Key.quickEntry) as? Bool ?? false
        quickEntryHotKey = HotKey(stored: defaults.object(forKey: Key.quickEntryHotKey))
        clipboardSecrets = defaults.object(forKey: Key.clipboardSecrets) as? Bool ?? true
        clipboardImageText = defaults.object(forKey: Key.clipboardImageText) as? Bool ?? true
        clipboardSecretsOffered = max(0, defaults.integer(forKey: Key.clipboardSecretsOffered))
        // Erster Start mit 0.13.0 (oder Wert fehlt): ab jetzt zählen, nie rückwirkend sofort löschen.
        let since = defaults.object(forKey: Key.clipboardSecretsSince) as? Date
        clipboardSecretsSince = clipboardSecrets ? min(since ?? Date(), Date()) : nil
        // didSet läuft in init nicht – sonst bekäme jeder Neustart wieder volle 5 Minuten.
        defaults.set(clipboardSecretsSince, forKey: Key.clipboardSecretsSince)
    }

    /// Gespeicherter Ort nur mit gültigen Werten (per `defaults write` gesetzt → verworfen).
    nonisolated static func validPlace(_ stored: Any?) -> Weather.Place? {
        guard let d = stored as? [String: Any], let name = d["name"] as? String,
              let lat = Weather.number(d["lat"], -90...90), let lon = Weather.number(d["lon"], -180...180) else { return nil }
        let clean = NotifyWire.clean(name, max: Weather.maxPlaceName)
        guard !clean.isEmpty else { return nil }
        return Weather.Place(name: clean, region: NotifyWire.clean(d["region"] as? String ?? "", max: Weather.maxPlaceName),
                             country: NotifyWire.clean(d["country"] as? String ?? "", max: 3),
                             latitude: Weather.rounded(lat), longitude: Weather.rounded(lon))
    }

    func isNotifyApp(_ bundleID: String) -> Bool {
        notifyApps?.contains(bundleID) ?? false
    }

    func setNotifyApp(_ bundleID: String, _ on: Bool) {
        var list = (notifyApps ?? []).filter { $0 != bundleID }
        if on { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != notifyApps { notifyApps = valid }
    }

    /// Beim ersten Einschalten: vorgeschlagene Apps übernehmen (nur einmal; danach entscheidet der Nutzer).
    func seedNotifyApps(_ ids: [String]) {
        guard notifyApps == nil else { return }
        notifyApps = Self.validExcluded(ids)
    }

    func isMediaExcluded(_ bundleID: String) -> Bool {
        mediaExcluded.contains(bundleID)
    }

    /// Schalter je App. Ungültige Kennungen werden nie gespeichert.
    func setMediaExcluded(_ bundleID: String, _ excluded: Bool) {
        var list = mediaExcluded.filter { $0 != bundleID }
        if excluded { list.append(bundleID) }
        let valid = Self.validExcluded(list)
        if valid != mediaExcluded { mediaExcluded = valid }
    }

    /// G25: nur `[A-Za-z0-9.-]`, je 1…255 Zeichen, ohne Doppelte, höchstens 64. Alles andere (per `defaults write`
    /// gesetzt, anderer Typ) fällt weg.
    nonisolated static func validExcluded(_ stored: Any?) -> [String] {
        guard let raw = stored as? [Any] else { return [] }
        var out: [String] = []
        for case let id as String in raw where isValidBundleID(id) && !out.contains(id) {
            out.append(id)
            if out.count == maxExcluded { break }
        }
        return out
    }

    nonisolated static func isValidBundleID(_ id: String) -> Bool {
        (1...maxBundleIDLength).contains(id.utf8.count) && id.unicodeScalars.allSatisfy { s in
            ("a"..."z").contains(s) || ("A"..."Z").contains(s) || ("0"..."9").contains(s) || s == "." || s == "-"
        }
    }

    /// Nur Werte aus der Auswahl; alles andere (anderer Typ, per `defaults write` gesetzt) → ab Werk.
    nonisolated static func validExpandDelay(_ stored: Any?) -> TimeInterval {
        guard let n = stored as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return defaultExpandDelay }
        let v = n.doubleValue
        return expandDelayChoices.first { abs($0 - v) < 0.001 } ?? defaultExpandDelay
    }

    /// Neonschrift (ab Werk an) und Start/Stopp-Knopf (ab Werk aus).
    nonisolated static func turntableFlags(_ defaults: UserDefaults) -> (neon: Bool, tonearm: Bool) {
        (defaults.object(forKey: Key.desktopMusicNeon) as? Bool ?? true, defaults.object(forKey: Key.desktopMusicTonearm) as? Bool ?? false)
    }

    /// 0.20.0: beide ab Werk aus (G46).
    nonisolated static func lockFlags(_ defaults: UserDefaults) -> (show: Bool, hideTitle: Bool) {
        (defaults.object(forKey: Key.lockScreenMusic) as? Bool ?? false, defaults.object(forKey: Key.lockScreenHideTitle) as? Bool ?? false)
    }

    nonisolated static func validScreen(_ defaults: UserDefaults) -> String {
        String((defaults.string(forKey: Key.desktopMusicScreen) ?? "").prefix(64))
    }

    nonisolated static func validStyle(_ defaults: UserDefaults) -> DesktopStyle {
        defaults.string(forKey: Key.desktopMusicStyle).flatMap(DesktopStyle.init(rawValue:)) ?? .card
    }

    /// Nur Werte aus der Auswahl; alles andere → ab Werk (30 Min.).
    nonisolated static func validScreenshotMinutes(_ stored: Any?) -> Int {
        guard let n = stored as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return defaultScreenshotMinutes }
        return screenshotMinuteChoices.first { $0 == n.intValue && Double($0) == n.doubleValue } ?? defaultScreenshotMinutes
    }
}

/// Bildschirmauswahl der Insel (0.46), eigener Block, damit die Klasse unter der Längengrenze bleibt.
extension Preferences {
    func isIslandScreenShown(_ uuid: String) -> Bool {
        !islandHiddenScreens.contains(uuid)
    }

    func setIslandScreen(_ uuid: String, shown: Bool) {
        var list = islandHiddenScreens.filter { $0 != uuid }
        if !shown { list.append(uuid) }
        let valid = Self.validScreens(list)
        if valid != islandHiddenScreens { islandHiddenScreens = valid }
    }

    /// Nur Zeichenketten aus `[0-9A-Fa-f-]` (Bildschirm-UUID), je höchstens 64 Zeichen, ohne Doppelte, höchstens 16.
    nonisolated static func validScreens(_ stored: Any?) -> [String] {
        guard let raw = stored as? [Any] else { return [] }
        var out: [String] = []
        for case let id as String in raw
        where !id.isEmpty && id.count <= 64 && id.allSatisfy({ $0.isHexDigit || $0 == "-" }) && !out.contains(id) {
            out.append(id)
            if out.count == 16 { break }
        }
        return out
    }
}
