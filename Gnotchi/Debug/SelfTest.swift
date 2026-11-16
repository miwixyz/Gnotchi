#if DEBUG
import AppKit
import Foundation

/// Selbsttest der Bild-Testkopie (BAMA `test-mac-app`, übernommen 2026-11-16): ruft im laufenden Bündel dieselben
/// Teile auf wie die Oberfläche und meldet je Schritt PASS oder FAIL. Kommt als Befehl `selftest` über den
/// Befehlskanal (`gnotchictl selftest`, Exit 0/1), weil Gnotchi eine Ein-Instanz-App ohne Startoption ist.
///
/// Abgeschottet wie die ganze Kopie: eigener Datenordner, Einstellungen nur in einer Wegwerf-Suite. Gestartet wird
/// NICHT, was Seiteneffekte hat (Claude-Hooks, Wetter-Netz, Hilfsprogramm, Zwischenablage, Ablage, Sockets) – der
/// Rauchtest deckt nur die beiden reinen Beobachter ab (Kopfhörer, Mikrofon/Kamera: CoreAudio-Rückrufe, genau der
/// Ort der Swift-6-Falle „Closure erbt den Hauptakteur“).
@MainActor
enum SelfTest {
    struct Step {
        let name: String
        let ok: Bool
        let detail: String
    }

    /// Dauer des Rauchtests. Lang genug für ein paar Rückrufe, kurz genug für den Befehl (Wartezeit der Steuerung 30 s).
    static let smokeSeconds = 3.0
    private static let scratchSuite = "dev.mwlr.gnotchi.bild.selftest"

    static func run(model: AppModel) async -> [Step] {
        var steps: [Step] = []
        steps.append(isolation())
        steps.append(resources())
        steps.append(bundleSeal())
        steps.append(preferencesRoundTrip())
        steps.append(contentsOf: await windows(model: model))
        steps.append(await smoke(model: model))
        return steps
    }

    /// Antwort für `Antworten/<id>.json`: `bestanden` plus `schritte`.
    static func answer(_ steps: [Step]) -> [String: Any] {
        ["ok": true,
         "bestanden": !steps.isEmpty && steps.allSatisfy(\.ok),
         "schritte": steps.map { ["name": $0.name, "ok": $0.ok, "detail": $0.detail] as [String: Any] }]
    }

    // MARK: Schritte

    /// Die Kopie darf nie auf Michaels echte Daten zeigen.
    private static func isolation() -> Step {
        let id = Bundle.main.bundleIdentifier ?? "?"
        let folder = LiveTextLink.directory?.lastPathComponent ?? "?"
        let ok = id == "dev.mwlr.gnotchi.bild" && AppDirectory.isBildCopy && folder == "Gnotchi Bild"
        return Step(name: "Abschottung", ok: ok, detail: "Kennung \(id), Datenordner \(folder)")
    }

    /// Schrift und Texte im Bündel – fehlt eine, fällt die Oberfläche still auf die Systemschrift zurück.
    private static func resources() -> Step {
        let families = NSFontManager.shared.availableFontFamilies
        let font = families.contains("Plus Jakarta Sans")
        let names: [String] = ["HILFE", "CHANGELOG", "THIRD-PARTY-LICENSES"]
        let missing: [String] = names.filter { AppResources.bundle.url(forResource: $0, withExtension: "md") == nil }
        let ok = font && missing.isEmpty
        let fontText = font ? "da" : "FEHLT"
        let missingText = missing.isEmpty ? "" : ", fehlt: " + missing.joined(separator: ", ")
        return Step(name: "Ressourcen", ok: ok, detail: "Schrift " + fontText + missingText)
    }

    /// Siegel unversehrt (ohne Team-Anforderung: die Kopie trägt eine andere Kennung als die echte App).
    private static func bundleSeal() -> Step {
        let status = BundleIntegrity.check(Bundle.main.bundleURL, requirement: nil)
        return Step(name: "Bundle-Siegel", ok: status == errSecSuccess, detail: "OSStatus \(status)")
    }

    /// Einstellung schreiben, mit neuer Instanz lesen – in einer Wegwerf-Suite, nie in den echten Einstellungen.
    private static func preferencesRoundTrip() -> Step {
        guard let suite = UserDefaults(suiteName: scratchSuite) else {
            return Step(name: "Einstellungen", ok: false, detail: "Suite nicht angelegt")
        }
        suite.removePersistentDomain(forName: scratchSuite)
        defer { suite.removePersistentDomain(forName: scratchSuite) }
        let writer = Preferences(defaults: suite)
        writer.weatherUnit = .fahrenheit
        let read = Preferences(defaults: suite).weatherUnit
        return Step(name: "Einstellungen", ok: read == .fahrenheit, detail: "geschrieben fahrenheit, gelesen \(read.rawValue)")
    }

    /// Einstellungen und Hilfe öffnen sich wirklich (sichtbar mit ihrer Kennung). Danach wieder zu.
    private static func windows(model: AppModel) async -> [Step] {
        var result: [Step] = []
        for id in [AppModel.WindowID.settings, AppModel.WindowID.help] {
            model.showWindow(id)
            var window: NSWindow?
            for _ in 0..<15 where window == nil {
                try? await Task.sleep(for: .milliseconds(100))
                window = NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(id) == true }
            }
            let size = window.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" } ?? "nicht offen"
            result.append(Step(name: "Fenster \(id)", ok: window != nil, detail: size))
            window?.close()
        }
        return result
    }

    /// Rauchtest: die beiden reinen Beobachter ein paar Sekunden laufen lassen, dabei Einstellung wechseln
    /// (recheck), dann stoppen. Ein Absturz auf einer Hintergrund-Warteschlange beendet die Kopie – dann fehlt die
    /// Antwort, und `gnotchictl` meldet „Keine Antwort“ statt PASS.
    private static func smoke(model: AppModel) async -> Step {
        let headphones = HeadphoneWatcher(activity: model.activity)
        let privacy = PrivacyMonitor(activity: model.activity)
        headphones.start()
        privacy.start()
        try? await Task.sleep(for: .seconds(smokeSeconds / 2))
        headphones.recheck()
        privacy.recheck()
        try? await Task.sleep(for: .seconds(smokeSeconds / 2))
        let devicesChanged = privacy.devicesChangedCount
        headphones.stop()
        privacy.stop()
        return Step(name: "Rauchtest", ok: true,
                    detail: "Kopfhörer- und Datenschutz-Beobachter \(smokeSeconds) s, Geräteänderungen: \(devicesChanged)")
    }
}
#endif
