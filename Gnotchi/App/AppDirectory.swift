import Foundation

/// Name von Gnotchis Datenordner unter `~/Library/Application Support`. Ausgeliefert immer „Gnotchi“.
///
/// Nur ein Debug-Build mit der Kennung der Bild-Testkopie (G45) nimmt einen eigenen Ordner: Die Kopie hat eine
/// eigene Kennung, damit ihre Bildschirmaufnahme-Freigabe nicht auch für das echte Gnotchi gilt. Ohne eigenen
/// Ordner läse sie trotzdem Michaels Ablage und Zwischenablage und belegte dieselben Sockets.
enum AppDirectory {
    /// `true` nur im Debug-Build der Bild-Testkopie; im Release-Build gibt es den Zweig nicht.
    nonisolated static var isBildCopy: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier == "dev.mwlr.gnotchi.bild"
        #else
        false
        #endif
    }

    nonisolated static var name: String { isBildCopy ? "Gnotchi Bild" : "Gnotchi" }
}
