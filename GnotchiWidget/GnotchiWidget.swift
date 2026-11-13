import AppIntents
import OSLog
import SwiftUI
import WidgetKit

// Schreibtisch-Widget „Gnotchi“ (0.26.0, docs/SECURE-DESIGN.md G49). Sandbox, nur die App-Gruppe.
// Liest, was Gnotchi in den Gruppen-Ordner legt (WidgetWire, mit Obergrenzen), und zeigt es nur an (G5:
// `Text(verbatim:)`). Darstellung gedämpft/farbig übernimmt macOS – genau dafür ist es ein echtes Widget.

/// Nur Fehler beim Lesen, nie Inhalte (G8). Stufe `notice`: `info` speichert macOS für eigene Apps nicht (13.11.).
let widgetLog = Logger(subsystem: "dev.mwlr.gnotchi", category: "widget")

struct MusicEntry: TimelineEntry {
    let date: Date
    let now: WidgetWire.Now?
    let cover: CGImage?

    static let empty = MusicEntry(date: Date(), now: nil, cover: nil)
}

struct MusicProvider: TimelineProvider {
    func load() -> MusicEntry {
        guard let dir = WidgetWire.container() else {
            widgetLog.notice("Widget gelesen: kein Gruppen-Ordner")
            return .empty
        }
        let url = dir.appendingPathComponent(WidgetWire.nowFile)
        // Keine Datei = nichts läuft (normal, kein Protokoll).
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let data = WidgetWire.read(url, limit: WidgetWire.maxJSON) else {
            // Messpunkt: Fehlercode beim Öffnen (nur Zahl/Domäne, kein Pfad).
            var code = "?"
            do { _ = try FileHandle(forReadingFrom: url) } catch let e as NSError { code = "\(e.domain) \(e.code)" }
            widgetLog.notice("Widget gelesen: Datei nicht lesbar (\(code, privacy: .public))")
            return .empty
        }
        guard let now = WidgetWire.decodeNow(data) else {
            widgetLog.notice("Widget gelesen: Format abgelehnt (\(data.count, privacy: .public) Bytes)")
            return .empty
        }
        var cover: CGImage?
        if now.hasCover, let png = WidgetWire.read(dir.appendingPathComponent(WidgetWire.coverFile),
                                                   limit: WidgetWire.maxCover) {
            cover = WidgetWire.coverImage(png)
        } else if now.hasCover {
            let curl = dir.appendingPathComponent(WidgetWire.coverFile)
            var code = "?"
            do { _ = try FileHandle(forReadingFrom: curl) } catch let e as NSError { code = "\(e.domain) \(e.code)" }
            widgetLog.notice("Widget gelesen: Cover nicht lesbar (\(code, privacy: .public))")
        }
        return MusicEntry(date: Date(), now: now, cover: cover)
    }

    func placeholder(in context: Context) -> MusicEntry {
        MusicEntry(date: Date(), now: WidgetWire.Now(title: "Titel", subtitle: "Interpret · Album", playing: true,
                                                     hasCover: false), cover: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        // Kein Zeitplan: Gnotchi bittet bei jedem Wechsel ums Neuzeichnen.
        completion(Timeline(entries: [load()], policy: .never))
    }
}

/// Knopf im Widget. Legt nur einen Befehl in den Gruppen-Ordner und weckt Gnotchi; Gnotchi prüft und führt aus (G13).
/// Nicht in Kurzbefehlen sichtbar (`isDiscoverable = false`), sonst könnte jeder Kurzbefehl die Wiedergabe steuern.
struct MediaCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Wiedergabe steuern"
    static let isDiscoverable = false

    @Parameter(title: "Aktion") var action: String

    init() {}
    init(_ action: WidgetWire.Action) { self.action = action.rawValue }

    func perform() async throws -> some IntentResult {
        guard let parsed = WidgetWire.Action(rawValue: action), let dir = WidgetWire.container() else { return .result() }
        let cmd = WidgetWire.Command(id: UUID(), action: parsed, at: Date().timeIntervalSince1970)
        try JSONEncoder().encode(cmd).write(to: dir.appendingPathComponent(WidgetWire.commandFile), options: .atomic)
        WidgetWire.postCommandNote()
        return .result()
    }
}

struct MusicWidgetView: View {
    let entry: MusicEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let now = entry.now {
                switch family {
                case .systemMedium: medium(now)
                case .systemLarge: large(now)
                default: small(now)
                }
            } else {
                empty
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func small(_ now: WidgetWire.Now) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cover(now)
            texts(now, titleSize: 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ now: WidgetWire.Now) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Feste Kante = volle Höhe; ohne sie fiel das Cover im HStack auf Breite 0 (gesehen 13.11.).
            GeometryReader { proxy in cover(now).frame(width: proxy.size.height, height: proxy.size.height) }
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                texts(now, titleSize: 14)
                Spacer(minLength: 0)
                buttons(now, size: 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func large(_ now: WidgetWire.Now) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cover(now)
            texts(now, titleSize: 16)
            buttons(now, size: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func cover(_ now: WidgetWire.Now) -> some View {
        Group {
            if let cover = entry.cover {
                // Gedämpft zeichnet macOS im Modus „accented“ (gemessen 13.11., nicht „vibrant“ wie in Apples Tabelle):
                // ohne diesen Schalter würde ein Bild zur einfarbigen Fläche, so bleibt es ein entsättigtes Foto.
                Image(decorative: cover, scale: 1).resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.fill.tertiary)
                    Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(now.playing ? 1 : 0.6)
        // Klein/Groß: Cover mittig (Michael 13.11.); Mittel: links neben dem Text.
        .frame(maxWidth: family == .systemMedium ? nil : .infinity, alignment: .center)
        .layoutPriority(-1)
    }

    private func texts(_ now: WidgetWire.Now, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: now.title).font(.system(size: titleSize, weight: .semibold)).lineLimit(1)
            if !now.subtitle.isEmpty {
                Text(verbatim: now.subtitle).font(.system(size: titleSize - 2)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func buttons(_ now: WidgetWire.Now, size: CGFloat) -> some View {
        HStack(spacing: size * 1.4) {
            Button(intent: MediaCommandIntent(.previous)) { Image(systemName: "backward.fill") }
                .accessibilityLabel(Text("Zurück"))
            Button(intent: MediaCommandIntent(.playPause)) { Image(systemName: now.playing ? "pause.fill" : "play.fill") }
                .accessibilityLabel(Text(now.playing ? "Pause" : "Wiedergabe"))
            Button(intent: MediaCommandIntent(.next)) { Image(systemName: "forward.fill") }
                .accessibilityLabel(Text("Weiter"))
        }
        .buttonStyle(.plain)
        .font(.system(size: size, weight: .semibold))
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("Keine Wiedergabe").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main
struct GnotchiMusicWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWire.kind, provider: MusicProvider()) { MusicWidgetView(entry: $0) }
            .configurationDisplayName("Musik")
            .description("Was gerade läuft, mit Cover. Daten von Gnotchi.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
