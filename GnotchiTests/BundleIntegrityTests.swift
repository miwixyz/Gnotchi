import XCTest
@testable import Gnotchi

/// G2: Gnotchi startet den Adapter nur aus einem unveränderten, signierten Bundle.
final class BundleIntegrityTests: XCTestCase {

    private var tempRoots: [URL] = []

    override func tearDown() {
        // Temp-Verzeichnisse über FileManager aufräumen (kein rm -rf in der Shell).
        for root in tempRoots { try? FileManager.default.removeItem(at: root) }
        tempRoots = []
        super.tearDown()
    }

    /// Baut ein eigenes, ad hoc signiertes Mini-Bundle – unabhängig vom Test-Host.
    private func makeProbeBundle(signed: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempRoots.append(root)
        let app = root.appendingPathComponent("Probe.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("MacOS/Probe").path)
        try Data("print 1;\n".utf8).write(to: app.appendingPathComponent("Resources/skript.pl"))
        let plist: [String: Any] = ["CFBundleExecutable": "Probe", "CFBundleIdentifier": "dev.mwlr.gnotchi.probe",
                                    "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        if signed {
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", root.appendingPathComponent("Probe.app").path]
            try sign.run()
            sign.waitUntilExit()
            XCTAssertEqual(sign.terminationStatus, 0)
        }
        return root.appendingPathComponent("Probe.app")
    }

    // Strukturtests ohne Identitätsanforderung (nil): die Probe ist nur ad hoc signiert.

    func testIntactBundlePasses() throws {
        XCTAssertTrue(BundleIntegrity.isIntact(try makeProbeBundle(), requirement: nil))
    }

    func testChangedScriptFails() throws {
        let app = try makeProbeBundle()
        try Data("system('evil');\n".utf8).write(to: app.appendingPathComponent("Contents/Resources/skript.pl"))
        XCTAssertFalse(BundleIntegrity.isIntact(app, requirement: nil))
    }

    /// Eine zusätzliche Datei darf das Siegel ebenfalls brechen (z. B. untergeschobenes Skript).
    func testExtraResourceFails() throws {
        let app = try makeProbeBundle()
        try Data("print 2;\n".utf8).write(to: app.appendingPathComponent("Contents/Resources/extra.pl"))
        XCTAssertFalse(BundleIntegrity.isIntact(app, requirement: nil))
    }

    func testMissingBundleFails() {
        XCTAssertFalse(BundleIntegrity.isIntact(URL(fileURLWithPath: "/tmp/gibt-es-nicht.app"), requirement: nil))
    }

    func testUnsignedBundleFails() throws {
        let app = try makeProbeBundle(signed: false)
        XCTAssertFalse(BundleIntegrity.isIntact(app, requirement: nil))
    }

    /// Kern von G2: Gültigkeit ohne Identität reicht nicht. Wer das Skript ändert, kann das Bundle
    /// per `codesign -fs -` neu versiegeln – die Standard-Anforderung (Team-Zertifikat) muss das abweisen.
    func testAdHocSignedBundleRejectedByDefaultRequirement() throws {
        let app = try makeProbeBundle()
        XCTAssertFalse(BundleIntegrity.isIntact(app))
        XCTAssertEqual(BundleIntegrity.check(app), errSecCSReqFailed)
    }
}
