import AppKit
import SwiftUI
import XCTest
@testable import Gnotchi

/// Sichtprüfung ohne App-Start: rendert die Insel (klein/groß, Notch/Pille). Prüft nur, dass gerendert
/// wird; das Aussehen beurteilt ein Mensch (Plan Aufgabe 10/14). PNGs nur auf Wunsch, z. B.:
/// `TEST_RUNNER_GNOTCHI_RENDER_DIR=/tmp/gnotchi-render make test` (xcodebuild reicht Variablen mit
/// Präfix `TEST_RUNNER_` ohne Präfix an den Testlauf durch).
@MainActor
final class IslandViewRenderTests: XCTestCase {

    // Gemessen am MacBook Air M5 (macOS 27.0.1, 18.10.), wie IslandGeometryTests.
    private let notchScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 645.5, auxRightWidth: 645.5)
    private let pillScreen = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)

    // MARK: 0.6.0 Mitteilungen und Anrufe (SYNTHETISCH)

    private static let sampleNote = NotifyWire.Note(
        id: "a1", kind: .note, app: "Erinnerungen", bundle: nil, title: "Blumen gießen", subtitle: "Balkon",
        body: "Erfundener Beispieltext, der so lang ist, dass er auf zwei Zeilen umbricht und am Ende gekürzt wird, damit man das sieht.",
        actions: ["Erledigt", "In einer Stunde erinnern", "Schließen"])
    private static let sampleCall = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                                    title: "Erika Muster", subtitle: "", body: "", actions: ["Annehmen", "Ablehnen"])

    func testRenderNotchMessage() throws {
        try render(notchScreen, .message, name: "notch-message", notes: [Self.sampleNote, Self.sampleNote.with(id: "a2")])
    }
    func testRenderPillMessageShort() throws {
        let short = NotifyWire.Note(id: "b1", kind: .note, app: "Nachrichten", bundle: nil, title: "Max", subtitle: "",
                                    body: "Kommst du heute?", actions: ["Schließen"])
        try render(pillScreen, .message, name: "pill-message-short", notes: [short])
    }
    func testRenderNotchCall() throws { try render(notchScreen, .call, name: "notch-call", notes: [Self.sampleCall]) }
    func testRenderPillCallNotArmed() throws {
        try render(pillScreen, .call, name: "pill-call-unarmed", notes: [Self.sampleCall], callArmed: false)
    }

    func testRenderNotchShelfDrop() throws {
        try render(notchScreen, .shelfDrop, name: "notch-shelf-drop", withMedia: false, shelfFiles: ["a.pdf"], drag: true)
    }
    func testRenderNotchShelfBig() throws {
        try render(notchScreen, .expanded, name: "notch-shelf-big", withMedia: false,
                   shelfFiles: ["Angebot Kino.pdf", "Plakat.png", "Notizen.txt", "Tabelle mit sehr langem Namen.xlsx"])
    }
    func testRenderNotchIdle() throws {
        try render(notchScreen, .compact, name: "notch-idle", withMedia: false, weather: Self.sampleWeather(code: 0, day: true),
                   shelfFiles: ["a.pdf", "b.pdf"], showWeatherBig: false)
    }
    func testRenderPillIdle() throws {
        try render(pillScreen, .compact, name: "pill-idle", withMedia: false, weather: Self.sampleWeather(code: 0, day: true),
                   shelfFiles: ["a.pdf", "b.pdf"], showWeatherBig: false)
    }

    func testRenderNotchWeather() throws {
        try render(notchScreen, .expanded, name: "notch-weather", withMedia: false, weather: Self.sampleWeather(code: 2, day: true))
    }
    func testRenderPillWeatherNightRain() throws {
        try render(pillScreen, .expanded, name: "pill-weather-night", withMedia: false, weather: Self.sampleWeather(code: 63, day: false))
    }

    /// Mitteilungen/Anruf (0.6.0) und Wetter (0.7.0) setzen – ausgelagert, damit `render` kurz bleibt.
    private static func applyExtras(_ activity: ActivityModel, notes: [NotifyWire.Note], callArmed: Bool,
                                    weather: Weather.Forecast?, showWeatherBig: Bool) {
        notes.forEach { activity.receiveNote($0) }
        activity.callArmed = callArmed
        if let weather { activity.setWeather(weather); if showWeatherBig { activity.selectWeather() } }
    }

    /// Ablage (0.8.0): erfundene Dateien in einem Temp-Ordner, eigener Speicher, Einstellungen getrennt von den echten.
    private static func applyShelf(_ activity: ActivityModel, files: [String], drag: Bool) -> ShelfLink? {
        activity.fileDragActive = drag
        guard !files.isEmpty else { return nil }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gnotchi-render-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = files.map { name -> URL in
            let u = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8))
            return u
        }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "gnotchi-render-\(UUID().uuidString)") ?? .standard)
        let link = ShelfLink(activity: activity, prefs: prefs, store: ShelfStore(directory: dir.appendingPathComponent("store")))
        activity.shelf = link
        link.drop(urls)
        activity.clearNotice()
        return link
    }

    /// Erfundene Vorhersage (Aufbau wie Open-Meteo, 22.10.).
    private static func sampleWeather(code: Int, day: Bool) -> Weather.Forecast {
        let tz = TimeZone(secondsFromGMT: 7200) ?? .current
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var f = Weather.Forecast(
            fetched: base, timeZone: tz, temperature: 10.4, apparent: 6.3, code: code, isDay: day, humidity: 63, wind: 14.8,
            pressure: 1014.9, uvMax: 2.9, sunrise: base.addingTimeInterval(-3600), sunset: base.addingTimeInterval(8 * 3600),
            hours: (0..<8).map { Weather.Hour(time: base.addingTimeInterval(Double($0) * 3600), temperature: 10 + Double($0 % 3),
                                               code: [code, 3, 61, 2][$0 % 4]) },
            days: (0..<7).map { Weather.Day(date: base.addingTimeInterval(Double($0) * 86_400), code: [code, 61, 3, 0, 71, 95, 2][$0],
                                             max: 12 - Double($0), min: 4 - Double($0)) })
        f.placeName = "Beispielstadt"
        return f
    }

    func testRenderNotchCompact() throws { try render(notchScreen, .compact, name: "notch-compact") }
    func testRenderNotchExpanded() throws { try render(notchScreen, .expanded, name: "notch-expanded") }
    func testRenderPillCompact() throws { try render(pillScreen, .compact, name: "pill-compact") }
    func testRenderPillExpanded() throws { try render(pillScreen, .expanded, name: "pill-expanded") }
    /// Mit App-Symbol. Gemessen 18.10.: Ein NSWorkspace-Symbol dunkelt im ImageRenderer das GANZE Bild
    /// ab (Grau 0,55 → 0,45) – Renderer-Eigenheit; deshalb die anderen Bilder ohne Symbol (farbecht).
    func testRenderNotchExpandedWithAppIcon() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-appicon", appBundleID: "com.apple.Music")
    }
    /// Spotify Connect: „Auf anderem Gerät“ oben rechts, klein ein Lautsprecher statt Pegel.
    func testRenderNotchExpandedRemote() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-remote", appBundleID: "com.spotify.client", route: .remote)
    }
    func testRenderNotchCompactRemote() throws {
        try render(notchScreen, .compact, name: "notch-compact-remote", route: .remote)
    }
    /// Langer AirPlay-Name: wird gekürzt, drückt den Titel nicht weg.
    func testRenderPillExpandedAirPlay() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-airplay",
                   route: .device(name: "Wohnzimmer HomePod mini Stereo-Paar", kind: .airPlay))
    }
    /// App-Abzeichen unten rechts am kleinen Cover.
    func testRenderNotchCompactWithAppBadge() throws {
        try render(notchScreen, .compact, name: "notch-compact-appbadge", appBundleID: "com.apple.Music")
    }

    /// 0.2.0 Kopfhörer-Hinweis: Streifen unter der Notch bzw. Pille, Name gekürzt.
    func testRenderNotchNotice() throws {
        try render(notchScreen, .notice, name: "notch-notice",
                   notice: ActivityModel.Notice(symbol: "headphones", title: "Beispiel-Kopfhörer Pro", subtitle: "Verbunden"))
    }
    func testRenderPillNoticeLongName() throws {
        try render(pillScreen, .notice, name: "pill-notice",
                   notice: ActivityModel.Notice(symbol: "speaker.wave.2", title: "Ein sehr langer Lautsprechername im Wohnzimmer",
                                                subtitle: "Kopfhörer getrennt"))
    }

    /// 0.2.0 Mikrofon/Kamera: Punkte klein (mit/ohne Musik), Zeile groß.
    private let callPrivacy = ActivityModel.Privacy(micApps: ["Konferenz-App", "Webseite"], camera: true)
    func testRenderNotchCompactPrivacyOnly() throws {
        try render(notchScreen, .compact, name: "notch-compact-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderPillCompactPrivacyOnly() throws {
        try render(pillScreen, .compact, name: "pill-compact-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderNotchCompactPrivacyWithMusic() throws {
        try render(notchScreen, .compact, name: "notch-compact-privacy-music", privacy: callPrivacy)
    }
    func testRenderNotchExpandedPrivacyOnly() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-privacy", privacy: callPrivacy, withMedia: false)
    }
    func testRenderPillExpandedPrivacyWithMusic() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-privacy-music", privacy: callPrivacy)
    }

    /// 0.2.0 Tippi-Aufnahme: klein, verdrängt die Musik.
    func testRenderNotchRecording() throws {
        try render(notchScreen, .compact, name: "notch-recording", recording: .recording(since: Date().addingTimeInterval(-7)))
    }
    func testRenderPillRecording() throws {
        try render(pillScreen, .compact, name: "pill-recording", recording: .recording(since: Date().addingTimeInterval(-7)))
    }
    func testRenderPillTranscribing() throws {
        try render(pillScreen, .compact, name: "pill-transcribing", recording: .transcribing)
    }

    // 0.3.0 Live-Text – SYNTHETISCH, erfundene Sätze (G16)
    private static let shortLive = "Hallo zusammen, das ist ein kurzer Test"
    private static let longLive = "Das hier ist ein erfundener, ziemlich langer Diktat-Satz, der über mehr als zwei "
        + "Zeilen geht, damit man sieht, dass vorne abgeschnitten wird und das Ende sichtbar bleibt"
    func testRenderNotchLive() throws {
        try render(notchScreen, .live, name: "notch-live", recording: .recording(since: Date()), liveText: Self.longLive)
    }
    func testRenderPillLive() throws {
        try render(pillScreen, .live, name: "pill-live", recording: .recording(since: Date()), liveText: Self.longLive)
    }
    func testRenderPillLiveShort() throws {
        try render(pillScreen, .live, name: "pill-live-short", recording: .recording(since: Date()), liveText: Self.shortLive)
    }
    func testRenderPillLiveTranscribing() throws {
        try render(pillScreen, .live, name: "pill-live-transcribing", recording: .transcribing, liveText: Self.shortLive)
    }

    // 0.3.0 Qotti-Kontingent
    private static let quota = QottiLink.Snapshot(claude: .init(percent: 42, resetAt: nil, state: .ok),
                                                  codex: .init(percent: 17, resetAt: nil, state: .ok))
    func testRenderNotchExpandedQuota() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-quota", quota: Self.quota)
    }
    func testRenderPillExpandedQuotaAndPrivacy() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-quota-privacy", privacy: callPrivacy, quota: Self.quota)
    }
    func testRenderNotchNoticeQuota() throws {
        let p = QottiLink.Provider(percent: 82, resetAt: Date().addingTimeInterval(65 * 60 + 30), state: .ok)
        try render(notchScreen, .notice, name: "notch-notice-quota", notice: QottiLink.notice(name: "Claude", p, .percent80))
    }

    // 0.4.0 Live-Aktivitäten – erfundene Gerätenamen und Versionen (G16)
    private static let buds = Headphones(name: "Beispiel-Kopfhörer Pro", symbol: "headphones")
    private static let kalli = FamilyUpdates.Entry(app: .kalli, version: "0.11.0", seen: Date())
    private static let seam = FamilyUpdates.Entry(app: .seam, version: "1.4.2", seen: Date())
    func testRenderNotchCompactHeadphones() throws {
        try render(notchScreen, .compact, name: "notch-compact-headphones", withMedia: false, headphones: Self.buds)
    }
    func testRenderPillCompactHeadphones() throws {
        try render(pillScreen, .compact, name: "pill-compact-headphones", withMedia: false, headphones: Self.buds)
    }
    func testRenderNotchCompactUpdate() throws {
        try render(notchScreen, .compact, name: "notch-compact-update", updates: [Self.kalli], cursor: .update(.kalli))
    }
    func testRenderPillCompactUpdate() throws {
        try render(pillScreen, .compact, name: "pill-compact-update", updates: [Self.kalli], cursor: .update(.kalli))
    }
    func testRenderNotchWide() throws {
        try render(notchScreen, .wide, name: "notch-wide")
    }
    func testRenderPillWide() throws {
        try render(pillScreen, .wide, name: "pill-wide")
    }
    func testRenderNotchExpandedUpdates() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-updates", updates: [Self.kalli, Self.seam])
    }
    func testRenderPillExpandedDetailsNoMusic() throws {
        try render(pillScreen, .expanded, name: "pill-expanded-details", privacy: callPrivacy, withMedia: false,
                   headphones: Self.buds, updates: [Self.kalli])
    }

    // 0.5.0 Termine + „Eine Sache groß“ – erfundener Termin (G16)
    private static let dentist = KalliEvents.Event(title: "Zahnarzt Dr. Beispiel", start: Date().addingTimeInterval(10 * 60),
                                                   color: KalliEvents.RGB(r: 0.2, g: 0.5, b: 1))
    func testRenderNotchCompactEvent() throws {
        try render(notchScreen, .compact, name: "notch-compact-event", cursor: .event, event: Self.dentist)
    }
    func testRenderPillCompactEvent() throws {
        try render(pillScreen, .compact, name: "pill-compact-event", cursor: .event, event: Self.dentist)
    }
    func testRenderNotchBigEventWithMusicAndMic() throws {
        try render(notchScreen, .expanded, name: "notch-big-event-music-mic", privacy: callPrivacy, cursor: .event,
                   event: Self.dentist)
    }
    func testRenderPillBigMusicWithEventAndMic() throws {
        try render(pillScreen, .expanded, name: "pill-big-music-event-mic", privacy: callPrivacy, cursor: .media,
                   event: Self.dentist)
    }
    func testRenderNotchBigUpdate() throws {
        try render(notchScreen, .expanded, name: "notch-big-update", updates: [Self.kalli], cursor: .update(.kalli),
                   event: Self.dentist)
    }
    func testRenderPillBigHeadphonesNoMusic() throws {
        try render(pillScreen, .expanded, name: "pill-big-headphones", withMedia: false, headphones: Self.buds)
    }

    // 0.5.0 Timer
    func testRenderNotchCompactTimer() throws {
        try render(notchScreen, .compact, name: "notch-compact-timer", cursor: .timer, timerMinutes: 25)
    }
    func testRenderPillBigTimer() throws {
        try render(pillScreen, .expanded, name: "pill-big-timer", cursor: .timer, timerMinutes: 25)
    }
    func testRenderNotchBigTimerPicker() throws {
        try render(notchScreen, .expanded, name: "notch-big-timer-picker", timerPicker: true)
    }

    func testRenderPillCompactAlarm() throws {
        try render(pillScreen, .compact, name: "pill-compact-alarm", withMedia: false, alarm: true)
    }
    func testRenderNotchBigAlarm() throws {
        try render(notchScreen, .expanded, name: "notch-big-alarm", alarm: true)
    }

    func testRenderPillPlayerFirstWithEventOverlay() throws {
        try render(pillScreen, .expanded, name: "pill-playerfirst-event", event: Self.dentist, playerFirstOverlay: .event)
    }

    func testRenderNotchCompactControls() throws {
        try render(notchScreen, .compact, name: "notch-compact-controls", privacy: callPrivacy, compactControls: true)
    }
    func testRenderPillCompactControls() throws {
        try render(pillScreen, .compact, name: "pill-compact-controls", compactControls: true)
    }

    func testRenderNotchBand() throws {
        try render(notchScreen, .band, name: "notch-band", event: Self.dentist)
    }
    func testRenderPillBand() throws {
        try render(pillScreen, .band, name: "pill-band", event: Self.dentist)
    }

    private func render(_ screen: IslandGeometry.ScreenMetrics, _ mode: IslandState.Mode, name: String,
                        appBundleID: String? = nil, route: PlaybackRoute = .local,
                        notice: ActivityModel.Notice? = nil, privacy: ActivityModel.Privacy = .none,
                        withMedia: Bool = true, recording: ActivityModel.Recording? = nil,
                        liveText: String? = nil, quota: QottiLink.Snapshot? = nil,
                        headphones: Headphones? = nil, updates: [FamilyUpdates.Entry] = [],
                        cursor: LiveActivity? = nil, event: KalliEvents.Event? = nil,
                        timerMinutes: Int? = nil, timerPicker: Bool = false, alarm: Bool = false,
                        playerFirstOverlay: LiveActivity? = nil, compactControls: Bool = false,
                        notes: [NotifyWire.Note] = [], callArmed: Bool = true, weather: Weather.Forecast? = nil,
                        shelfFiles: [String] = [], drag: Bool = false, showWeatherBig: Bool = true,
                        unread: [NotifyWire.Badge] = []) throws {
        let layout = IslandGeometry.layout(for: screen)
        let state = IslandState(layout: layout)
        state.mode = mode
        let model = NowPlayingModel()
        // Klein mit Pause: der Pegel steht, das Bild ist bei jedem Lauf gleich. Groß zeigt keinen Pegel;
        // dort hält rate 0 die Zeit fest.
        model.setPreviewState(info: withMedia ? Self.info(appBundleID: appBundleID, playing: mode == .expanded) : nil,
                              artwork: Self.artwork(), route: route)
        let activity = ActivityModel(media: model)
        activity.receiveBadges(unread)
        if let notice { activity.post(notice) }
        activity.setPrivacy(privacy)
        activity.setQuota(quota)
        activity.setHeadphones(headphones)
        activity.setFamilyUpdates(updates)
        activity.rotationCursor = cursor
        if let recording {
            activity.setRecording(recording)
            activity.setRecordingLevel(0.7)
            activity.setLiveText(liveText)
        }

        activity.setUpcomingEvent(event)
        if let timerMinutes { activity.startTimer(minutes: timerMinutes); activity.rotationCursor = cursor }
        if timerPicker { activity.showTimerPicker() }
        if alarm { activity.timerAlarm = true }
        activity.compactControls = compactControls
        if let playerFirstOverlay { activity.playerFirst = true; activity.select(playerFirstOverlay) }
        Self.applyExtras(activity, notes: notes, callArmed: callArmed, weather: weather, showWeatherBig: showWeatherBig)
        let shelfLink = Self.applyShelf(activity, files: shelfFiles, drag: drag)
        defer { _ = shelfLink }
        let (panel, canvas) = Self.frames(mode, layout, activity, wide: weather != nil || !shelfFiles.isEmpty)
        let view = ZStack(alignment: .top) {
            // Mittelgrau statt Hintergrundbild: Form und Kanten sind so gut zu sehen.
            Color(white: 0.55)
            IslandView(state: state, onHover: { _ in })
                .environment(model)
                .environment(activity)
                .frame(width: panel.width, height: panel.height)
            // Hardware-Notch als rote Haarlinie, um die Ausrichtung zu prüfen.
            if let n = layout.notch {
                Rectangle().stroke(Color.red, lineWidth: 0.5).frame(width: n.width, height: n.height)
            }
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let cg = try XCTUnwrap(renderer.cgImage, "ImageRenderer lieferte kein Bild")
        XCTAssertEqual(cg.width, Int(canvas.width * 2))
        guard let dir = ProcessInfo.processInfo.environment["GNOTCHI_RENDER_DIR"], !dir.isEmpty else { return }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("gnotchi-island-\(name).png"), options: .atomic)
    }

    /// Panel so groß wie der aktuelle Zustand (wie im IslandController) und die Leinwand drumherum.
    private static func frames(_ mode: IslandState.Mode, _ layout: IslandGeometry.Layout, _ activity: ActivityModel,
                               wide: Bool) -> (CGRect, CGSize) {
        let panel: CGRect
        switch mode {
        case .message: panel = IslandController.messageFrame(layout: layout, note: activity.currentNote)
        case .expanded:
            panel = IslandController.bigFrame(layout: layout, small: activity.bigContent == .privacy, chipRow: activity.showsChipRow,
                                              mirror: activity.mirrorActive, weather: activity.bigContent == .weather,
                                              shelf: activity.bigContent == .shelf,
                                              strip: activity.showsShelfStrip) ?? layout.compact
        default: panel = IslandController.panelFrame(mode: mode, layout: layout) ?? layout.compact
        }
        let canvas = CGSize(width: mode == .band ? 1100 : (wide ? 680 : 520), height: wide ? 420 : 210)
        return (panel, canvas)
    }

    private static func info(appBundleID: String?, playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(
            title: "Ein ziemlich langer Songtitel, der sicher abgeschnitten wird",
            artist: "Interpretin mit Namen", album: nil, appBundleID: appBundleID,
            isPlaying: playing, duration: 225, elapsedAtStamp: 83,
            stamp: Date(timeIntervalSince1970: 1_800_000_000), rate: 0,
            contentID: nil, artworkBase64: nil)
    }

    /// Farbverlauf als Platzhalter-Cover (kein echtes Bild im Repo nötig).
    private static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(starting: .systemOrange, ending: .systemPink)?.draw(in: rect, angle: 45)
            return true
        }
    }
}

