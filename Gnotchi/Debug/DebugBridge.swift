#if DEBUG
import AppKit
import OSLog
import ScreenCaptureKit
import Security

/// Ein Befehl an die Bild-Testkopie (G45). Feste Liste, alles andere ist ungültig.
struct DebugCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Version, Kennung, Freigabe, offene Fenster.
        case status
        /// Bild eines eigenen Fensters (nur Einstellungen und Hilfe – nie Insel, Zwischenablage, Ablage).
        case snapshot(window: String)
        /// Hell, dunkel oder wie das System.
        case appearance(String)
    }

    let id: String
    let kind: Kind

    /// Fenster, von denen ein Bild erlaubt ist. Insel und Panels zeigen echte Inhalte (G16, G40) und fehlen bewusst.
    nonisolated static let snapshotWindows: Set<String> = [AppModel.WindowID.settings, AppModel.WindowID.help]
    nonisolated static let appearances: Set<String> = ["light", "dark", "system"]

    /// Kennung des Steuerprogramms `gnotchictl` (Developer ID, Team LTKJ6Z2VYB) – nur es darf Befehle schicken.
    nonisolated static let ctlRequirement = LiveText.peerRequirement(identifier: "dev.mwlr.gnotchi.ctl")

    /// `{"v":1,"id":"…","cmd":"status"|"snapshot"|"appearance", …}`; `id` 1–32 Zeichen a–z, A–Z, 0–9 (wird Dateiname).
    nonisolated static func parse(_ payload: Data) -> DebugCommand? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.doubleValue == 1,
              let id = obj["id"] as? String, (1...32).contains(id.count),
              id.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }),
              let cmd = obj["cmd"] as? String else { return nil }
        switch cmd {
        case "status":
            return DebugCommand(id: id, kind: .status)
        case "snapshot":
            guard let w = obj["window"] as? String, snapshotWindows.contains(w) else { return nil }
            return DebugCommand(id: id, kind: .snapshot(window: w))
        case "appearance":
            guard let m = obj["mode"] as? String, appearances.contains(m) else { return nil }
            return DebugCommand(id: id, kind: .appearance(m))
        default:
            return nil
        }
    }
}

/// Befehlskanal der Bild-Testkopie (G45), nur Debug-Build und nur mit Kennung `dev.mwlr.gnotchi.bild`.
/// Befehle kommen über `debug.sock` (PeerSocketServer: Audit-Token gegen `ctlRequirement` vor dem ersten Byte),
/// Antworten liegen als `Antworten/<id>.json`, Bilder als `Bilder/<id>-<fenster>.png` im eigenen Datenordner (0700).
@MainActor
final class DebugBridge {
    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "debug")
    private static var current: DebugBridge?

    private weak var model: AppModel?
    private let directory: URL
    private var server: PeerSocketServer<DebugCommand>?

    private init(model: AppModel, directory: URL) {
        self.model = model
        self.directory = directory
    }

    static func start(model: AppModel) {
        guard AppDirectory.isBildCopy, current == nil, let dir = LiveTextLink.directory,
              PeerSocketServer<DebugCommand>.prepareDirectory(dir) else { return log.error("Befehlskanal aus: Ordner") }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(DebugCommand.ctlRequirement as CFString, [], &req) == errSecSuccess,
              let req else { return log.error("Befehlskanal aus: Anforderung ungültig") }
        let bridge = DebugBridge(model: model, directory: dir)
        let s = PeerSocketServer<DebugCommand>(
            directory: dir, fileName: "debug.sock", label: "Befehlskanal", peer: "gnotchictl", requirement: req,
            coalesce: false, parse: { DebugCommand.parse($0) },
            onValue: { command in
                guard let command else { return }
                Task { @MainActor in await bridge.handle(command) }
            })
        do {
            try s.start()
            bridge.server = s
            current = bridge
            log.notice("Befehlskanal bereit")
        } catch {
            log.error("Befehlskanal aus: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ command: DebugCommand) async {
        var answer: [String: Any] = ["v": 1, "id": command.id]
        switch command.kind {
        case .status:
            answer["status"] = status()
        case .appearance(let mode):
            NSApp.appearance = switch mode {
            case "light": NSAppearance(named: .aqua)
            case "dark": NSAppearance(named: .darkAqua)
            default: nil
            }
            answer["ok"] = true
        case .snapshot(let window):
            let result = await snapshot(window: window, id: command.id)
            answer.merge(result) { $1 }
        }
        write(answer, id: command.id)
    }

    private func status() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let windows = NSApp.windows.filter(\.isVisible).compactMap { w -> [String: Any]? in
            guard let id = w.identifier?.rawValue else { return nil }
            return ["id": id, "breite": Int(w.frame.width), "hoehe": Int(w.frame.height)]
        }
        return ["version": info["CFBundleShortVersionString"] as? String ?? "?",
                "kennung": Bundle.main.bundleIdentifier ?? "?",
                "bildschirmaufnahme": CGPreflightScreenCaptureAccess(),
                "darstellung": NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light",
                "fenster": windows]
    }

    /// Öffnet das Fenster (falls zu), wartet kurz und nimmt NUR dieses eigene Fenster per ScreenCaptureKit auf.
    private func snapshot(window id: String, id answerID: String) async -> [String: Any] {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return ["ok": false, "fehler": "Bildschirmaufnahme nicht freigegeben – in den Systemeinstellungen erlauben, App neu starten"]
        }
        model?.showWindow(id)
        try? await Task.sleep(for: .milliseconds(900))
        guard let win = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix(id) == true }) else {
            return ["ok": false, "fehler": "Fenster nicht offen"]
        }
        let windowID = CGWindowID(win.windowNumber)
        let scale = win.backingScaleFactor
        let size = win.frame.size
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return ["ok": false, "fehler": "Fenster nicht in ScreenCaptureKit"]
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: config)
            let folder = directory.appendingPathComponent("Bilder", isDirectory: true)
            guard PeerSocketServer<DebugCommand>.prepareDirectory(folder),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                return ["ok": false, "fehler": "Bild nicht gespeichert"]
            }
            let file = folder.appendingPathComponent("\(answerID)-\(id).png")
            try png.write(to: file, options: .atomic)
            return ["ok": true, "datei": file.path, "breite": image.width, "hoehe": image.height]
        } catch {
            return ["ok": false, "fehler": "Aufnahme: \(error.localizedDescription)"]
        }
    }

    private func write(_ answer: [String: Any], id: String) {
        let folder = directory.appendingPathComponent("Antworten", isDirectory: true)
        guard PeerSocketServer<DebugCommand>.prepareDirectory(folder),
              let data = try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]) else {
            return Self.log.error("Antwort nicht geschrieben")
        }
        do {
            try data.write(to: folder.appendingPathComponent("\(id).json"), options: .atomic)
        } catch {
            Self.log.error("Antwort nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
        Self.log.notice("Befehl ausgeführt")
    }
}
#endif
