import Security
import XCTest
@testable import Gnotchi

/// 0.4.0 Updates der App-Familie (SECURE-DESIGN G23/G24): Schema, Erledigt-Regel, Drossel, Zuordnung fest,
/// Signaturprüfung vor dem Öffnen.
@MainActor
final class FamilyUpdatesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Schema (G23)

    func testParseValid() {
        XCTAssertEqual(FamilyUpdates.parse(["v": 1, "app": "kalli", "version": "0.11.0", "ready": true]),
                       .init(app: .kalli, version: "0.11.0", ready: true))
        XCTAssertEqual(FamilyUpdates.parse(["v": 1, "app": "seam", "version": "1.4", "ready": false,
                                            "extra": "ignoriert"]),
                       .init(app: .seam, version: "1.4", ready: false))
    }

    func testParseRejectsWrongTypes() {
        XCTAssertNil(FamilyUpdates.parse(nil))
        XCTAssertNil(FamilyUpdates.parse(["v": true, "app": "kalli", "version": "0.11.0", "ready": true]),
                     "Bool statt Zahl bei v")
        XCTAssertNil(FamilyUpdates.parse(["v": 2, "app": "kalli", "version": "0.11.0", "ready": true]))
        XCTAssertNil(FamilyUpdates.parse(["v": 1.5, "app": "kalli", "version": "0.11.0", "ready": true]))
        XCTAssertNil(FamilyUpdates.parse(["v": "1", "app": "kalli", "version": "0.11.0", "ready": true]))
        XCTAssertNil(FamilyUpdates.parse(["v": 1, "app": "kalli", "version": "0.11.0", "ready": 1]),
                     "Zahl statt Bool bei ready")
        XCTAssertNil(FamilyUpdates.parse(["v": 1, "app": "kalli", "version": "0.11.0"]), "ohne ready")
        XCTAssertNil(FamilyUpdates.parse(["v": 1, "app": "kalli", "version": 11, "ready": true]))
    }

    func testParseRejectsForeignApps() {
        for app in ["gnotchi", "Kalli", "finder", "", "kalli ", "com.kalli.app"] {
            XCTAssertNil(FamilyUpdates.parse(["v": 1, "app": app, "version": "1.0", "ready": true]), app)
        }
    }

    func testVersionForm() {
        for ok in ["0.11", "0.11.0", "1.2.3", "999.999.999", "0.0"] {
            XCTAssertTrue(FamilyUpdates.isValidVersion(ok), ok)
        }
        for bad in ["1", "1.2.3.4", "1000.0", "1..2", ".1", "1.", "v1.2", "1.2-beta", "1.2 ", "١.٢", "1.2\u{202E}",
                    "1.2\nX", "", String(repeating: "1.", count: 400) + "1"] {
            XCTAssertFalse(FamilyUpdates.isValidVersion(bad), bad)
        }
    }

    func testLabelUsesFixedNameNotMessage() {
        let e = FamilyUpdates.Entry(app: .kalli, version: "0.11.0", seen: now)
        XCTAssertEqual(e.label, "Kalli 0.11.0 bereit")
    }

    // MARK: Erledigt-Regel

    private let kalli = FamilyUpdates.Message(app: .kalli, version: "0.11.0", ready: true)

    func testReadyAddsAndReplaces() {
        var e = FamilyUpdates.apply(kalli, to: [:], installed: "0.10.0", now: now)
        XCTAssertEqual(e[.kalli]?.version, "0.11.0")
        e = FamilyUpdates.apply(.init(app: .kalli, version: "0.12.0", ready: true), to: e, installed: "0.10.0",
                                now: now.addingTimeInterval(5))
        XCTAssertEqual(e[.kalli]?.version, "0.12.0")
        XCTAssertEqual(e.count, 1, "je App höchstens ein Eintrag")
    }

    func testNotReadyRemoves() {
        let e = FamilyUpdates.apply(kalli, to: [:], installed: nil, now: now)
        XCTAssertNil(FamilyUpdates.apply(.init(app: .kalli, version: "0.11.0", ready: false), to: e, installed: nil,
                                         now: now)[.kalli])
    }

    func testAlreadyInstalledIsNotAdded() {
        XCTAssertNil(FamilyUpdates.apply(kalli, to: [:], installed: "0.11.0", now: now)[.kalli])
        XCTAssertNil(FamilyUpdates.apply(kalli, to: [:], installed: "0.11", now: now)[.kalli], "0.11 == 0.11.0")
        XCTAssertNil(FamilyUpdates.apply(kalli, to: [:], installed: "1.0.0", now: now)[.kalli])
        XCTAssertNotNil(FamilyUpdates.apply(kalli, to: [:], installed: "0.10.9", now: now)[.kalli])
        XCTAssertNotNil(FamilyUpdates.apply(kalli, to: [:], installed: "0.9.99", now: now)[.kalli], "Zahlen, nicht Text")
    }

    func testPruneInstalledAndExpired() {
        var e = FamilyUpdates.apply(kalli, to: [:], installed: nil, now: now)
        e = FamilyUpdates.apply(.init(app: .seam, version: "1.4.0", ready: true), to: e, installed: nil, now: now)
        let installed: (FamilyApp) -> String? = { $0 == .kalli ? "0.11.0" : nil }
        XCTAssertEqual(Set(FamilyUpdates.prune(e, installed: installed, now: now).keys), [.seam], "installiert")
        let late = now.addingTimeInterval(FamilyUpdates.maxAge)
        XCTAssertTrue(FamilyUpdates.prune(e, installed: { _ in nil }, now: late).isEmpty, "14 Tage ohne Meldung")
        XCTAssertEqual(FamilyUpdates.prune(e, installed: { _ in nil }, now: late.addingTimeInterval(-1)).count, 2)
    }

    func testSortedInFamilyOrder() {
        var e = FamilyUpdates.apply(.init(app: .seam, version: "1.0", ready: true), to: [:], installed: nil, now: now)
        e = FamilyUpdates.apply(.init(app: .tippi, version: "2.0", ready: true), to: e, installed: nil, now: now)
        XCTAssertEqual(FamilyUpdates.sorted(e).map(\.app), [.tippi, .seam])
    }

    func testOwnEntryOnlyWithValidVersion() {
        XCTAssertEqual(FamilyUpdates.ownEntry("0.5.0", now: now)?.app, .gnotchi)
        XCTAssertNil(FamilyUpdates.ownEntry(nil, now: now))
        XCTAssertNil(FamilyUpdates.ownEntry("0.5.0 <b>", now: now))
    }

    // MARK: Drossel

    func testThrottlePerApp() {
        XCTAssertTrue(FamilyUpdates.accepts(last: nil, now: now))
        XCTAssertFalse(FamilyUpdates.accepts(last: now, now: now.addingTimeInterval(0.5)))
        XCTAssertTrue(FamilyUpdates.accepts(last: now, now: now.addingTimeInterval(1)))
    }

    func testLinkDropsFloodAndKeepsAppsApart() {
        let activity = ActivityModel(media: NowPlayingModel())
        let link = FamilyUpdateLink(activity: activity, installed: { _ in nil })
        link.receive(kalli, now: now)
        link.receive(.init(app: .kalli, version: "0.11.0", ready: false), now: now.addingTimeInterval(0.2))
        XCTAssertEqual(activity.familyUpdates.map(\.app), [.kalli], "zweite Kalli-Meldung binnen 1 s verworfen")
        link.receive(.init(app: .seam, version: "1.4.0", ready: true), now: now.addingTimeInterval(0.3))
        XCTAssertEqual(activity.familyUpdates.map(\.app), [.kalli, .seam], "andere App hat eigene Drossel")
        link.receive(.init(app: .kalli, version: "0.11.0", ready: false), now: now.addingTimeInterval(1.2))
        XCTAssertEqual(activity.familyUpdates.map(\.app), [.seam])
        link.receive(nil, now: now.addingTimeInterval(5))
        XCTAssertEqual(activity.familyUpdates.map(\.app), [.seam], "ungültige Meldung ändert nichts")
        link.stop()
        XCTAssertTrue(activity.familyUpdates.isEmpty)
    }

    // MARK: G24 – Zuordnung fest, Signaturprüfung

    func testBundleIDsFixed() {
        XCTAssertEqual(FamilyApp.tippi.bundleID, "com.tippi.app")
        XCTAssertEqual(FamilyApp.kalli.bundleID, "com.kalli.app")
        XCTAssertEqual(FamilyApp.qotti.bundleID, "app.qotti.local")
        XCTAssertEqual(FamilyApp.seam.bundleID, "dev.mwlr.seam")
        XCTAssertEqual(FamilyApp.remote, [.tippi, .kalli, .qotti, .seam], "Gnotchi meldet nie über distnoted")
        XCTAssertTrue(FamilyLauncher.requirement(for: .kalli).contains(#"identifier "com.kalli.app""#))
        XCTAssertTrue(FamilyLauncher.requirement(for: .kalli).contains("LTKJ6Z2VYB"))
    }

    func testVerifiedURLNeedsValidSignature() {
        let url = URL(fileURLWithPath: "/Applications/Kalli.app")
        var asked: [String] = []
        XCTAssertNil(FamilyLauncher.verifiedURL(for: .kalli, locate: { asked.append($0); return [url] },
                                                verify: { _, _ in errSecCSReqFailed }))
        XCTAssertEqual(asked, ["com.kalli.app"], "Ort nur über die feste Bundle-ID")
        XCTAssertEqual(FamilyLauncher.verifiedURL(for: .kalli, locate: { _ in [url] }, verify: { _, _ in errSecSuccess }), url)
        XCTAssertNil(FamilyLauncher.verifiedURL(for: .kalli, locate: { _ in [] }), "nicht installiert")
        let fake = URL(fileURLWithPath: "/Users/x/Applications/Kalli.app")
        XCTAssertEqual(FamilyLauncher.verifiedURL(for: .kalli, locate: { _ in [fake, url] },
                                                  verify: { u, _ in u == url ? errSecSuccess : errSecCSReqFailed }), url,
                       "Attrappe vorne blockiert den Klick nicht, die echte App wird geöffnet")
    }

    /// Attrappe mit Kallis Kennung, ad hoc signiert: Die echte Anforderung lehnt sie ab. Gegenprobe: Nur mit der
    /// Kennung (ohne Developer ID/Team) ginge sie durch – ohne die Prüfung würde die Attrappe also gestartet.
    func testAdHocDummyWithSameIdentifierIsRejected() throws {
        let app = try makeAdHocApp(identifier: "com.kalli.app")
        XCTAssertNotEqual(FamilyLauncher.checkSignature(at: app, requirement: FamilyLauncher.requirement(for: .kalli)),
                          errSecSuccess)
        XCTAssertNil(FamilyLauncher.verifiedURL(for: .kalli, locate: { _ in [app] }))
        XCTAssertEqual(FamilyLauncher.checkSignature(at: app, requirement: #"identifier "com.kalli.app""#), errSecSuccess,
                       "Gegenprobe: Attrappe ist gültig signiert, nur nicht von Michaels Team")
    }

    /// Das echte, installierte Kalli besteht die Prüfung (sonst wäre die Anforderung falsch und jeder Klick scheiterte).
    func testInstalledKalliPasses() throws {
        let url = URL(fileURLWithPath: "/Applications/Kalli.app")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Kalli nicht installiert") }
        XCTAssertEqual(FamilyLauncher.checkSignature(at: url, requirement: FamilyLauncher.requirement(for: .kalli)),
                       errSecSuccess)
        XCTAssertNotEqual(FamilyLauncher.checkSignature(at: url, requirement: FamilyLauncher.requirement(for: .seam)),
                          errSecSuccess, "falsche Kennung")
    }

    private func makeAdHocApp(identifier: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gnotchi-fake-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Kalli.app")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macos.appendingPathComponent("Kalli"))
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Kalli",
                                    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "99.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "--sign", "-", "--identifier", identifier, app.path]
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "codesign ad hoc")
        return app
    }
}
