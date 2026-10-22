import AppKit
import UniformTypeIdentifiers

/// App-Auswahl für „Mitteilungen in der Notch“ (0.6.0, G29). Gespeichert werden nur Kennungen (Preferences, wie G25);
/// Namen und Symbole kommen aus dem lokalen App-Bundle.
@MainActor
enum NotifyApps {

    /// Bekannte Apps, die in der Liste stehen, sofern installiert.
    nonisolated static let known = [
        "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop",
        "com.tinyspeck.slackmacgap", "org.whispersystems.signal-desktop", "com.apple.mail", "com.microsoft.Outlook",
        "com.microsoft.teams2", "com.hnc.Discord", "com.apple.reminders", "com.apple.iCal", "com.apple.FaceTime",
    ]

    /// Beim ersten Einschalten angehakt (Spec: Nachrichten, WhatsApp, Telegram, Slack, Mail; dazu Signal).
    nonisolated static let suggested: Set<String> = [
        "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop",
        "com.tinyspeck.slackmacgap", "org.whispersystems.signal-desktop", "com.apple.mail",
    ]

    static func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static var suggestedInstalled: [String] {
        known.filter { suggested.contains($0) && isInstalled($0) }
    }

    /// Installierte bekannte Apps, dann von Hand hinzugefügte (auch wenn deinstalliert – sonst ließen sie sich nicht
    /// mehr abwählen).
    static func list(selected: [String]) -> [(id: String, name: String)] {
        let ids = known.filter(isInstalled) + selected.filter { !known.contains($0) }
        return ids.map { ($0, AppIcons.name(for: $0) ?? $0) }
    }

    /// „App hinzufügen …“: nur eine `.app` auswählen, nur deren Kennung übernehmen.
    static func pickApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Hinzufügen"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              Preferences.isValidBundleID(id) else { return nil }
        return id
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
