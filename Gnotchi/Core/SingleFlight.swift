/// Höchstens eine Arbeit gleichzeitig; was währenddessen kommt, wird verworfen (Adapter-Befehle:
/// ein Klick mehr startet keinen weiteren Perl-Prozess, Security-Review 18.10. B4).
struct OneAtATime {
    private(set) var busy = false

    mutating func tryStart() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    mutating func finish() { busy = false }
}

/// Höchstens eine Arbeit gleichzeitig; von dem, was währenddessen kommt, wartet nur das NEUESTE
/// (Cover-Dekodieren: ältere Titel sind ohnehin abgelöst, Security-Review 18.10. B3).
struct LatestWins<Item> {
    private(set) var running = false
    private var waiting: Item?

    /// Das zu startende Element – oder nil, wenn schon etwas läuft (dann wartet `item` statt eines älteren).
    mutating func submit(_ item: Item) -> Item? {
        guard !running else {
            waiting = item
            return nil
        }
        running = true
        return item
    }

    /// Laufende Arbeit fertig: das wartende Element starten (bleibt belegt) oder frei werden (nil).
    mutating func finish() -> Item? {
        if let next = waiting {
            waiting = nil
            return next
        }
        running = false
        return nil
    }
}
