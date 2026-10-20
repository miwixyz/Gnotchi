import Foundation
import Security

/// Tippis Live-Text (0.3.0, specs/2026-10-20-gnotchi-0.3.0-live-text.md, SECURE-DESIGN G21): reine Teile.
/// Diktattext ist so privat wie das Mikrofon. Er kommt nur über einen lokalen Socket, dessen Gegenseite
/// per Audit-Token gegen eine Developer-ID-Anforderung geprüft ist, nie über distnoted (G17), und wird
/// nie protokolliert oder gespeichert.
enum LiveText {

    /// Größte Nachricht (Länge + JSON). Größer → Verbindung trennen.
    nonisolated static let maxFrame = 4096
    /// Höchstens so viele Zeichen behält die Insel (zwei Zeilen brauchen weit weniger).
    nonisolated static let maxChars = 400

    /// Developer ID von Michaels Team – **nicht** nur `anchor apple generic`: Apple-Development-Builds tragen
    /// `get-task-allow` und ließen sich vom gleichen Nutzer anhängen (Spec, Zeile S/E).
    nonisolated static func peerRequirement(identifier: String) -> String {
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
            + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier ""#
            + identifier + #"" and certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    }

    nonisolated static let tippiRequirement = peerRequirement(identifier: "com.tippi.app")

    // MARK: Rahmen: 4 Byte Länge (Big Endian) + JSON

    enum Frame: Equatable {
        case message(Data), needMore, invalid
    }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer`. `invalid`: Länge 0 oder zu groß –
    /// der Aufrufer trennt die Verbindung.
    nonisolated static func nextFrame(_ buffer: inout Data) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= maxFrame else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    nonisolated static func frame(_ object: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object),
              json.count + 4 <= maxFrame else { return nil }
        let n = UInt32(json.count).bigEndian
        return withUnsafeBytes(of: n) { Data($0) } + json
    }

    // MARK: Schema

    /// `{"v":1,"text":"…"}` – `v` Zahl 1 (kein Wahrheitswert), `text` String. Unbekannte Schlüssel
    /// ignoriert. Liefert den bereinigten Text, `nil` bei allem anderen.
    nonisolated static func parse(_ payload: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
              v.intValue == 1, v.doubleValue == 1,
              let text = obj["text"] as? String else { return nil }
        return tail(sanitize(text))
    }

    /// Steuer- und Formatzeichen raus (u. a. Richtungs-Overrides U+202E, Nullbreite), außer dem
    /// Emoji-Verbinder U+200D. Zeilenumbrüche/Tabs → Leerzeichen, Leerraum zusammengefasst.
    nonisolated static func sanitize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in s.unicodeScalars {
            let cat = scalar.properties.generalCategory
            if scalar.properties.isWhitespace || cat == .control {
                if !lastWasSpace { out.append(" "); lastWasSpace = true }
                continue
            }
            if cat == .format && scalar.value != 0x200D { continue }
            out.append(scalar)
            lastWasSpace = false
        }
        var result = String(out)
        if result.last == " " { result.removeLast() }
        return result
    }

    /// Nur das Ende behalten (die Insel zeigt die neuesten Wörter), an einer Wortgrenze, mit „…“ davor.
    /// `limit` kleiner für die Anzeige: zwei Zeilen fassen etwa 85 Zeichen (Testbild 20.10.: `.truncationMode(.head)`
    /// kürzt bei zwei Zeilen nur die letzte – oben stand sonst der Anfang des Diktats).
    nonisolated static func tail(_ s: String, limit: Int = maxChars) -> String {
        guard s.count > limit else { return s }
        var cut = String(s.suffix(limit))
        if let space = cut.prefix(max(limit / 10, 8)).firstIndex(of: " ") {
            cut = String(cut[cut.index(after: space)...])
        }
        return "…" + cut
    }
}
