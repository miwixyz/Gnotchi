import Foundation
import XCTest

extension XCTestCase {
    /// Wegwerf-Einstellungen für einen Test, Name `<prefix>-<Testname>[-n]`, vor der Nutzung und nach dem Test
    /// geleert. Fester Name statt UUID: Je Lauf blieb sonst eine Datei in `~/Library/Preferences` liegen (28.11.2026
    /// über 1 600). Die Datei selbst zu löschen hilft nicht – cfprefsd schreibt sie danach leer wieder hin (gemessen).
    @MainActor
    func throwawayDefaults(_ prefix: String) -> UserDefaults {
        let test = name.filter { $0.isLetter || $0.isNumber }
        let count = ThrowawayDefaultsCounter.next(test + prefix)
        let suite = "\(prefix)-\(test)" + (count > 1 ? "-\(count)" : "")
        UserDefaults().removePersistentDomain(forName: suite)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite) ?? UserDefaults()
    }
}

/// Zweiter Aufruf mit gleichem Präfix im selben Test bekommt einen eigenen Bereich (sonst leerte er den ersten).
@MainActor
private enum ThrowawayDefaultsCounter {
    static var seen: [String: Int] = [:]
    static func next(_ key: String) -> Int {
        seen[key, default: 0] += 1
        return seen[key]!
    }
}
