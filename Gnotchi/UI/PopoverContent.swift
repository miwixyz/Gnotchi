import AppKit
import SwiftUI

/// Menüleisten-Popover (0.30.0, G54): Übersicht aller Funktionen statt der einfachen Menüliste. Reiter **Mixer** (Ausgabe,
/// Mikrofon, Apps mit Ton samt AirPlay/Bluetooth) und **Funktionen** (Timer, Wach bleiben, Bildschirmfoto,
/// Geschwindigkeitstest, Status). Unten Einstellungen, Hilfe, Updates, Beenden. Ersetzt `MenuContent` (Menü-Stil);
/// Tastenkürzel des alten Menüs entfallen im Fenster-Stil.
struct PopoverContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("popoverTab") private var tabRaw = Tab.mixer.rawValue
    @State private var mixerOverride: MixerModel?
    /// Gemessene Höhe des Inhalts: Ein ScrollView hat im Fenster-Menü keine eigene Höhe und fiele auf null zusammen
    /// (Fund 15.11. am echten Symbol: Reiter und Fuß da, Inhalt leer).
    @State private var contentHeight: CGFloat = 0

    /// Der Mixer gehört der App (`AppModel.mixer`), damit ein Regler je App das Popover überdauert; Tests geben einen eigenen mit.
    init(mixer: MixerModel? = nil) { _mixerOverride = State(initialValue: mixer) }
    private var mixer: MixerModel { mixerOverride ?? model.mixer }

    enum Tab: String, CaseIterable {
        case mixer, functions
        var symbol: String { self == .mixer ? "slider.horizontal.3" : "square.grid.2x2" }
        var title: String { self == .mixer ? "Mixer" : "Funktionen" }
    }

    private var tab: Tab { Tab(rawValue: tabRaw) ?? .mixer }

    var body: some View {
        VStack(spacing: 12) {
            notices
            tabBar
            ScrollView {
                Group {
                    if tab == .mixer { MixerView(model: mixer) } else { FunctionsView(onCustomTimer: askCustomTimer) }
                }
                .padding(.horizontal, 2)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.hidden)
            .frame(height: max(1, min(contentHeight, 520)))
            footer
        }
        .padding(14)
        .frame(width: 360)
        // Der Mixer fragt nur ab, solange das Popover sichtbar ist (kein Dauer-Beobachter).
        .background(WindowVisibility { visible in mixer.setVisible("popover", visible) })
    }

    // MARK: Teile

    /// Zweite Notch-App und bereites Update stehen ganz oben (wie im alten Menü).
    @ViewBuilder private var notices: some View {
        if let other = model.nowPlaying.competingNotchApp {
            Button { open(AppModel.WindowID.help) } label: {
                Label { Text(verbatim: IslandController.competingWarning(name: other)) }
                    icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.system(size: 12)).foregroundStyle(FamilyTheme.warning)
            }
            .buttonStyle(.plain)
        }
        if let updater = model.updater, let version = updater.pendingVersion {
            // Versionsnummer kommt aus dem Appcast → nie als Übersetzungsschlüssel/Markdown lesen (G5).
            Button { updater.checkForUpdates() } label: {
                Label { Text(verbatim: "Update \(version) verfügbar …") } icon: { Image(systemName: "arrow.down.circle.fill") }
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tabRaw = t.rawValue } label: {
                    Label { Text(verbatim: t.title) } icon: { Image(systemName: t.symbol) }
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(t == tab ? Color.primary.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.quaternary.opacity(0.4)))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton("Einstellungen", "gearshape") { open(AppModel.WindowID.settings) }
            footerButton("Hilfe", "questionmark.circle") { open(AppModel.WindowID.help) }
            footerButton("Updates", "arrow.triangle.2.circlepath") { model.updater?.checkForUpdates() }
                .disabled(!(model.updater?.canCheck ?? false))
            footerButton("Beenden", "power") { NSApp.terminate(nil) }
        }
    }

    private func footerButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(verbatim: title).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.4)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Meldet zugleich `openWindow` an AppModel (falls das Menüleisten-Symbol es nicht schon getan hat).
    private func open(_ id: String) {
        let action = openWindow
        model.registerWindowOpener { action(id: $0) }
        model.showWindow(id)
    }

    /// Eigene Zeit (Michael 21.10.): kleines Fenster mit Minuten-Feld, vorbelegt mit der zuletzt gewählten Zeit.
    private func askCustomTimer() {
        let last = CountdownTimer.clampCustom(UserDefaults.standard.object(forKey: CountdownTimer.customKey) as? Int ?? 30)
        let alert = NSAlert()
        alert.messageText = "Timer mit eigener Zeit"
        alert.informativeText = "Minuten (1 bis 180) und optional ein Name:"
        let field = NSTextField(string: "\(last)")
        field.frame = NSRect(x: 0, y: 30, width: 80, height: 24)
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Name (optional)"
        nameField.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 54))
        box.addSubview(field)
        box.addSubview(nameField)
        field.nextKeyView = nameField
        alert.accessoryView = box
        alert.addButton(withTitle: "Starten")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let minutes = CountdownTimer.parseCustom(field.stringValue) else { return NSSound.beep() }
        UserDefaults.standard.set(minutes, forKey: CountdownTimer.customKey)
        model.activity.startTimer(minutes: minutes, name: nameField.stringValue)
    }
}

