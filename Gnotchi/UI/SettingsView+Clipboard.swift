import AppKit
import SwiftUI

/// Reiter „Zwischenablage“ (0.11.0, G37–G41). Ab Werk aus.
extension SettingsView {
    @ViewBuilder var clipboardTab: some View {
        @Bindable var prefs = prefs
        let link = model.activity.clipboard
        card("Zwischenablage") {
            toggleRow("Verlauf der Zwischenablage", isOn: $prefs.clipboard)
                .onChange(of: prefs.clipboard) { model.applyNotchSetting() }
            if !prefs.clipboard {
                note("Gnotchi merkt sich, was du kopierst – verschlüsselt, 30 Tage, höchstens 1 000 Einträge; Angeheftetes "
                     + "und Sammlungen bleiben. Kopien aus Passwort-Apps nie. Einfügen machst du selbst mit ⌘V.",
                     symbol: "info.circle", color: FamilyTheme.textSecondary)
            } else {
                if let problem = link?.startProblem {
                    note(problem, symbol: "exclamationmark.triangle", color: .orange)
                }
                if NSPasteboard.general.accessBehavior == .alwaysDeny {
                    note("macOS verbietet Gnotchi das Lesen der Zwischenablage. Erlauben: Systemeinstellungen → Datenschutz & "
                         + "Sicherheit → Aus anderen Apps einfügen.", symbol: "hand.raised", color: .orange)
                }
                row("Seitenansicht öffnen") {
                    HotKeyRecorder(hotKey: $prefs.clipboardPanelHotKey)
                        .onChange(of: prefs.clipboardPanelHotKey) { model.applyNotchSetting() }
                }
                row("Seitenansicht am Rand") {
                    Picker("", selection: $prefs.clipboardPanelEdge) {
                        Text("Rechts").tag(Preferences.PanelEdge.right)
                        Text("Links").tag(Preferences.PanelEdge.left)
                        Text("Unten").tag(Preferences.PanelEdge.bottom)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 200)
                }
                row("Mitlesen") {
                    if prefs.isClipboardPaused {
                        Button("Fortsetzen") { link?.resume() }
                    } else {
                        Button("30 Min. pausieren") { link?.pause() }
                    }
                }
                note("Reagiert das Kürzel nicht, belegt es eine andere App (z. B. PastePal) – dann ein anderes wählen.",
                     symbol: "keyboard", color: FamilyTheme.textSecondary)
            }
        }
        if prefs.clipboard {
            ClipboardExclusions()
            ClipboardDataCard(link: link)
        }
    }
}

/// Ausgeschlossene Apps (nur Kennungen, G37).
private struct ClipboardExclusions: View {
    @Environment(Preferences.self) var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
            Text("Nie aus diesen Apps").font(FamilyTheme.font(.headline))
            ForEach(prefs.clipboardExcluded, id: \.self) { id in
                HStack {
                    AppSymbol(bundleID: id, size: 18)
                    Text(verbatim: AppIcons.name(for: id) ?? id).lineLimit(1)
                    Spacer()
                    Button { prefs.setClipboardExcluded(id, false) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("App hinzufügen …") { addApp() }
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }

    private func addApp() {
        let open = NSOpenPanel()
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.allowedContentTypes = [.application]
        open.allowsMultipleSelection = true
        guard open.runModal() == .OK else { return }
        for url in open.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { prefs.setClipboardExcluded(id, true) }
        }
    }
}

/// Import, Löschen, Zurücksetzen.
private struct ClipboardDataCard: View {
    let link: ClipboardLink?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
            Text("Daten").font(FamilyTheme.font(.headline))
            HStack {
                Button("Aus PastePal importieren …") { link?.importPastePal { message = $0 } }
                Spacer()
            }
            HStack {
                Button("Verlauf löschen …") {
                    if ClipboardPrompts.confirm(title: "Verlauf löschen?",
                                                message: "Angeheftetes, Sammlungen und Tresor bleiben.") {
                        link?.clearHistory()
                        message = "Verlauf gelöscht."
                    }
                }
                Button("Alles zurücksetzen …", role: .destructive) {
                    if ClipboardPrompts.confirm(title: "Zwischenablage zurücksetzen?",
                                                message: "Verlauf, Sammlungen und Tresor werden gelöscht, die Schlüssel auch – "
                                                + "danach ist nichts mehr lesbar, auch nicht in Sicherungen.") {
                        link?.resetEverything()
                    }
                }
            }
            if let message {
                Text(verbatim: message).font(FamilyTheme.font(.callout)).foregroundStyle(FamilyTheme.textSecondary)
            }
        }
        .padding(FamilyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .familyCard(radius: FamilyTheme.Radius.tile)
    }
}

/// Tastenkürzel aufnehmen: Klick, dann Kombination drücken (Esc bricht ab, ⌫ entfernt). Nur mit Modifikator.
/// Speichert den gedrückten Tastencode (24.10.: „<“ ist auf deutscher ISO-Tastatur Code 50, nicht 10).
struct HotKeyRecorder: View {
    @Binding var hotKey: Preferences.HotKey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(verbatim: recording ? String(localized: "Kombination drücken …")
                 : hotKey.map(HotKeyCenter.display) ?? String(localized: "Kein Kürzel"))
                .frame(minWidth: 120)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = HotKeyCenter.carbonModifiers(event.modifierFlags)
            switch event.keyCode {
            case 53: stop()                                   // Esc
            case 51 where mods == 0: hotKey = nil; stop()     // ⌫
            default:
                guard let key = Preferences.HotKey(stored: ["key": Int(event.keyCode), "mods": Int(mods)]) else {
                    return nil   // ohne Modifikator: ignorieren, weiter aufnehmen
                }
                hotKey = key
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
