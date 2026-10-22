import SwiftUI

/// Inhalte der Reiter (Michael 22.10.: „Einstellungsfenster zu lang, besser strukturieren“). Zuordnung nach Zweck:
/// Allgemein (Start, Updates, Aufklappen) · Wiedergabe (Musik, Medienfilter) · Aktivitäten (was die Insel sonst zeigt,
/// Timer, Spiegel) · Mitteilungen · Wetter.
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
            if prefs.notchMedia, let other = model.nowPlaying.competingNotchApp {
                note(IslandController.competingWarning(name: other),
                     symbol: "exclamationmark.triangle", color: FamilyTheme.warning)
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

    @ViewBuilder var activitiesTab: some View {
        @Bindable var prefs = prefs
        card("Anzeigen") {
            toggleRow("Rotation", isOn: $prefs.liveRotation)
                .onChange(of: prefs.liveRotation) { model.applyNotchSetting() }
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
    }

    @ViewBuilder var shelfTab: some View {
        @Bindable var prefs = prefs
        card("Dateiablage") {
            toggleRow("Dateiablage in der Notch", isOn: $prefs.shelf)
                .onChange(of: prefs.shelf) { model.applyNotchSetting() }
            toggleRow("Nach dem Rausziehen entfernen", isOn: $prefs.shelfRemoveOnDrag)
                .disabled(!prefs.shelf)
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
                     + "Bedienungshilfen-Freigabe. Gnotchi selbst bleibt ohne.", symbol: "info.circle",
                     color: FamilyTheme.textSecondary)
            } else {
                switch model.activity.notifyTrust {
                case nil:
                    note("Hilfsprogramm startet …", symbol: "hourglass", color: FamilyTheme.textSecondary)
                case false?:
                    row(nil) {
                        Label("Bedienungshilfen für „Gnotchi Mitteilungen“ freigeben", systemImage: "exclamationmark.triangle")
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
