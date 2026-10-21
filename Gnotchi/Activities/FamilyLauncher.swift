import AppKit
import OSLog
import Security

/// Klick auf ein Update öffnet nur die echte App (0.4.0, SECURE-DESIGN G24). Bundle-ID fest im Code
/// (`FamilyApp.bundleID`), Programm über LaunchServices, vor dem Öffnen Signatur gegen Developer ID +
/// Team LTKJ6Z2VYB + Kennung geprüft (Anforderung wie G21). Eine Attrappe gleicher Kennung (etwa in
/// `~/Applications`) wird so nie gestartet.
enum FamilyLauncher {

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "familie")
    /// Kurz warten, bis eine frisch gestartete App ihren Beobachter angemeldet hat.
    private static let showDelay: Duration = .milliseconds(1500)

    nonisolated static func requirement(for app: FamilyApp) -> String {
        LiveText.peerRequirement(identifier: app.bundleID)
    }

    /// Statische Signaturprüfung des Programms an `url` gegen `requirement`. `errSecSuccess` = gültig.
    nonisolated static func checkSignature(at url: URL, requirement: String) -> OSStatus {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard status == errSecSuccess, let code else { return status == errSecSuccess ? errSecCSStaticCodeNotFound : status }
        var req: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &req)
        guard status == errSecSuccess, let req else { return status == errSecSuccess ? errSecCSReqInvalid : status }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), req)
    }

    /// Welche Programm-URL geöffnet werden darf: die erste aller Fundorte zur festen Bundle-ID mit gültiger Signatur.
    /// Alle, nicht nur LaunchServices' Favorit: Eine Attrappe gleicher Kennung soll den Klick nicht blockieren
    /// (rafter-code-review 21.10., Verfügbarkeit) – gestartet würde sie ohnehin nie.
    nonisolated static func verifiedURL(for app: FamilyApp, locate: (String) -> [URL],
                                        verify: (URL, String) -> OSStatus = checkSignature) -> URL? {
        let req = requirement(for: app)
        return locate(app.bundleID).first { verify($0, req) == errSecSuccess }
    }

    /// Öffnet die App und bittet sie danach, ihr Update-Fenster zu zeigen. `completion(false)`: nicht
    /// gefunden oder Signatur ungültig – dann wird nichts gestartet.
    @MainActor
    static func open(_ app: FamilyApp, completion: @escaping @MainActor (Bool) -> Void) {
        let locations = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID)
        Task {
            // Signaturprüfung liest das ganze Bundle – nicht auf dem Hauptthread.
            let url = await Task.detached(priority: .userInitiated) {
                verifiedURL(for: app, locate: { _ in locations })
            }.value
            guard let url else {
                log.error("Update öffnen: \(app.rawValue, privacy: .public) nicht gefunden oder Signatur ungültig")
                return completion(false)
            }
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                log.error("Update öffnen: \(app.rawValue, privacy: .public) startet nicht")
                return completion(false)
            }
            completion(true)
            try? await Task.sleep(for: showDelay)
            postShow(app)
        }
    }

    /// `{"v":1,"app":"kalli"}` – die App reagiert nur, wenn sie selbst ein Update bereit hat (G24).
    @MainActor
    static func postShow(_ app: FamilyApp) {
        DistributedNotificationCenter.default().postNotificationName(
            FamilyUpdates.showName, object: nil, userInfo: ["v": 1, "app": app.rawValue], deliverImmediately: true)
    }
}
