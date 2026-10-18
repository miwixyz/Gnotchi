import Foundation

/// Bereinigter Wiedergabe-Zustand aus einer Adapter-Zeile (G4). Alles, was hier
/// ankommt, kann eine beliebige Website gesetzt haben – deshalb gekürzt und ohne
/// Steuer- und Richtungszeichen.
struct NowPlayingInfo: Equatable, Sendable {
    let title: String
    let artist: String?
    let album: String?
    /// App für Symbol/Name. Safari meldet den WebKit-Hilfsprozess → Eltern-App (Mitschnitt 18.10.).
    let appBundleID: String?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedAtStamp: TimeInterval
    let stamp: Date
    let rate: Double
    let contentID: String?
    /// Base64, noch nicht dekodiert (Artwork.decode begrenzt Größe und Typ).
    let artworkBase64: String?

    static let maxTextLength = 300
    /// Harte Obergrenze in UTF-8-Bytes: `prefix(300)` zählt Grapheme, ein Zalgo-Zeichen kann Megabytes haben.
    static let maxTextBytes = 1200
    /// So viele Skalare werden überhaupt angesehen, bevor gefiltert wird.
    static let maxScalarsScanned = 2000
    /// Mehr kombinierende Zeichen in Folge werden verworfen (Zalgo).
    static let maxCombiningRun = 4
    /// Wie viele ZWJ/ZWNJ je Feld bleiben (eine Familien-Emoji-Sequenz braucht 3).
    static let maxJoiners = 8
    /// Längere Dauern sind unglaubwürdig (und würden die Anzeige sprengen).
    static let maxDuration: TimeInterval = 48 * 3600
    static let maxArtworkBase64Bytes = 2 * 1024 * 1024

    /// Browser liefern zuerst Titel ohne Interpret/Dauer (Mitschnitt 18.10.).
    var isIncomplete: Bool { artist == nil || duration == nil }

    /// Hochgerechnete Position. Gilt auch für Werte aus dem AppleScript-Fallback (memberwise init),
    /// deshalb hier abgesichert: immer endlich, ≥ 0, höchstens Dauer bzw. `maxDuration`.
    func elapsed(at now: Date) -> TimeInterval {
        let base = elapsedAtStamp.isFinite ? elapsedAtStamp : 0
        let usedRate = rate.isFinite ? min(max(rate, 0), 16) : 0
        let dt = now.timeIntervalSince(stamp)
        // Ein Zeitstempel in der Zukunft darf die Position nicht zurücklaufen lassen.
        let run = isPlaying && dt.isFinite ? max(0, dt) * usedRate : 0
        let cap = duration.map { $0.isFinite ? max(0, min($0, Self.maxDuration)) : 0 } ?? Self.maxDuration
        return max(0, min(base + run, cap))
    }

    private struct Envelope: Decodable { let payload: Payload? }
    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let playing: Bool?
        let playbackRate: Double?
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let timestampEpochMicros: Double?
        let contentItemIdentifier: String?
        let artworkData: String?
    }

    static func parse(line: Data) -> NowPlayingInfo? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: line),
              let p = env.payload, let title = sanitize(p.title) else { return nil }
        let playing = p.playing ?? false
        return NowPlayingInfo(
            title: title,
            artist: sanitize(p.artist),
            album: sanitize(p.album),
            appBundleID: bundleID(p.parentApplicationBundleIdentifier) ?? bundleID(p.bundleIdentifier),
            isPlaying: playing,
            duration: p.durationMicros.flatMap { validDuration($0 / 1_000_000) },
            elapsedAtStamp: finiteOrZero((p.elapsedTimeMicros ?? 0) / 1_000_000),
            stamp: p.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date(),
            rate: p.playbackRate ?? (playing ? 1 : 0),
            contentID: sanitize(p.contentItemIdentifier),
            artworkBase64: p.artworkData.flatMap { $0.utf8.count <= maxArtworkBase64Bytes ? $0 : nil })
    }

    /// Auch vom AppleScript-Rückfall genutzt: endlich, > 0, höchstens `maxDuration`.
    static func validDuration(_ d: TimeInterval) -> TimeInterval? {
        d.isFinite && d > 0 && d <= maxDuration ? d : nil
    }

    private static func finiteOrZero(_ d: Double) -> Double { d.isFinite ? d : 0 }

    /// Kürzen, Steuer-/Format-/Richtungszeichen und Zeilentrenner weg, Zalgo begrenzen.
    /// Ausnahme: ZWJ/ZWNJ (U+200D/U+200C) bleiben, wenn davor und danach ein behaltenes Zeichen steht
    /// (Emoji-Sequenzen, persische/indische Schrift), höchstens `maxJoiners` je Feld.
    /// Reihenfolge wichtig: erst Skalare begrenzen, dann filtern (sonst wäre ein 4-MB-Titel schon im Speicher).
    static func sanitize(_ s: String?) -> String? {
        guard let s else { return nil }
        let scalars = Array(s.unicodeScalars.prefix(maxScalarsScanned))
        var kept = String.UnicodeScalarView()
        var marks = 0
        var joiners = 0
        var previousKept = false
        for (index, scalar) in scalars.enumerated() {
            if isStripped(scalar) {
                // Verbinder nur zwischen zwei Zeichen, die selbst bleiben (kein Rand, kein Doppel).
                let isJoiner = scalar.value == 0x200C || scalar.value == 0x200D
                let nextIsText = index + 1 < scalars.count && !isStripped(scalars[index + 1])
                guard isJoiner, previousKept, nextIsText, joiners < maxJoiners else {
                    previousKept = false
                    continue
                }
                joiners += 1
                kept.append(scalar)
                marks = 0
                previousKept = false   // zwei Verbinder nacheinander ausgeschlossen
                continue
            }
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark || category == .enclosingMark {
                marks += 1
                if marks > maxCombiningRun { previousKept = false; continue }
            } else {
                marks = 0
            }
            kept.append(scalar)
            previousKept = true
        }
        let cleaned = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var out = String(cleaned.prefix(maxTextLength))
        while out.utf8.count > maxTextBytes { out.removeLast() }
        return out.isEmpty ? nil : out
    }

    /// Cc + Cf (u. a. LRM/RLM/ALM, ZWSP, BOM, ZWJ/ZWNJ, U+202A–202E, U+2066–2069) und Zeilentrenner.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x2028 || scalar.value == 0x2029
    }

    /// Nur plausible Bundle-IDs weiterreichen (BundleID.isValid, aus Seams Link-Regeln übernommen).
    private static func bundleID(_ s: String?) -> String? {
        guard let s, BundleID.isValid(s) else { return nil }
        return s
    }
}
