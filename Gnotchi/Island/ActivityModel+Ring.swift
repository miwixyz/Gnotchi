import Foundation

/// Tasten-Ring (0.28.0): Verfügbarkeit, Zustand und Aktionen der Ring-Tasten. Reine Rechnungen in `RingButtons.swift`.
extension ActivityModel {

    /// Funktionen, die gerade etwas anbieten – dieselben Bedingungen wie früher in der Leiste: Wetter nur mit
    /// Vorhersage, Ablage nur mit Inhalt, Zwischenablage nur eingeschaltet, Spiegel nur mit Schalter.
    var ringAvailable: Set<RingButton> {
        var s: Set<RingButton> = [.timer, .screenshot, .speedtest, .mixer]
        if awake != nil { s.insert(.awake) }   // wie die alte Leiste: nur, wenn „Wach bleiben“ da ist
        // Mikrofon: nur, wenn sich das Gerät stummschalten lässt, und – außer auf Wunsch immer – nur im Meeting
        // (eine App nutzt das Mikrofon) oder solange es stumm ist (sonst käme man nicht mehr heran).
        if mic.isSupported, ringMicAlways || privacy.mic || mic.isMuted { s.insert(.mic) }
        if mirrorEnabled { s.insert(.mirror) }
        if weather != nil { s.insert(.weather) }
        if !shelfItems.isEmpty { s.insert(.shelf) }
        if clipboard != nil { s.insert(.clipboard) }
        if openQuickEntry != nil { s.insert(.quickEntry) }
        return s
    }

    /// Tasten im Ring, in fester Reihenfolge. Leer, wenn der Ring aus ist.
    var ringButtons: [RingButton] {
        ringEnabled ? Ring.visible(enabled: ringOn, available: ringAvailable) : []
    }

    /// Ring ist an und hat mindestens eine Taste – dann entfallen die festen Symbole der Leiste.
    var ringShown: Bool { !ringButtons.isEmpty }

    /// Gewählt (hellere Füllung): die zugehörige große Ansicht ist gerade offen.
    func ringSelected(_ b: RingButton) -> Bool {
        switch b {
        case .timer: timerPickerActive || bigContent == .timer
        case .awake: awakePageActive
        case .mirror: mirrorActive
        case .weather: weatherActive
        case .shelf: shelfActive
        case .clipboard: clipboardActive
        case .pin: pinned
        case .speedtest: speedtestActive
        case .mixer: mixerActive
        case .mic, .screenshot, .settings, .quickEntry: false
        }
    }

    /// Läuft gerade etwas hinter der Taste (kleiner Punkt): Timer, Wach bleiben, Spiegel.
    func ringRunning(_ b: RingButton) -> Bool {
        switch b {
        case .timer: timer != nil
        case .awake: awake?.isActive == true
        case .mirror: mirrorActive
        case .mic: mic.isMuted
        case .speedtest: speed.state == .running
        case .weather, .shelf, .clipboard, .mixer, .pin, .screenshot, .settings, .quickEntry: false
        }
    }

    /// Tippen auf eine Taste. `.settings` meldet der Controller selbst (er öffnet Fenster), hier nur die Inhalte.
    func ringTap(_ b: RingButton) {
        switch b {
        case .timer:
            // Läuft ein Timer, steht er bei den Aktivitäten (Leiste): Taste zeigt ihn groß, sonst die Auswahl.
            if timer != nil { select(.timer) } else { showTimerPicker() }
        case .awake: selectAwake()
        case .mirror: selectMirror()
        case .weather: selectWeather()
        case .shelf: selectShelf()
        case .clipboard: selectClipboard()
        case .pin: togglePin()
        case .mic: mic.toggle()
        case .speedtest: selectSpeedtest()
        case .mixer: selectMixer()
        case .screenshot, .settings, .quickEntry: break   // öffnen Fenster bzw. Apps: der Controller führt sie aus
        }
    }

    /// Mixer groß in der Insel (G54): derselbe wie im Popover.
    func selectMixer() {
        mixerActive = true
        speedtestActive = false
        mirrorActive = false
        timerPickerActive = false
        awakePageActive = false
        weatherActive = false
        shelfActive = false
        clipboardActive = false
    }

    /// Geschwindigkeitstest groß zeigen und starten (G51): nur auf Klick, ein Lauf gleichzeitig.
    func selectSpeedtest() {
        speedtestActive = true
        mixerActive = false
        mirrorActive = false
        timerPickerActive = false
        awakePageActive = false
        weatherActive = false
        shelfActive = false
        clipboardActive = false
        speed.start()
    }
}