private extension NotifyWire.Note {
    func with(id: String) -> NotifyWire.Note {
        NotifyWire.Note(id: id, kind: kind, app: app, bundle: bundle, title: title, subtitle: subtitle, body: body,
                        actions: actions)
    }
}

// 0.9.0 – als Erweiterung, damit der Klassenrumpf unter 350 Zeilen bleibt.
extension IslandViewRenderTests {
    // 0.9.0: Mailbox-Zustand nach „Mitlesen“, Ungelesen-Zahlen klein, in der Leiste und im Band (erfundene Zahlen).
    private static let sampleUnread = [NotifyWire.Badge(bundle: "com.apple.mail", count: 5),
                                       NotifyWire.Badge(bundle: "com.apple.reminders", count: 12)]
    func testRenderNotchCallScreening() throws {
        let screening = NotifyWire.Note(id: NotifyWire.callIdentifier, kind: .call, app: "Telefon", bundle: nil,
                                        title: "Erika Muster", subtitle: "", body: "",
                                        actions: ["Annehmen", "Live-Voicemail stoppen"])
        try render(notchScreen, .call, name: "notch-call-screening", notes: [screening])
    }
    func testRenderNotchIdleUnread() throws {
        try render(notchScreen, .compact, name: "notch-idle-unread", withMedia: false,
                   weather: Self.sampleWeather(code: 0, day: true), showWeatherBig: false, unread: Self.sampleUnread)
    }
    func testRenderPillIdleUnreadOnly() throws {
        try render(pillScreen, .compact, name: "pill-idle-unread", withMedia: false, unread: Self.sampleUnread)
    }
    func testRenderNotchExpandedUnread() throws {
        try render(notchScreen, .expanded, name: "notch-expanded-unread", unread: Self.sampleUnread)
    }
    func testRenderNotchBandUnread() throws {
        try render(notchScreen, .band, name: "notch-band-unread", unread: Self.sampleUnread)
    }
    func testRenderNotchCompactUnreadWithMusic() throws {
        try render(notchScreen, .compact, name: "notch-compact-unread", appBundleID: "com.apple.Music", unread: Self.sampleUnread)
    }
    func testRenderPillCompactUnreadWithMusic() throws {
        try render(pillScreen, .compact, name: "pill-compact-unread", appBundleID: "com.apple.Music", compactControls: true,
                   unread: Self.sampleUnread)
    }
    func testRenderPillCompactControlsNoUnread() throws {
        try render(pillScreen, .compact, name: "pill-compact-controls", appBundleID: "com.apple.Music", compactControls: true)
    }
    func testRenderPillBandUnread() throws {
        try render(pillScreen, .band, name: "pill-band-unread", unread: Self.sampleUnread)
    }
    func testRenderPillPrivacyUnread() throws {
        try render(pillScreen, .compact, name: "pill-privacy-unread", privacy: .init(micApps: ["Beispiel"], camera: false),
                   withMedia: false, unread: Self.sampleUnread)
    }
    func testRenderNotchPrivacyUnread() throws {
        try render(notchScreen, .compact, name: "notch-privacy-unread", privacy: .init(micApps: ["Beispiel"], camera: false),
                   withMedia: false, unread: Self.sampleUnread)
    }
    func testRenderNotchBandShelfUnread() throws {
        try render(notchScreen, .band, name: "notch-band-shelf-unread", shelfFiles: ["a.pdf", "b.pdf"], unread: Self.sampleUnread)
    }
}
