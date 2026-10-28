import SwiftUI

/// Einstellungen als eigenes Fenster, gleiche Bausteine wie Seam (Verlauf, weiße Karten, Titel in
/// der Karte, Plus Jakarta Sans) statt Apples grauem Formular.
struct SettingsView: View {
    @Environment(AppModel.self) var model
    @Environment(Preferences.self) var prefs
    /// Autostart-Zustand: von macOS gelesen, nicht gespiegelt (siehe LoginItem). Seam-Code-Audit
    /// 09.10. (C3): vorher wurde ein Fehler verworfen und „Freigabe nötig“ als „aus“ gezeigt.
    @State var login = LoginItem.state
    @State var loginError: String?
    /// Zuletzt gewählter Reiter (Michael 22.10.: Fenster war zu lang → Reiter oben wie Safari/Mail).
    @AppStorage("settingsTab") private var tab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general, playback, activities, notify, weather, shelf, clipboard
        var id: Self { self }

        var title: String {
            switch self {
            case .general: "Allgemein"
            case .playback: "Wiedergabe"
            case .activities: "Aktivitäten"
            case .notify: "Mitteilungen"
            case .weather: "Wetter"
            case .shelf: "Ablage"
            case .clipboard: "Zwischenablage"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .playback: "music.note"
            case .activities: "square.stack.3d.up"
            case .notify: "bell.badge"
            case .weather: "cloud.sun"
            case .shelf: "tray.full"
            case .clipboard: "doc.on.clipboard"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                switch tab {
                case .general: generalTab
                case .playback: playbackTab
                case .activities: activitiesTab
                case .notify: notifyCard
                case .weather: weatherTab
                case .shelf: shelfTab
                case .clipboard: clipboardTab
                }
            }
            .padding(FamilyTheme.Space.l)
        }
        .frame(width: 540)   // 0.11.0: sieben Reiter (vorher 440 bei sechs)
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

    /// Reiterleiste oben (Symbol über Titel), wie die Einstellungen von Safari und Mail.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 17, weight: .medium)).frame(height: 20)
                        Text(t.title).font(FamilyTheme.font(.caption, weight: .medium)).lineLimit(1).fixedSize()
                    }
                    // Breite nach Text statt fest 74 pt: „Zwischenablage“ war abgeschnitten (Fensterbild 28.10., G45).
                    .padding(.horizontal, 6)
                    .frame(minWidth: 62, minHeight: 48, maxHeight: 48)
                    .foregroundStyle(tab == t ? FamilyTheme.accent : FamilyTheme.textSecondary)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tab == t ? FamilyTheme.accent.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(t.title))
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(.top, FamilyTheme.Space.m)
        .frame(maxWidth: .infinity)
    }

    /// „Sofort“, „0,3 s“, „0,6 s“, „1 s“ – deutsches Komma, ganze Sekunden ohne Nachkommastelle.
    nonisolated static func delayLabel(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Sofort" }
        let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return text.replacingOccurrences(of: ".", with: ",") + " s"
    }

    // MARK: - Bausteine (aus Seams SettingsView, 18.10.)

    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    func row<Control: View>(_ title: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: FamilyTheme.Space.m) {
            if let title {
                Text(title).foregroundStyle(FamilyTheme.textPrimary)
                Spacer(minLength: FamilyTheme.Space.m)
            }
            control()
        }
        .frame(minHeight: 34)
    }

    func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(FamilySwitchStyle())
        }
    }

    /// Schalter mit fremdem Text (App-Name): `Text(verbatim:)`, nie Übersetzungsschlüssel oder Markdown.
    func toggleRow(verbatim title: String, isOn: Binding<Bool>) -> some View {
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
    func note(_ text: String, symbol: String, color: Color) -> some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: symbol) }
            .font(FamilyTheme.font(.callout))
            .foregroundStyle(color)
            .padding(.vertical, FamilyTheme.Space.xs)
    }

    var divider: some View {
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
