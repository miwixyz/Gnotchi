import Foundation

/// Bündel mit Gnotchis Bildern und Schriften. In der App ist das das App-Bündel (wie `Bundle.main`).
/// Im Testlauf ohne Host-App (ab 2026-10-29) ist `Bundle.main` der xctest-Agent; dann ist es das
/// Testbündel, in das project.yml dieselben Dateien kopiert.
enum AppResources {
    static let bundle = Bundle(for: Marker.self)

    private final class Marker {}
}