/// Reiter „Funktionen“: dieselben Werkzeuge wie der Tasten-Ring, direkt ausführbar, auch ohne die Insel aufzuklappen.
private struct FunctionsView: View {
    @Environment(AppModel.self) private var model
    let onCustomTimer: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            card("Timer in Minuten") {
                HStack(spacing: 6) {
                    ForEach(CountdownTimer.choices, id: \.self) { m in
                        chip("\(m)") { model.activity.startTimer(minutes: m) }
                    }
                    chip("Eigene …", action: onCustomTimer)
                }
                if let t = model.activity.timer {
                    HStack {
                        Text(verbatim: t.name.map { "Läuft: \($0)" } ?? "Timer läuft").font(.system(size: 12))
                            .foregroundStyle(FamilyTheme.textSecondary)
                        Spacer()
                        chip("Stopp") { model.activity.stopTimer() }
                    }
                }
            }
            if let awake = model.activity.awake {
                card("Wach bleiben") {
                    HStack(spacing: 6) {
                        ForEach([1, 2, 4], id: \.self) { h in chip("\(h) h") { awake.turnOn(hours: h) } }
                        chip("Bis aus") { awake.turnOn(hours: nil) }
                        if awake.isActive { chip("Aus") { awake.turnOff() } }
                    }
                    if awake.isActive {
                        Text(verbatim: "Der Mac schläft gerade nicht ein.").font(.system(size: 12))
                            .foregroundStyle(FamilyTheme.textSecondary)
                    }
                }
            }
            card("Werkzeuge") {
                HStack(spacing: 6) {
                    chip("Bildschirmfoto") {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
                                                           configuration: NSWorkspace.OpenConfiguration())
                    }
                    chip(speedLabel) { model.activity.speed.start() }
                        .disabled(model.activity.speed.state == .running)
                }
                if case .done(let r) = model.activity.speed.state {
                    Text(verbatim: "↓ \(SpeedTest.mbpsText(r.downMbps)) · ↑ \(SpeedTest.mbpsText(r.upMbps)) Mbit/s"
                         + (r.latencyMs.map { " · \(Int($0.rounded())) ms" } ?? ""))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(FamilyTheme.textSecondary)
                } else if case .failed(let why) = model.activity.speed.state {
                    Text(verbatim: why).font(.system(size: 12)).foregroundStyle(FamilyTheme.warning)
                }
            }
            status
        }
    }

    private var speedLabel: String { model.activity.speed.state == .running ? "Misst …" : "Geschwindigkeitstest" }

    /// Was die Insel sonst noch weiß: nur, was da ist.
    @ViewBuilder private var status: some View {
        let a = model.activity
        let lines: [(String, String)] = [
            a.weather.map { ("cloud.sun", "Wetter \(WeatherBig.deg($0.temperature))") },
            a.shelfItems.isEmpty ? nil : ("tray.full", "\(a.shelfItems.count) in der Ablage"),
            a.upcomingEvent.map { ("calendar", "Nächster Termin: \($0.title)") },
            a.showsBattery ? a.battery.status.map { ($0.symbol, "Batterie \($0.text)") } : nil,
        ].compactMap { $0 }
        if !lines.isEmpty {
            card("Status") {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Label { Text(verbatim: l.1).lineLimit(1) } icon: { Image(systemName: l.0) }
                        .font(.system(size: 12)).foregroundStyle(FamilyTheme.textSecondary)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(FamilyTheme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(FamilyTheme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FamilyTheme.cardStroke.opacity(0.6), lineWidth: 0.5))
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
