import SwiftUI

/// Einstellungen als eigenes Fenster, gleiche Bausteine wie Seam (Verlauf, weiße Karten, Titel in
/// der Karte, Plus Jakarta Sans) statt Apples grauem Formular.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var prefs
    /// Autostart-Zustand: von macOS gelesen, nicht gespiegelt (siehe LoginItem). Seam-Code-Audit
    /// 09.10. (C3): vorher wurde ein Fehler verworfen und „Freigabe nötig“ als „aus“ gezeigt.
    @State private var login = LoginItem.state
    @State private var loginError: String?

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
            card("Notch") {
                toggleRow("Musik in der Notch", isOn: $prefs.notchMedia)
                    .onChange(of: prefs.notchMedia) { model.applyNotchSetting() }
                toggleRow("Kopfhörer-Hinweis", isOn: $prefs.headphoneNotice)
                    .onChange(of: prefs.headphoneNotice) { model.applyNotchSetting() }
                toggleRow("Mikrofon & Kamera anzeigen", isOn: $prefs.micCamera)
                    .onChange(of: prefs.micCamera) { model.applyNotchSetting() }
                toggleRow("Tippi-Aufnahme anzeigen", isOn: $prefs.tippiRecording)
                    .onChange(of: prefs.tippiRecording) { model.applyNotchSetting() }
                toggleRow("Qotti-Kontingent anzeigen", isOn: $prefs.qottiQuota)
                    .onChange(of: prefs.qottiQuota) { model.applyNotchSetting() }
                toggleRow("Termine aus Kalli anzeigen", isOn: $prefs.kalliEvents)
                    .onChange(of: prefs.kalliEvents) { model.applyNotchSetting() }
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
                .disabled(!prefs.notchMedia)
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
            card("Live-Aktivitäten") {
                toggleRow("Rotation", isOn: $prefs.liveRotation)
                    .onChange(of: prefs.liveRotation) { model.applyNotchSetting() }
                toggleRow("Kopfhörer-Aktivität", isOn: $prefs.headphoneActivity)
                    .onChange(of: prefs.headphoneActivity) { model.applyNotchSetting() }
                toggleRow("Updates der App-Familie", isOn: $prefs.familyUpdates)
                    .onChange(of: prefs.familyUpdates) { model.applyNotchSetting() }
                divider
                Text("Medienfilter")
                    .font(FamilyTheme.font(.callout, weight: .medium))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .padding(.top, FamilyTheme.Space.s)
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
            card("Allgemein") {
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
        }
        .frame(width: 400)
        .padding(FamilyTheme.Space.l)
        .font(FamilyTheme.font(.body))
        .foregroundStyle(FamilyTheme.textPrimary)
        .tint(FamilyTheme.accent)
        .fixedSize(horizontal: false, vertical: true)
        .familyBackground()
        .onAppear {
            login = LoginItem.state
            model.recheckNotch()
        }
    }

    /// Medienfilter: bekannte installierte Apps, seit Start gesehene und ausgeschlossene (G25).
    private var mediaApps: [(id: String, name: String)] {
        NowPlayingModel.filterApps(known: NowPlayingModel.knownPlayers, seen: model.nowPlaying.seenApps,
                                   excluded: prefs.mediaExcluded, name: AppIcons.name(for:))
    }

    /// „Sofort“, „0,3 s“, „0,6 s“, „1 s“ – deutsches Komma, ganze Sekunden ohne Nachkommastelle.
    nonisolated static func delayLabel(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Sofort" }
        let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return text.replacingOccurrences(of: ".", with: ",") + " s"
    }

    // MARK: - Bausteine (aus Seams SettingsView, 18.10.)

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(FamilyTheme.font(.headline))
                .foregroundStyle(FamilyTheme.textPrimary)
                .padding(.bottom, FamilyTheme.Space.xs)
            content()
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func row<Control: View>(_ title: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            if let title {
                Text(title).foregroundStyle(FamilyTheme.textPrimary)
                Spacer(minLength: FamilyTheme.Space.m)
            }
            control()
        }
        .frame(minHeight: 34)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(FamilySwitchStyle())
        }
    }

    /// Schalter mit fremdem Text (App-Name): `Text(verbatim:)`, nie Übersetzungsschlüssel oder Markdown.
    private func toggleRow(verbatim title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Text(verbatim: title).foregroundStyle(FamilyTheme.textPrimary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: FamilyTheme.Space.m)
            Toggle(isOn: isOn) { Text(verbatim: title) }
                .labelsHidden()
                .toggleStyle(FamilySwitchStyle())
        }
        .frame(minHeight: 34)
    }

    /// `Text(verbatim:)`: Hinweise können App-Namen enthalten (Automation verweigert) – nie als
    /// Markdown oder Übersetzungsschlüssel lesen.
    private func note(_ text: String, symbol: String, color: Color) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: symbol) }
            .font(FamilyTheme.font(.callout))
            .foregroundStyle(color)
            .padding(.vertical, FamilyTheme.Space.xs)
    }

    private var divider: some View {
        Rectangle().fill(FamilyTheme.cardStroke).frame(height: 0.8)
    }
}

/// Knopf in einer Karte (aus Seam): Kartenrand-Ton, Radius 9, beim Überfahren Akzent.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardButtonLabel(configuration: configuration)
    }
}

private struct CardButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let active = hovered && isEnabled
        configuration.label
            .font(FamilyTheme.font(.callout, weight: .medium))
            .foregroundStyle(active ? FamilyTheme.accent : FamilyTheme.textPrimary)
            .padding(.horizontal, FamilyTheme.Space.m)
            .frame(minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? FamilyTheme.accent.opacity(0.14) : FamilyTheme.cardStroke.opacity(0.45))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(active ? FamilyTheme.accent.opacity(0.6) : .clear, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// Eigener Schalter: Apples `.switch` wird grau, sobald das Fenster nicht aktiv ist
/// (gemessen 09.10. im Vorschau-Render und in Michaels Screenshot, Seam) — das Gnotchi-Fenster
/// hat nur eigene Bedienelemente und sieht immer gleich aus. Für VoiceOver bleibt es ein Toggle.
struct FamilySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        FamilySwitch(configuration: configuration)
    }
}

private struct FamilySwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let on = configuration.isOn
        Capsule()
            .fill(on ? FamilyTheme.accent : FamilyTheme.textSecondary.opacity(0.28))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.18), value: on)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}
