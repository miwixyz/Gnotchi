import AppKit

/// Ablauf „Aus PastePal importieren …“ (G41): Datei wählen → Vorschau mit Zahlen und Tresor-Auswahl → ggf. einmal
/// Touch ID → alles oder nichts → Exportdatei in den Papierkorb. Ergebnis als Satz für die Einstellungen.
extension ClipboardLink {
    func importPastePal(done: @escaping @MainActor (String) -> Void) {
        guard let store else { return done(String(localized: "Erst die Zwischenablage einschalten.")) }
        let open = NSOpenPanel()
        open.allowedContentTypes = [.json]
        open.allowsMultipleSelection = false
        open.message = String(localized: "PastePal-Export wählen (PastePal → Einstellungen → Exportieren)")
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= PastePalImport.maxFileBytes, let data = try? Data(contentsOf: url),
              let plan = try? PastePalImport.plan(from: data) else {
            return done(String(localized: "Die Datei ist kein lesbarer PastePal-Export."))
        }
        guard let vaultIDs = Self.askVault(plan) else { return }

        let finish: @MainActor (SymmetricKeyProvider?) -> Void = { key in
            do {
                let count = try PastePalImport.run(plan, vaultIDs: vaultIDs, store: store, vaultKey: key)
                NSWorkspace.shared.recycle([url]) { _, error in
                    Task { @MainActor in
                        done(error == nil
                             ? String(localized: "\(count) Einträge übernommen. Die Exportdatei liegt im Papierkorb – leere ihn, sie enthält alles im Klartext.")
                             : String(localized: "\(count) Einträge übernommen. Die Exportdatei konnte nicht in den Papierkorb – bitte selbst löschen, sie enthält alles im Klartext."))
                    }
                }
            } catch {
                done(String(localized: "Import abgebrochen, nichts übernommen."))
            }
        }
        if vaultIDs.isEmpty {
            finish(nil)
        } else {
            unlockVault { key in
                guard let key else { return done(String(localized: "Tresor nicht entsperrt, nichts übernommen.")) }
                finish(SymmetricKeyProvider(key: key))
            }
        }
    }

    /// Vorschau: Sammlungen mit Anzahl, je ein Häkchen „Tresor“. Vorschlag bei Namen wie „Keys“, „Passwort“, „Token“.
    /// Inhalte erscheinen nie. Rückgabe nil = abgebrochen.
    private static func askVault(_ plan: PastePalImport.Plan) -> Set<String>? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Aus PastePal importieren")
        let total = plan.collections.reduce(0) { $0 + $1.items.count }
        alert.informativeText = String(localized: "\(plan.collections.count) Sammlungen mit \(total) Einträgen. Formatierungen kommen nicht mit, PastePal exportiert nur reinen Text. Haken = in den Tresor (nur mit Touch ID lesbar).")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        var boxes: [(String, NSButton)] = []
        for c in plan.collections {
            let box = NSButton(checkboxWithTitle: "\(c.name) (\(c.items.count)) – Tresor", target: nil, action: nil)
            let lower = c.name.lowercased()
            box.state = ["key", "schlüssel", "passw", "token", "secret", "api"].contains(where: lower.contains) ? .on : .off
            stack.addArrangedSubview(box)
            boxes.append((c.id, box))
        }
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: CGFloat(boxes.count) * 24)
        alert.accessoryView = stack
        alert.addButton(withTitle: String(localized: "Importieren"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Set(boxes.filter { $0.1.state == .on }.map(\.0))
    }
}
