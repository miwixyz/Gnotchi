import SwiftUI

/// Inhalte der Reiter (Michael 22.10.: „Einstellungsfenster zu lang, besser strukturieren“). Zuordnung nach Zweck:
/// Allgemein (Start, Updates, Aufklappen) · Wiedergabe (Musik, Medienfilter) · Audio (Mixer, Meeting-Leiser) · Aktivitäten
/// (was die Insel sonst zeigt) · Tasten (Ring, Timer, Spiegel, Wetter) · Mitteilungen · Ablage · Zwischenablage.
extension SettingsView {

    @ViewBuilder var generalTab: some View {
        @Bindable var prefs = prefs
        card("Start und Updates") {
            toggleRow("Bei Anmeldung starten", isOn: Binding(
                get: { login == .on || login == .needsApproval },
                set: { on in
                    loginError = LoginItem.set(on)?.localizedDescription
                    login = LoginItem.state
                }
            ))
            .disabled(login == .unavailable)
            if login == .needsApproval {
                row(nil) {
                    Label("macOS wartet auf deine Freigabe", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(FamilyTheme.warning)
                    Spacer()
                    Button("Freigeben …") { LoginItem.openSystemSettings() }
                        .buttonStyle(CardButtonStyle())
                }
            }
            if login == .unavailable {
                note("macOS meldet einen unbekannten Autostart-Status",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
            }
            if let loginError {
                note(loginError, symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
            }
            if let updater = model.updater {
                divider
                Button("Nach Updates suchen …") { updater.checkForUpdates() }
                    .buttonStyle(CardButtonStyle())
                    .disabled(!updater.canCheck)
                    .padding(.vertical, FamilyTheme.Space.s)
            }
        }
        card("Aussehen") {
            // 0.16.0 (Michael 27.10.): ohne Notch wirkte die schwarze Insel auf der hellen Menüleiste wie ein Fremdkörper.
            toggleRow("Ruhige Insel ohne Notch", isOn: $prefs.quietIsland)
                .onChange(of: prefs.quietIsland) { model.applyNotchSetting() }
            note("Auf Bildschirmen ohne Notch sieht die Insel aus wie die Menüleiste, solange sie nur Wetter, Ablage oder "
                 + "Ungelesen-Zahlen zeigt. Bei Musik, Timer, Termin, Anruf, Aufnahme oder Mitteilung wird sie wieder schwarz.",
                 symbol: "info.circle", color: FamilyTheme.textSecondary)
        }
        card("Terminal") {
            // 0.44.0 (G65): echte Shell in einem eigenen Fenster, im eigenen Hilfsprogramm „Gnotchi Terminal“.
            toggleRow("Terminal-Fenster anbieten", isOn: $prefs.terminal)
            note("Zeigt einen Knopf „Terminal“ unter „Funktionen“ und als Taste unten an der großen Insel. "
                 + "Das Fenster ist ein eigenes Programm („Gnotchi Terminal“) ohne Gnotchis Freigaben wie Kamera oder "
                 + "Apple Events. Die Shell hat deine Nutzerrechte, wie in Terminal.app; "
                 + "macOS fragt für Ordner wie Dokumente oder Schreibtisch unter „Gnotchi Terminal“ nach. Ab Werk aus.",
                 symbol: "info.circle", color: FamilyTheme.textSecondary)
        }
        card("Aufklappen") {
            row("Aufklappen als") {
                Picker("Aufklappen als", selection: $prefs.bandStyle) {
                    Text(verbatim: "Insel").tag(false)
                    Text(verbatim: "Band").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                .onChange(of: prefs.bandStyle) { model.applyNotchSetting() }
            }
            // Wirkt beim nächsten Überfahren (IslandController liest den Wert jedes Mal neu).
            row("Aufklappen nach") {
                Picker("Aufklappen nach", selection: $prefs.expandDelay) {
                    ForEach(Preferences.expandDelayChoices, id: \.self) { d in
                        Text(verbatim: Self.delayLabel(d)).tag(d)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    @ViewBuilder var playbackTab: some View {
        @Bindable var prefs = prefs
        card("Musik") {
            toggleRow("Musik in der Notch", isOn: $prefs.notchMedia)
                .onChange(of: prefs.notchMedia) { model.applyNotchSetting() }
            toggleRow("Wiedergabe-Knöpfe in der kleinen Insel", isOn: $prefs.compactControls)
                .onChange(of: prefs.compactControls) { model.applyNotchSetting() }
            toggleRow("Wiedergabe immer groß", isOn: $prefs.playerFirst)
                .onChange(of: prefs.playerFirst) { model.applyNotchSetting() }
            // Grund steht für sich (z. B. „… – nur Spotify und Musik“): Der Rückfall läuft dann
            // ja noch, ein Vorsatz „nicht verfügbar“ wäre falsch.
            if prefs.notchMedia, let reason = model.nowPlaying.unavailableReason {
                note(reason, symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
            }
            // Ersatzquelle (G56): Spotify/Musik laufen, Gnotchi darf sie aber nicht fragen → Titel fehlt, wenn macOS ihn nicht meldet.
            if prefs.notchMedia {
                ForEach([AppleScriptSource.spotify, AppleScriptSource.music], id: \.self) { id in
                    if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
                       !AutomationStatus.shared.isAllowed(id) {
                        note("\(AppleScriptSource.appName(id)) läuft, aber Gnotchi darf die App nicht steuern. Meldet macOS den Titel nicht selbst (z. B. weil ein pausierter Browser davorsteht), bleibt die Notch leer.",
                             symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                        Button("\(AppleScriptSource.appName(id)) jetzt erlauben") { AutomationStatus.shared.request(id) }
                        if let code = AutomationStatus.shared.lastRequest[id], code != 0 {
                            note(code == AppleScriptSource.deniedError
                                 ? "macOS hat die Erlaubnis verweigert und fragt nicht noch einmal. Schalte sie in Systemeinstellungen → Datenschutz & Sicherheit → Automation unter Gnotchi für \(AppleScriptSource.appName(id)) ein."
                                 : "macOS antwortete mit Code \(code) – ohne Erlaubnis.",
                                 symbol: "info.circle", color: FamilyTheme.textSecondary)
                            Button("Automation-Einstellungen öffnen") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
            if prefs.notchMedia, let other = model.nowPlaying.competingNotchApp {
                note(IslandController.competingWarning(name: other),
                     symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
            }
        }
        if prefs.notchMedia {
            card("Auf dem Schreibtisch") {
                toggleRow("Cover und Titel auf dem Schreibtisch", isOn: $prefs.desktopMusic)
                    .onChange(of: prefs.desktopMusic) { model.applyNotchSetting() }
                if prefs.desktopMusic {
                    // 0.17.0 (Michael 27.10.): zweite Darstellung derselben Anzeige.
                    row("Darstellung") {
                        Picker("", selection: $prefs.desktopMusicStyle) {
                            Text("Widget").tag(Preferences.DesktopStyle.card)
                            Text("Plattenspieler").tag(Preferences.DesktopStyle.turntable)
                        }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                        .onChange(of: prefs.desktopMusicStyle) { model.applyNotchSetting() }
                    }
                }
                if prefs.desktopMusic && prefs.desktopMusicStyle == .turntable {
                    row("Bildschirm") {
                        Picker("", selection: $prefs.desktopMusicScreen) {
                            Text("Hauptbildschirm").tag("")
                            ForEach(NSScreen.screens.dropFirst(), id: \.self) { screen in
                                Text(verbatim: screen.localizedName).tag(DesktopMusicLink.uuid(of: screen))
                            }
                        }
                        .labelsHidden().frame(width: 220)
                        .onChange(of: prefs.desktopMusicScreen) { model.applyNotchSetting() }
                    }
                    toggleRow("Neonschrift „Now Playing“", isOn: $prefs.desktopMusicNeon)
                        .onChange(of: prefs.desktopMusicNeon) { model.applyNotchSetting() }
                    toggleRow("Start/Stopp-Knopf bedienen (unten links am Plattenspieler)", isOn: $prefs.desktopMusicTonearm)
                        .onChange(of: prefs.desktopMusicTonearm) { model.applyNotchSetting() }
                }
                note(prefs.desktopMusicStyle == .turntable
                     ? "Plattenspieler mittig, dahinter ein Farbverlauf aus dem Cover, unter deinen Schreibtisch-Symbolen. "
                       + "Sichtbar, solange Musik spielt oder pausiert, nach 10 Minuten Pause weg. Drüberfahren zeigt die "
                       + "Knöpfe, Klick auf die Hülle holt die App."
                     : "Ein echtes macOS-Widget wie Uhr und Kalender: Rechtsklick auf den Schreibtisch → „Widgets bearbeiten …“ "
                       + "→ „Gnotchi“, Größe wählen und ablegen. Zeigt Titel und Cover, solange Musik spielt oder pausiert, "
                       + "nach 10 Minuten Pause leer. Mittel und Groß mit Knöpfen.",
                     symbol: "photo.on.rectangle", color: FamilyTheme.textSecondary)
                // 0.20.0 (G46): Sperrbildschirm, ab Werk aus. Ohne SkyLight-Funktionen ausgegraut.
                toggleRow("Auf dem Sperrbildschirm zeigen", isOn: $prefs.lockScreenMusic)
                    .disabled(!LockScreenSpace.isAvailable)
                    .onChange(of: prefs.lockScreenMusic) { model.applyNotchSetting() }
                if prefs.lockScreenMusic && LockScreenSpace.isAvailable {
                    toggleRow("Titel verbergen (nur Knöpfe)", isOn: $prefs.lockScreenHideTitle)
                        .onChange(of: prefs.lockScreenHideTitle) { model.applyNotchSetting() }
                }
                note(LockScreenSpace.isAvailable
                     ? "Jeder am gesperrten Mac sieht den Titel und kann die Wiedergabe steuern. "
                       + "Klick aufs Cover zeigt es groß, nach 30 Sekunden kommt die kleine Karte zurück."
                     : "Unter dieser macOS-Version nicht verfügbar.",
                     symbol: "lock", color: FamilyTheme.textSecondary)
            }
        }
        card("Medienfilter") {
            // Zweispaltig: Mit allen installierten Wiedergabe-Apps würde das Fenster sonst höher als ein MacBook-Bildschirm.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FamilyTheme.Space.l), GridItem(.flexible())],
                      spacing: 0) {
                ForEach(mediaApps, id: \.id) { app in
                    // App-Namen aus dem lokalen Bundle, unbekannte als Bundle-ID → nie als Schlüssel lesen.
                    toggleRow(verbatim: app.name, isOn: Binding(
                        get: { !prefs.isMediaExcluded(app.id) },
                        set: { on in
                            prefs.setMediaExcluded(app.id, !on)
                            model.applyMediaFilter()
                        }))
                }
            }
            .disabled(!prefs.notchMedia)
        }
    }

    /// Apps zur Auswahl der Meeting-Apps: die Standardliste, schon gewählte und Apps, die in diesem Lauf das Mikrofon genutzt haben.
    /// „Jetzt erlauben“ mit Rückmeldung: Vorher tat der Knopf bei nicht laufender App nichts sichtbar (Michael 16.11., Musik).
    @ViewBuilder func allowButton(_ id: String) -> some View {
        let name = id == AppleScriptSource.music ? "Apple Musik" : AppleScriptSource.appName(id)
        Button("\(name) jetzt erlauben") {
            AutomationStatus.shared.lastRequest[id] = nil   // keine alte Meldung stehen lassen (Michael 16.11.: „läuft nicht“ blieb stehen)
            AutomationStatus.shared.request(id)
        }
            .buttonStyle(CardButtonStyle())
        if let code = AutomationStatus.shared.lastRequest[id], code != 0 {
            note(code == AppleScriptSource.notRunningError
                 ? "\(name) läuft nicht. Starte die App und klicke dann noch einmal: macOS fragt nur, solange sie läuft."
                 : code == AppleScriptSource.deniedError
                 ? "macOS hat die Erlaubnis verweigert und fragt nicht noch einmal. Schalte sie in Systemeinstellungen → Datenschutz & Sicherheit → Automation unter Gnotchi für \(name) ein."
                 : "macOS antwortete mit Code \(code) – ohne Erlaubnis.",
                 symbol: "info.circle", color: FamilyTheme.textSecondary)
        }
    }

    var meetingAppChoices: [String] {
        Array(Set(DuckLogic.defaultMeetingApps).union(prefs.meetingApps).union(model.activity.micAppsSeen)).sorted()
    }

    @ViewBuilder var activitiesTab: some View {
        @Bindable var prefs = prefs
        card("Anzeigen") {
            toggleRow("Rotation", isOn: $prefs.liveRotation)
                .onChange(of: prefs.liveRotation) { model.applyNotchSetting() }
            toggleRow("Batterie in der Ruhe-Insel", isOn: $prefs.batteryIdle)
                .onChange(of: prefs.batteryIdle) { model.applyNotchSetting() }
            toggleRow("Kopfhörer-Hinweis", isOn: $prefs.headphoneNotice)
                .onChange(of: prefs.headphoneNotice) { model.applyNotchSetting() }
            toggleRow("Kopfhörer-Aktivität", isOn: $prefs.headphoneActivity)
                .onChange(of: prefs.headphoneActivity) { model.applyNotchSetting() }
            toggleRow("Mikrofon & Kamera anzeigen", isOn: $prefs.micCamera)
                .onChange(of: prefs.micCamera) { model.applyNotchSetting() }
            toggleRow("Tippi-Aufnahme anzeigen", isOn: $prefs.tippiRecording)
                .onChange(of: prefs.tippiRecording) { model.applyNotchSetting() }
            toggleRow("Qotti-Kontingent anzeigen", isOn: $prefs.qottiQuota)
                .onChange(of: prefs.qottiQuota) { model.applyNotchSetting() }
            toggleRow("Termine aus Kalli anzeigen", isOn: $prefs.kalliEvents)
                .onChange(of: prefs.kalliEvents) { model.applyNotchSetting() }
            toggleRow("Updates der App-Familie", isOn: $prefs.familyUpdates)
                .onChange(of: prefs.familyUpdates) { model.applyNotchSetting() }
        }
        // G62: „Läuft gerade“ an Tippis Schreibtischgerät, ab Werk aus.
        card("Tippi-Gerät") {
            toggleRow("Läuft gerade an Tippis Schreibtischgerät", isOn: $prefs.tippiDevice)
                .onChange(of: prefs.tippiDevice) { model.applyNotchSetting() }
            if prefs.tippiDevice { TippiDeviceKeyRow { model.applyNotchSetting() } }
        }
        // G61: Schnelleingabe, ab Werk aus. Gespeichert wird über Kalli, Gnotchi hat keinen Kalenderzugriff.
        card("Schnelleingabe") {
            toggleRow("Termine und Erinnerungen per Kürzel anlegen", isOn: $prefs.quickEntry)
                .onChange(of: prefs.quickEntry) { model.applyNotchSetting() }
            if prefs.quickEntry {
                row("Kürzel") {
                    HotKeyRecorder(hotKey: $prefs.quickEntryHotKey)
                        .onChange(of: prefs.quickEntryHotKey) { model.applyNotchSetting() }
                }
            }
            note("Schreib zum Beispiel „Zahnarzt morgen 15 Uhr“. Mit Uhrzeit wird es ein Termin, sonst eine Erinnerung, "
                 + "Tab wechselt. ↵ speichert, ⌘Z direkt danach nimmt zurück. Gespeichert wird über Kalli, Kalli muss "
                 + "laufen.", symbol: "info.circle", color: .secondary)
        }
        // 0.9.0 Code & KI (G34/G35): trägt Hooks in ~/.claude/settings.json ein – deshalb Erklärung und Hinweis direkt hier.
        card("Code & KI") {
            toggleRow("Claude Code in der Notch", isOn: $prefs.claudeCode)
                .onChange(of: prefs.claudeCode) { model.applyNotchSetting() }
            if let warn = model.activity.claudeSetupNote, prefs.claudeCode {
                note(warn, symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
            } else {
                note(prefs.claudeCode
                     ? "Eingetragen in ~/.claude/settings.json (nur Gnotchis eigene Einträge, Sicherung daneben)."
                     : "Zeigt laufende Claude-Code-Sitzungen: arbeitet, wartet auf Erlaubnis, fertig. Trägt dafür "
                       + "eigene Hooks in ~/.claude/settings.json ein; aus entfernt genau diese.",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
            }
        }
    }

    /// Audio (Michael 16.11.: „Menüstruktur unübersichtlich in einem zu langen Fenster“): alles, was Lautstärke betrifft.
    @ViewBuilder var audioTab: some View {
        @Bindable var prefs = prefs
        // 0.29.0 Meeting-Leiser (G53): Spotify und Musik leiser, solange eine gewählte App das Mikrofon nutzt.
        card("Meeting-Leiser") {
            toggleRow("Musik im Meeting leiser", isOn: $prefs.meetingDuck)
                .onChange(of: prefs.meetingDuck) { model.applyNotchSetting() }
            if prefs.meetingDuck {
                row("Leiser auf") {
                    Picker("Leiser auf", selection: $prefs.meetingDuckPercent) {
                        ForEach(DuckLogic.percentChoices, id: \.self) { Text(verbatim: "\($0) % der Lautstärke").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: prefs.meetingDuckPercent) { model.applyNotchSetting() }
                }
                ForEach(meetingAppChoices, id: \.self) { name in
                    toggleRow(name, isOn: Binding(
                        get: { prefs.meetingApps.contains(name) },
                        set: { prefs.setMeetingApp(name, on: $0); model.applyNotchSetting() }))
                }
                // swiftlint:disable:next line_length
                note("Gilt für Spotify und Musik. Tippi-Diktat zählt nicht. Für Google Meet im Browser wähle den Browser (er erscheint hier, sobald er das Mikrofon genutzt hat). Gnotchi merkt sich die ursprüngliche Lautstärke und stellt sie nach dem Meeting, beim Beenden und beim Start wieder her; änderst du sie selbst, gilt dein Wert. Dafür läuft die Mikrofon-Erkennung, auch wenn „Mikrofon & Kamera anzeigen“ aus ist; die Punkte in der Insel erscheinen dann trotzdem.",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
                ForEach([AppleScriptSource.spotify, AppleScriptSource.music], id: \.self) { id in
                    let name = id == AppleScriptSource.music ? "Apple Musik (die App „Musik“)" : AppleScriptSource.appName(id)
                    if !AutomationStatus.shared.isAllowed(id) {
                        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                            // Nicht gestartet: nichts zu erlauben, macOS fragt nur bei laufender App (Michael 16.11.: Knopf wirkte kaputt).
                            note("\(name) läuft nicht, die Erlaubnis lässt sich erst anfordern, wenn sie läuft. Mit Spotify hat das nichts zu tun.",
                                 symbol: "info.circle", color: FamilyTheme.textSecondary)
                        } else {
                            note("\(name): Gnotchi darf die App noch nicht steuern. Ohne diese Erlaubnis bleibt die Lautstärke unverändert, und Gnotchi zeigt den Titel nicht, wenn macOS ihn nicht selbst meldet. macOS fragt beim ersten Spulen (Spotify) bzw. Shuffle-Klick (Musik) – oder jetzt auf Klick (die App muss laufen).",
                                 symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                            allowButton(id)
                        }
                    }
                }
            }
        }
        // Mixer Stufe 2 (G55): Regler je App über Prozess-Taps. Braucht „Audio-Aufnahme“, ab Werk aus.
        card("Mixer") {
            note("Ausgabe- und Mikrofon-Favoriten legst du im Mixer selbst fest: Auswahlfeld öffnen, unten „Favoriten …“.",
                 symbol: "star", color: FamilyTheme.textSecondary)
            toggleRow("Lautstärke je App (Audio-Aufnahme)", isOn: $prefs.appVolume)
                .onChange(of: prefs.appVolume) { model.applyNotchSetting() }
            note(prefs.appVolume
                 // swiftlint:disable:next line_length
                 ? "Im Mixer (Menüleisten-Symbol) bekommt jede App mit Ton einen Regler von 0 bis 200 %. Dafür braucht Gnotchi die Freigabe für Systemaudio. Fragt macOS beim ersten Verschieben nicht, trag sie selbst ein: Systemeinstellungen → Datenschutz & Sicherheit → „Aufnahme von Bildschirm & Systemaudio“ → „+“ → Gnotchi. Solange ein Regler nicht auf 100 % steht, hört Gnotchi den Ton dieser App im Arbeitsspeicher mit; bei 100 % endet das sofort. Gnotchi merkt sich den Wert je App und stellt ihn wieder ein, sobald die App erneut Ton ausgibt (Werte bis 5 % nicht, damit nichts still stumm bleibt). Gerätewechsel setzen alle Regler vorübergehend zurück."
                 // swiftlint:disable:next line_length
                 : "Aus: Regler gibt es nur für Spotify und Musik. Ein Regler je App braucht die Freigabe „Audio-Aufnahme“: Sie erlaubt Gnotchi, den Ton einer App mitzuhören, solange ihr Regler nicht auf 100 % steht. Der Ton bleibt im Arbeitsspeicher, wird nicht gespeichert und nicht gesendet.",
                 symbol: "info.circle", color: FamilyTheme.textSecondary)
            if !model.mixer.remembered.isEmpty {
                Button("Gemerkte Lautstärken vergessen (\(model.mixer.remembered.count))") { model.mixer.forgetRemembered() }
                    .buttonStyle(CardButtonStyle())
            }
        }
        // 0.35.0 Stream Deck (G59): Befehle nur vom eigenen, signierten Plugin, gestartet von Elgatos Stream Deck.
        card("Stream Deck") {
            toggleRow("Steuerung über Stream Deck", isOn: $prefs.streamDeck)
                .onChange(of: prefs.streamDeck) { model.applyNotchSetting() }
            // swiftlint:disable:next line_length
            note("Drehregler: Lautstärke je App (drücken = stumm, auf die Leiste tippen = Play/Pause), Tasten: Play/Pause, Weiter, Zurück. Gnotchi nimmt Befehle nur vom eigenen Plugin an, und nur, wenn Elgatos Stream-Deck-App es gestartet hat. Auf der Leiste steht der laufende Titel; dafür bekommt die Stream-Deck-App Titel und Interpret. Browser lassen sich nur steuern, solange sie gerade spielen.",
                 symbol: "info.circle", color: FamilyTheme.textSecondary)
            if prefs.streamDeck {
                if let old = model.activity.deckPluginOutdated {
                    note("Im Stream Deck ist noch das Plugin \(old) installiert. Klick „Plugin installieren“, damit es zu diesem Gnotchi passt.",
                         symbol: "arrow.down.circle", color: FamilyTheme.warning)
                }
                Button("Plugin installieren") { deckInstallResult = DeckLink.installPlugin() }
                    .buttonStyle(CardButtonStyle())
                if case .failure(let e)? = deckInstallResult {
                    note(e == .unsigned ? "Das Plugin in Gnotchi ist nicht gültig signiert – nichts übergeben."
                         : e == .missing ? "Das Plugin fehlt in diesem Gnotchi." : "Das Paket ließ sich nicht packen.",
                         symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                }
                // G59 Punkt 10: Browser-Weg, ab Werk aus. Gnotchi schaltet Heliums Schalter nie selbst.
                toggleRow("YouTube in Helium gezielt steuern", isOn: $prefs.deckBrowserTab)
                // swiftlint:disable:next line_length
                note("Play/Pause und Titel für YouTube-Tabs in Helium, auch wenn gleichzeitig Spotify läuft. Dafür muss in Helium „Darstellung → Entwickler → JavaScript von Apple Events erlauben“ an sein, und macOS fragt nach der Steuerung von Helium. Achtung: Mit diesem Schalter kann jedes Programm mit Steuerungsfreigabe für Helium JavaScript in allen Tabs ausführen, auch in angemeldeten. Gnotchi selbst führt es nur in Tabs von youtube.com aus und schaltet den Helium-Schalter nie selbst.",
                     symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
                // G59 Punkt 10e: Cover, ab Werk aus.
                toggleRow("Cover auf dem Deck", isOn: $prefs.deckCover)
                // swiftlint:disable:next line_length
                note("Zeigt das Cover (bei YouTube in Helium das Vorschaubild) auf der Wiedergabe-Taste. Das Bild geht dafür an die Stream-Deck-App von Elgato, auch private Cover. Gnotchi verkleinert es vorher selbst und lädt nichts aus dem Netz. Braucht das aktuelle Plugin.",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
                if !prefs.appVolume {
                    note("Für Browser & Co. braucht der Regler „Lautstärke je App“ oben. Spotify und Musik gehen auch ohne.",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
            }
        }
    }

    /// Tasten: die Werkzeuge um die große Insel samt ihren Einstellungen (Timer, Spiegel, Wetter).
    @ViewBuilder var keysTab: some View {
        @Bindable var prefs = prefs
        // 0.28.0 Tasten-Ring: Werkzeuge als runde Tasten um die große Insel. Ein Schalter je Taste.
        card("Tasten um die Insel") {
            toggleRow("Tasten um die große Insel", isOn: $prefs.ring)
                .onChange(of: prefs.ring) { model.applyNotchSetting() }
            if prefs.ring {
                ForEach(RingButton.allCases.filter { !$0.alwaysOn && $0 != .terminal }, id: \.self) { b in
                    toggleRow(b.label, isOn: Binding(
                        get: { prefs.isRingButtonOn(b) },
                        set: { on in
                            prefs.setRingButton(b, on: on)
                            // Mirror und Ablage sind harmlos und gehören zur Taste; Wetter (Netz) und Zwischenablage
                            // (liest mit) schaltest du bewusst in ihrem Reiter ein.
                            if on, b == .mirror { prefs.mirror = true }
                            if on, b == .shelf { prefs.shelf = true }
                            model.applyNotchSetting()
                        }))
                }
                if prefs.isRingButtonOn(.mic) {
                    toggleRow("Mikrofon-Taste immer zeigen", isOn: $prefs.ringMicAlways)
                        .onChange(of: prefs.ringMicAlways) { model.applyNotchSetting() }
                    note("Ohne den Schalter erscheint die Taste nur, solange eine App das Mikrofon nutzt, und bleibt, solange es stumm ist.",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
                if prefs.isRingButtonOn(.weather) && !prefs.weather {
                    note("Wetter ist aus: Die Taste erscheint, sobald du es weiter unten bei „Wetter“ einschaltest.",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
                if prefs.isRingButtonOn(.clipboard) && !prefs.clipboard {
                    note("Zwischenablage ist aus: Die Taste erscheint, sobald du sie im Reiter „Zwischenablage“ einschaltest.",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
                note("Anheften und Einstellungen sind immer da. Ohne die Tasten steht wieder die kleine Symbolleiste in der Insel.",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
            }
        }
        card("Timer und Spiegel") {
            toggleRow("Timer-Ablauf bis Klick anzeigen", isOn: $prefs.timerAlarm)
                .onChange(of: prefs.timerAlarm) { model.applyNotchSetting() }
            row("Timer-Ton") {
                Picker("Timer-Ton", selection: $prefs.timerSound) {
                    Text(verbatim: "Kein Ton").tag(CountdownTimer.silent)
                    Divider()
                    ForEach(CountdownTimer.sounds, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                // Probehören beim Auswählen.
                .onChange(of: prefs.timerSound) { CountdownTimer.play(prefs.timerSound) }
            }
            toggleRow("Spiegel in der Notch", isOn: $prefs.mirror)
                .onChange(of: prefs.mirror) { model.applyNotchSetting() }
        }
        weatherTab
    }

    @ViewBuilder var shelfTab: some View {
        @Bindable var prefs = prefs
        card("Dateiablage") {
            toggleRow("Dateiablage in der Notch", isOn: $prefs.shelf)
                .onChange(of: prefs.shelf) { model.applyNotchSetting() }
            toggleRow("Nach dem Rausziehen entfernen", isOn: $prefs.shelfRemoveOnDrag)
                .disabled(!prefs.shelf)
            toggleRow("Vorschau beim Überfahren", isOn: $prefs.shelfPreview)
                .disabled(!prefs.shelf)
            toggleRow("Beim Umwandeln Ortsdaten entfernen", isOn: $prefs.shelfStripLocation)
                .disabled(!prefs.shelf)
            toggleRow("Bildschirmfotos automatisch ablegen", isOn: $prefs.shelfScreenshots)
                .disabled(!prefs.shelf)
                .onChange(of: prefs.shelfScreenshots) { model.applyNotchSetting() }
            if prefs.shelf && prefs.shelfScreenshots {
                // 0.16.0: nur der Verweis läuft ab, die Datei bleibt (Michael 27.10.).
                row("Bildschirmfotos behalten") {
                    Picker("Bildschirmfotos behalten", selection: $prefs.shelfScreenshotMinutes) {
                        ForEach(Preferences.screenshotMinuteChoices, id: \.self) { m in
                            Text(verbatim: m == 0 ? "immer" : "\(m) Min.").tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                note("Neue Bildschirmfotos (macOS und CleanShot) landen von selbst hier. Liegen sie auf dem Schreibtisch, "
                     + "fragt macOS einmal nach dem Zugriff – ohne Erlauben bleiben sie draußen. Nach der gewählten Zeit "
                     + "verschwinden sie wieder aus der Ablage; die Datei selbst bleibt liegen.",
                     symbol: "camera.viewfinder", color: FamilyTheme.textSecondary)
            }
            note("Zieh eine Datei zur Notch, um sie abzulegen, und später woanders wieder heraus. Die Ablage merkt sich "
                 + "nur, wo die Datei liegt – entfernen löscht nie etwas.", symbol: "info.circle", color: FamilyTheme.textSecondary)
        }
    }

    @ViewBuilder var weatherTab: some View {
        @Bindable var prefs = prefs
        card("Wetter") {
            toggleRow("Wetter in der Notch", isOn: $prefs.weather)
                .onChange(of: prefs.weather) { model.applyNotchSetting() }
            WeatherSettings(onChange: { model.applyNotchSetting() })
        }
    }

    /// Mitteilungen und Anrufe (0.6.0, G28–G30). Ab Werk aus; braucht das Hilfsprogramm mit Bedienungshilfen.
    @ViewBuilder var notifyCard: some View {
        @Bindable var prefs = prefs
        card("Mitteilungen") {
            toggleRow("Mitteilungen in der Notch", isOn: $prefs.notifications)
                .onChange(of: prefs.notifications) {
                    if prefs.notifications { prefs.seedNotifyApps(NotifyApps.suggestedInstalled) }
                    model.applyNotchSetting()
                }
            if !prefs.notifications {
                note("Ein eigenes Hilfsprogramm „Gnotchi Mitteilungen“ liest Apples Mitteilungen und braucht dafür die "
                     + "Freigabe „Gerätesteuerung und Datenzugriff“. Gnotchi selbst bleibt ohne.", symbol: "info.circle",
                     color: FamilyTheme.textSecondary)
            } else {
                switch model.activity.notifyTrust {
                case nil:
                    note("Hilfsprogramm startet …", symbol: "hourglass", color: FamilyTheme.textSecondary)
                case false?:
                    row(nil) {
                        Label("„Gnotchi Mitteilungen“ in „Gerätesteuerung und Datenzugriff“ freigeben",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(FamilyTheme.warning)
                        Spacer()
                        Button("Öffnen …") { NotifyApps.openAccessibilitySettings() }
                            .buttonStyle(CardButtonStyle())
                    }
                case true?:
                    EmptyView()
                }
                toggleRow("Anrufe in der Notch", isOn: $prefs.notifyCalls)
                    .onChange(of: prefs.notifyCalls) { model.applyNotchSetting() }
                toggleRow("Ungelesen-Zahlen zeigen", isOn: $prefs.notifyBadges)
                    .onChange(of: prefs.notifyBadges) { model.applyNotchSetting() }
                if prefs.notifyBadges {
                    toggleRow("Zähler auch in der kleinen Insel", isOn: $prefs.compactUnread)
                        .onChange(of: prefs.compactUnread) { model.applyNotchSetting() }
                    note("Zahlen von den Dock-Symbolen der ausgewählten Apps – nur Apps, die im Dock liegen.",
                         symbol: "info.circle", color: FamilyTheme.textSecondary)
                }
                divider
                Text("Apps")
                    .font(FamilyTheme.font(.callout, weight: .medium))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .padding(.top, FamilyTheme.Space.s)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: FamilyTheme.Space.l), GridItem(.flexible())],
                          spacing: 0) {
                    ForEach(NotifyApps.list(selected: prefs.notifyApps ?? []), id: \.id) { app in
                        toggleRow(verbatim: app.name, isOn: Binding(
                            get: { prefs.isNotifyApp(app.id) },
                            set: { on in
                                prefs.setNotifyApp(app.id, on)
                                model.applyNotchSetting()
                            }))
                    }
                }
                Button("App hinzufügen …") {
                    guard let id = NotifyApps.pickApp() else { return }
                    prefs.setNotifyApp(id, true)
                    model.applyNotchSetting()
                }
                .buttonStyle(CardButtonStyle())
                .padding(.vertical, FamilyTheme.Space.s)
            }
        }
    }

    /// Medienfilter: bekannte installierte Apps, seit Start gesehene und ausgeschlossene (G25).
    var mediaApps: [(id: String, name: String)] {
        NowPlayingModel.filterApps(known: NowPlayingModel.knownPlayers, seen: model.nowPlaying.seenApps,
                                   excluded: prefs.mediaExcluded, name: AppIcons.name(for:))
    }
}
