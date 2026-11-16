import Foundation

/// Warnton-Lautstärke des Systems (0.33.0, G57): der Regler „Warntonlautstärke“ aus Systemeinstellungen → Ton.
///
/// macOS führt sie getrennt von der Ausgabelautstärke (`alert volume` in `get volume settings`, 0…100). Gelesen und gesetzt
/// wird mit den Standardbefehlen von AppleScript (`get volume settings`, `set volume alert volume N`): kein Zielprogramm,
/// kein Automation-Dialog, keine neue Freigabe. Die Skripte sind **feste Texte**; eingesetzt wird nur eine auf 0…100
/// begrenzte Ganzzahl, nie ein Wert von außen. Läuft nie auf dem Hauptthread, höchstens 3 Sekunden.
enum SystemAlertVolume {
    nonisolated static let readScript = """
    with timeout of 3 seconds
    return alert volume of (get volume settings)
    end timeout
    """

    nonisolated static func setScript(_ percent: Int) -> String {
        "with timeout of 3 seconds\nset volume alert volume \(clamp(percent))\nend timeout"
    }

    nonisolated static func clamp(_ percent: Int) -> Int { min(100, max(0, percent)) }

    /// Aktuelle Warnton-Lautstärke in Prozent; nil, wenn macOS keine meldet.
    nonisolated static func read() async -> Int? {
        await run(readScript).flatMap { $0.int32Value }.map { clamp(Int($0)) }
    }

    /// Setzt die Warnton-Lautstärke; liefert, ob macOS den Befehl angenommen hat.
    @discardableResult
    nonisolated static func set(_ percent: Int) async -> Bool {
        await run(setScript(percent)) != nil
    }

    /// Eine eigene serielle Queue: NSAppleScript verträgt gleichzeitige Aufrufe nicht (gemessen 16.11.: 320 Aufrufe aus 8 Threads,
    /// 1 Fehler). Lesen (Mixer-Abfrage) und Setzen (Ziehen am Regler) laufen so nie ineinander.
    private nonisolated static let queue = DispatchQueue(label: "dev.mwlr.gnotchi.alertvolume", qos: .userInitiated)

    /// NSAppleScript ist nicht Sendable: auf der Queue erzeugt, nie geteilt.
    private nonisolated static func run(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil ? out : nil)
            }
        }
    }
}
