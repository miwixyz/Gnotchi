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
                note("Die Insel ist in Arbeit, der Schalter wirkt ab der nächsten Version",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
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
        .onAppear { login = LoginItem.state }
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

    private func note(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
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
