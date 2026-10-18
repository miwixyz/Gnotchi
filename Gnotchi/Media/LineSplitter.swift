import Foundation

/// Schneidet den stdout-Strom des Adapters in Zeilen (G4). Eine Zeile über
/// `maxLineBytes` wird komplett verworfen und gezählt – auch wenn sie über mehrere
/// Pakete verteilt ankommt –, damit ein entgleister Strom Gnotchi nicht volllaufen lässt.
struct LineSplitter {
    let maxLineBytes: Int
    private(set) var dropped = 0
    private var buffer = Data()
    private var skipping = false

    init(maxLineBytes: Int) { self.maxLineBytes = maxLineBytes }

    /// Arbeitet auf Teilstücken statt Byte für Byte: Mit `--no-diff` trägt jede Zeile das
    /// Base64-Cover (bis ca. 2 MB). Läuft auf dem Lese-Thread (StreamReader), nicht auf dem MainActor.
    mutating func feed(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var pos = chunk.startIndex
        while pos < chunk.endIndex {
            let newline = chunk[pos...].firstIndex(of: 0x0A)
            let segment = chunk[pos..<(newline ?? chunk.endIndex)]
            if !skipping {
                if buffer.count + segment.count > maxLineBytes {
                    dropped += 1
                    skipping = true
                    buffer.removeAll()   // Speicher freigeben, nicht nur leeren
                } else {
                    buffer.append(segment)
                }
            }
            guard let newline else { break }
            // Zeilenende: gültige Zeile ausgeben, Zustand zurücksetzen.
            if !skipping && !buffer.isEmpty { lines.append(buffer) }
            skipping = false
            buffer = Data()   // neu statt keepingCapacity: `lines` teilt sich den alten Speicher
            pos = chunk.index(after: newline)
        }
        return lines
    }
}
