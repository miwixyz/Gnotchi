import Foundation

/// Eine Aktivität der kleinen Insel (0.4.0, specs/2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md). Aufnahme und
/// Hinweise gehören nicht dazu: Sie rotieren nicht mit, sie verdrängen.
enum LiveActivity: Hashable, Sendable {
    case event, timer, media, headphones
    case update(FamilyApp)
}

/// Bluetooth-Ausgang als dauerhafte Aktivität: nur Symbol und bereinigter Gerätename (kein Akku, G19).
struct Headphones: Equatable, Sendable {
    let name: String
    let symbol: String
}

extension ActivityModel {

    // MARK: Reine Teile (getestet)

    /// Feste Reihenfolge: Termin (0.5.0, das Dringendste), Timer, Medien, Kopfhörer, Updates der Familie.
    nonisolated static func rotationItems(event: Bool = false, timer: Bool = false, media: Bool, headphones: Bool,
                                          updates: [FamilyApp]) -> [LiveActivity] {
        (event ? [.event] : []) + (timer ? [.timer] : []) + (media ? [.media] : []) + (headphones ? [.headphones] : [])
            + updates.map(LiveActivity.update)
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
        Self.rotationItems(event: upcomingEvent != nil, timer: timer != nil, media: media.isVisible,
                           headphones: headphones != nil, updates: allUpdates.map(\.app))
    }

    /// Zeilen über der Musik bzw. in der großen Insel: je Update eine, dazu der Termin.
    var activityLines: Int {
        allUpdates.count + (upcomingEvent == nil ? 0 : 1)
    }

    // MARK: Große Insel – „Eine Sache groß“ (0.5.0, Michael 21.10.)

    /// Was die große Insel groß zeigt: dieselbe Aktivität wie die kleine. Ohne Aktivität Mikrofon/Kamera bzw.
    /// die (pausierte) Musik.
    enum BigContent: Equatable {
        case media, event, timer, timerPicker, alarm, headphones, update(FamilyApp), privacy, mirror, weather, none
    }

    nonisolated static func bigContent(current: LiveActivity?, privacy: Bool, hasMediaInfo: Bool,
                                       mirror: Bool = false, timerPicker: Bool = false, alarm: Bool = false,
                                       weather: Bool = false) -> BigContent {
        if alarm { return .alarm }
        if mirror { return .mirror }
        if weather { return .weather }
        if timerPicker { return .timerPicker }
        return switch current {
        case .event?: .event
        case .timer?: .timer
        case .media?: .media
        case .headphones?: .headphones
        case .update(let app)?: .update(app)
        case nil: privacy ? .privacy : (hasMediaInfo ? .media : .none)
        }
    }

    /// Symbolleiste über der großen Sache: sobald es mehr als eine Sache gibt – mehrere Aktivitäten, oder
    /// Mikrofon/Kamera bzw. Qotti-Kontingent neben der großen Sache, oder feste Knöpfe (Timer, Spiegel).
    nonisolated static func showsChipRow(items: Int, big: BigContent, privacy: Bool, quota: Bool,
                                         fixedButtons: Bool = false) -> Bool {
        fixedButtons || items > 1 || (privacy && big != .privacy) || quota
    }

    /// Symbole der Leiste: wie die Rotation, aber Musik auch pausiert (dort will man sie weiterspielen; die
    /// kleine Insel blendet pausierte Musik nach 5 s aus – gemessen 21.10.: Musik-Symbol fehlte).
    var chipItems: [LiveActivity] {
        Self.rotationItems(event: upcomingEvent != nil, timer: timer != nil, media: media.info != nil,
                           headphones: headphones != nil, updates: allUpdates.map(\.app))
    }

    /// Was die große Insel zeigt: die gewählte bzw. gerade rotierende Sache aus der Leiste.
    var bigActivity: LiveActivity? {
        Self.resolve(cursor: rotationCursor, items: chipItems, enabled: true)
    }

    var bigContent: BigContent {
        // „Wiedergabe immer groß“: Player als Grundlage, solange Musik da ist (Alarm, Spiegel, Timer-Auswahl gehen vor).
        let current: LiveActivity? = playerFirst && media.info != nil ? .media : bigActivity
        return Self.bigContent(current: current, privacy: privacy.isActive, hasMediaInfo: media.info != nil,
                               mirror: mirrorActive, timerPicker: timerPickerActive, alarm: timerAlarm,
                               weather: weatherActive && weather != nil)
    }

    /// Glas-Schicht über dem Player (nur bei „Wiedergabe immer groß“): die gewählte, noch laufende Aktivität.
    var playerOverlay: LiveActivity? {
        guard bigContent == .media, let o = overlayActivity, o != .media, chipItems.contains(o) else { return nil }
        return o
    }

    /// Hervorgehobenes Symbol der Leiste.
    var highlightedChip: LiveActivity? {
        if mirrorActive || timerPickerActive || weatherActive { return nil }
        if playerFirst && bigContent == .media { return playerOverlay ?? .media }
        return bigActivity
    }

    func togglePin() {
        pinned.toggle()
    }

    var showsChipRow: Bool {
        Self.showsChipRow(items: chipItems.count, big: bigContent, privacy: privacy.isActive, quota: quotaLine != nil,
                          fixedButtons: true)   // Timer-Symbol steht immer in der Leiste (0.5.0)
    }

    /// Klick auf ein Symbol der Leiste: diese Aktivität groß zeigen (der Takt steht, solange die Maus darauf ist).
    func select(_ item: LiveActivity) {
        if chipItems.contains(item) { rotationCursor = item }
        mirrorActive = false
        timerPickerActive = false
        weatherActive = false
        // „Wiedergabe immer groß“: Klick auf eine andere Aktivität legt sie als Glas über den Player, erneut weg.
        if playerFirst { overlayActivity = item == .media || overlayActivity == item ? nil : item }
    }

    // MARK: Spiegel (0.5.0, G27) – Kamera nur, solange der Spiegel groß sichtbar ist

    func selectMirror() {
        if mirrorEnabled { mirrorActive = true }
        timerPickerActive = false
        weatherActive = false
    }

    /// Wetter groß (0.7.0): nur mit einer Vorhersage.
    func selectWeather() {
        guard weather != nil else { return }
        weatherActive = true
        mirrorActive = false
        timerPickerActive = false
    }

    /// Insel klappt zu / Spiegel ausgeschaltet: Kamera aus (MirrorView verschwindet).
    func endMirror() {
        if mirrorActive { mirrorActive = false }
        if timerPickerActive { timerPickerActive = false }
        if weatherActive { weatherActive = false }
        if overlayActivity != nil { overlayActivity = nil }
    }

    func setMirrorEnabled(_ on: Bool) {
        if mirrorEnabled != on { mirrorEnabled = on }
        if !on { endMirror() }
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
