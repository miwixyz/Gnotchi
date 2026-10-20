import Foundation
import OSLog
import Security

/// Tippis Live-Text in der Insel (0.3.0, SECURE-DESIGN G21): betreibt `LiveTextServer` im Ordner
/// `~/Library/Application Support/Gnotchi`, solange „Tippi-Aufnahme anzeigen“ an ist. Scheitert der Start
/// (fremde Datei am Pfad, Ordner nicht unserer), bleibt die Funktion aus – Tippi zeigt dann seine Pille.
@MainActor
final class LiveTextLink: NotchPart {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "livetext")

    private let activity: ActivityModel
    private var server: LiveTextServer?

    init(activity: ActivityModel) {
        self.activity = activity
    }

    nonisolated static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Gnotchi", isDirectory: true)
    }

    func start() {
        guard server == nil, let dir = Self.directory else { return }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(LiveText.tippiRequirement as CFString, [], &req) == errSecSuccess,
              let req else { return Self.log.error("Live-Text: Anforderung ungültig") }
        let s = LiveTextServer(directory: dir, requirement: req) { [weak self] text in
            Task { @MainActor in self?.activity.setLiveText(text) }
        }
        do {
            try s.start()
            server = s
        } catch {
            Self.log.error("Live-Text aus: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        activity.setLiveText(nil)
    }
}
