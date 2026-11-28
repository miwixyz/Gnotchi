import XCTest

/// Favoriten-Geräte im Mixer (0.31.0): Reihenfolge, fehlende Geräte, Obergrenze, Speichern.
@MainActor
final class MixerFavoritesTests: XCTestCase {
    private func dev(_ id: UInt32, _ name: String, uid: String?) -> OutputDevices.Device {
        OutputDevices.Device(id: id, name: name, transport: 0, uid: uid)
    }

    private func freshDefaults() throws -> UserDefaults {
        throwawayDefaults("gnotchi-favtest")
    }

    func testShownKeepsFavoriteOrderNotDeviceOrder() {
        let devices = [dev(1, "A", uid: "a"), dev(2, "B", uid: "b"), dev(3, "C", uid: "c")]
        XCTAssertEqual(MixerFavorites.shown(["c", "a"], in: devices).map(\.id), [3, 1])
    }

    func testShownSkipsDisconnectedAndUnknownUIDs() {
        let devices = [dev(1, "A", uid: "a"), dev(2, "B", uid: nil)]
        XCTAssertEqual(MixerFavorites.shown(["x", "a", "b"], in: devices).map(\.id), [1])
        XCTAssertTrue(MixerFavorites.shown([], in: devices).isEmpty)
    }

    func testToggleAddsAtEndAndRemoves() {
        XCTAssertEqual(MixerFavorites.toggled(["a"], uid: "b"), ["a", "b"])
        XCTAssertEqual(MixerFavorites.toggled(["a", "b"], uid: "a"), ["b"])
    }

    func testToggleStopsAtLimitButStillRemoves() {
        let full = (1...MixerFavorites.maxPerList).map { "u\($0)" }
        XCTAssertEqual(MixerFavorites.toggled(full, uid: "neu"), full)
        XCTAssertEqual(MixerFavorites.toggled(full, uid: "u1").count, MixerFavorites.maxPerList - 1)
    }

    func testLoadDropsEmptyDuplicatesAndCapsLength() throws {
        let d = try freshDefaults()
        d.set(["a", "", "a", "b"] + (1...10).map { "x\($0)" }, forKey: MixerFavorites.List.output.rawValue)
        let loaded = MixerFavorites.load(.output, from: d)
        XCTAssertEqual(Array(loaded.prefix(2)), ["a", "b"])
        XCTAssertEqual(loaded.count, MixerFavorites.maxPerList)
        XCTAssertTrue(MixerFavorites.load(.input, from: d).isEmpty)
    }

    func testModelPersistsToggleAndKeepsListsSeparate() throws {
        let d = try freshDefaults()
        let model = MixerModel(interval: .seconds(3600), defaults: d)
        let out = dev(1, "CalDigit", uid: "cal")
        model.toggleFavorite(out, .output)
        XCTAssertTrue(model.isFavorite(out, .output))
        XCTAssertFalse(model.isFavorite(out, .input))
        let again = MixerModel(interval: .seconds(3600), defaults: d)
        XCTAssertTrue(again.isFavorite(out, .output), "Favorit überlebt einen Neustart")
        again.toggleFavorite(out, .output)
        XCTAssertEqual(MixerFavorites.load(.output, from: d), [])
    }

    func testDeviceWithoutUIDCannotBecomeFavorite() throws {
        let model = MixerModel(interval: .seconds(3600), defaults: try freshDefaults())
        let d = dev(5, "Ohne UID", uid: nil)
        model.toggleFavorite(d, .output)
        XCTAssertFalse(model.isFavorite(d, .output))
        XCTAssertTrue(model.outputFavorites.isEmpty)
    }
}
