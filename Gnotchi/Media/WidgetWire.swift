import Foundation
import ImageIO

/// Gemeinsames Format zwischen Gnotchi und dem Schreibtisch-Widget (0.26.0, docs/SECURE-DESIGN.md G49).
/// Dieselbe Datei in App und Widget-Erweiterung, damit Schreiben und Prüfen nie auseinanderlaufen.
///
/// Weg: Gnotchi schreibt den **aktuellen** Titel (kein Verlauf) und ein schon verkleinertes Cover in den Ordner der
/// App-Gruppe und bittet WidgetKit ums Neuzeichnen. Das Widget liest beides mit Obergrenzen und zeigt es nur an (G5).
/// Knöpfe: Das Widget legt einen Befehl in denselben Ordner und weckt Gnotchi per Darwin-Mitteilung. Die Mitteilung ist
/// nur ein Weckruf – ausgeführt wird nur ein frischer, noch nicht ausgeführter Befehl aus dem Ordner, in den nur Programme
/// mit Michaels Team-Signatur schreiben (macOS-Schutz der Gruppen-Ordner, gemessen 13.11.). So bleibt G13.
enum WidgetWire {
    static let group = "LTKJ6Z2VYB.dev.mwlr.gnotchi"
    static let kind = "dev.mwlr.gnotchi.music"
    static let commandNote = "LTKJ6Z2VYB.dev.mwlr.gnotchi.widget-command"
    static let nowFile = "widget-now.json"
    static let coverFile = "widget-cover.png"
    static let commandFile = "widget-command.json"

    static let maxJSON = 16 * 1024
    static let maxCommand = 1024
    static let maxCover = 512 * 1024
    static let maxCoverSide = 512
    static let maxText = 300
    /// Älter als das → verworfen (verhindert, dass ein liegengebliebener Befehl später noch einmal ausgelöst wird).
    static let commandMaxAge: TimeInterval = 3

    struct Now: Codable, Equatable {
        var v = 1
        var title: String
        /// „Interpret · Album“, fertig zusammengesetzt.
        var subtitle: String
        var playing: Bool
        var hasCover: Bool
    }

    enum Action: String, Codable, CaseIterable, Sendable { case previous, playPause, next }

    struct Command: Codable, Equatable {
        var v = 1
        var id: UUID
        var action: Action
        /// Sekunden seit 1970.
        var at: Double
    }

    static func container() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func clip(_ s: String) -> String { String(s.prefix(maxText)) }

    static func decodeNow(_ data: Data) -> Now? {
        guard data.count <= maxJSON, let n = try? JSONDecoder().decode(Now.self, from: data), n.v == 1 else { return nil }
        return Now(title: clip(n.title), subtitle: clip(n.subtitle), playing: n.playing, hasCover: n.hasCover)
    }

    static func decodeCommand(_ data: Data, now: Date) -> Command? {
        guard data.count <= maxCommand, let c = try? JSONDecoder().decode(Command.self, from: data), c.v == 1,
              c.at.isFinite else { return nil }
        let age = now.timeIntervalSince1970 - c.at
        guard age >= -1, age <= commandMaxAge else { return nil }
        return c
    }

    /// Datei lesen, nie mehr als `limit` Bytes; größer → nil.
    static func read(_ url: URL, limit: Int) -> Data? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: limit + 1), d.count <= limit else { return nil }
        return d
    }

    /// Cover nur als PNG bis `maxCoverSide` je Seite, Kopf **vor** dem Dekodieren geprüft (wie G6).
    static func coverImage(_ data: Data) -> CGImage? {
        guard data.count <= maxCover,
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(src) as String? == "public.png",
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= maxCoverSide, h <= maxCoverSide else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func postCommandNote() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(commandNote as CFString), nil, nil, true)
    }
}
