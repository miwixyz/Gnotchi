import AppKit
import ApplicationServices

/// Liest den Inhalt eines Banners (0.6.0, G28/G29) – nur lesen. Gemessen 22.10. (macOS 27.0.1): App-Name = erster
/// Teil der Beschreibung, Texte als `AXStaticText` mit Kennung `title`/`header`/`subtitle`/`body`/`summary-text`,
/// Knöpfe als benannte Aktionen; beim Anruf `AvatarView` (Anrufart), Anrufer-Element und echte `AXButton`.
@MainActor
final class BannerReader {

    private var nameCache: [String: String?] = [:]

    func note(id: String, _ banner: AXUIElement) -> NotifyWire.Note? {
        // Beschreibung „App, Titel, …“: der erste Teil ist der App-Name (gemessen: „Skripteditor“, „Erinnerungen“).
        let app = AXQuery.firstPart(AXQuery.string(banner, kAXDescriptionAttribute))
        guard !app.isEmpty else { return nil }
        var texts: [String: String] = [:]
        var stack = AXQuery.children(banner)
        var nodes = 0
        while let e = stack.popLast(), nodes < 60 {
            nodes += 1
            let key = AXQuery.string(e, kAXIdentifierAttribute)
            if ["title", "header", "subtitle", "body", "summary-text"].contains(key), texts[key] == nil {
                texts[key] = AXQuery.string(e, kAXValueAttribute)
            }
            stack.append(contentsOf: AXQuery.children(e))
        }
        let title = texts["title"] ?? texts["header"] ?? ""
        let body = texts["body"] ?? texts["summary-text"] ?? ""
        return NotifyWire.Note(
            id: id, kind: .note, app: NotifyWire.clean(app, max: NotifyWire.maxApp), bundle: bundleID(forAppNamed: app),
            title: NotifyWire.clean(title, max: NotifyWire.maxTitle),
            subtitle: NotifyWire.clean(texts["subtitle"] ?? "", max: NotifyWire.maxTitle),
            body: NotifyWire.clean(body, max: NotifyWire.maxBody),
            actions: NotifyWire.offeredActions(AXQuery.actions(banner).map(\.name)))
    }

    /// Anruf (gemessen 22.10.): `AvatarView` mit der Anrufart als Beschreibung, daneben ein Element mit dem Anrufer,
    /// dazu echte Knöpfe. Angeboten werden nur Annehmen, Ablehnen und (im Gespräch) Beenden.
    func call(id: String, _ banner: AXUIElement) -> NotifyWire.Note? {
        var kindLabel = ""
        var caller = ""
        var buttons: [String] = []
        var stack = AXQuery.children(banner)
        var nodes = 0
        while let e = stack.popLast(), nodes < 80 {
            nodes += 1
            let role = AXQuery.string(e, kAXRoleAttribute)
            let desc = AXQuery.string(e, kAXDescriptionAttribute)
            if AXQuery.string(e, kAXIdentifierAttribute) == "AvatarView" {
                kindLabel = AXQuery.firstPart(desc)
            } else if role == "AXGenericElement", caller.isEmpty, !desc.isEmpty {
                caller = AXQuery.firstPart(desc)
            } else if role == kAXButtonRole as String, NotifyWire.callActions.contains(desc) {
                buttons.append(desc)
            }
            stack.insert(contentsOf: AXQuery.children(e), at: 0)   // Reihenfolge wie auf dem Bildschirm
        }
        // Ohne Anrufart-Symbol ist es kein Anruf-Banner (Review 22.10.: nicht nur auf die Kennung verlassen).
        guard !buttons.isEmpty, !kindLabel.isEmpty else { return nil }
        // Annehmen vor Ablehnen, egal in welcher Reihenfolge macOS sie liefert.
        let ordered = buttons.sorted { NotifyWire.acceptActions.contains($0) && !NotifyWire.acceptActions.contains($1) }
        return NotifyWire.Note(
            id: id, kind: .call, app: NotifyWire.clean(kindLabel.isEmpty ? "Anruf" : kindLabel, max: NotifyWire.maxApp),
            bundle: nil, title: NotifyWire.clean(caller, max: NotifyWire.maxTitle), subtitle: "", body: "",
            actions: ordered)
    }

    /// App-Name aus dem Banner → Kennung. Nur bei **eindeutiger** Zuordnung: Zwei laufende Apps gleichen Namens
    /// (z. B. eine App, die sich „WhatsApp“ nennt) → keine Kennung → nicht angezeigt (G29).
    private func bundleID(forAppNamed name: String) -> String? {
        let key = name.lowercased()
        if let hit = nameCache[key] { return hit }
        let running = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.lowercased() == key }
            .compactMap(\.bundleIdentifier)
        var result: String?
        if Set(running).count == 1 {
            result = running[0]
        } else if running.isEmpty {
            let hits = installedApps()[key] ?? []
            result = hits.count == 1 ? hits.first : nil
        }
        if nameCache.count > 64 { nameCache = [:] }
        nameCache[key] = result
        return result
    }

    private var installed: (map: [String: Set<String>], at: Date)?

    /// Angezeigter (lokalisierter) Name → Kennungen aller installierten Apps. Banner nennen den lokalisierten Namen
    /// („Skripteditor“), die Datei heißt anders („Script Editor.app“). Höchstens alle 5 Minuten neu eingelesen.
    private func installedApps() -> [String: Set<String>] {
        if let installed, Date().timeIntervalSince(installed.at) < 300 { return installed.map }
        var map: [String: Set<String>] = [:]
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
                    "/System/Applications/Utilities"]
        for dir in dirs {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                let path = dir + "/" + entry
                guard let id = Bundle(path: path)?.bundleIdentifier else { continue }
                let shown = FileManager.default.displayName(atPath: path)
                for n in Set([shown, String(entry.dropLast(4))]) {
                    let k = (n.hasSuffix(".app") ? String(n.dropLast(4)) : n).lowercased()
                    map[k, default: []].insert(id)
                }
            }
        }
        installed = (map, Date())
        return map
    }
}
