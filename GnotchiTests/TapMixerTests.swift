import CoreAudio
import XCTest

/// Mixer Stufe 2 (G55): Verstärkung, Weichbegrenzer und Puffer-Kopie – mit selbst gebauten Puffern, ohne Core Audio.
final class TapMixerTests: XCTestCase {

    /// Puffer-Liste mit eigenem Speicher: `layout` = Kanäle je Puffer, `frames` Bilder je Puffer.
    fileprivate final class Buffers {
        let list: UnsafeMutableAudioBufferListPointer
        private var storage: [UnsafeMutablePointer<Float>] = []
        init(channels layout: [Int], frames: Int, fill: (Int, Int, Int) -> Float = { _, _, _ in 0 }) {
            list = AudioBufferList.allocate(maximumBuffers: max(1, layout.count))   // 0 Puffer: ohne Eingang
            list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(layout.count)
            for (i, c) in layout.enumerated() {
                let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames * c))
                for f in 0..<frames { for ch in 0..<c { p[f * c + ch] = fill(i, f, ch) } }
                storage.append(p)
                list[i] = AudioBuffer(mNumberChannels: UInt32(c), mDataByteSize: UInt32(frames * c * MemoryLayout<Float>.size),
                                      mData: UnsafeMutableRawPointer(p))
            }
        }
        deinit { storage.forEach { $0.deallocate() }; free(list.unsafeMutablePointer) }
        func sample(_ buffer: Int, _ frame: Int, _ channel: Int = 0) -> Float {
            let c = Int(list[buffer].mNumberChannels)
            return list[buffer].mData!.assumingMemoryBound(to: Float.self)[frame * c + channel]
        }
        var const: UnsafePointer<AudioBufferList> { UnsafePointer(list.unsafeMutablePointer) }
    }

    // MARK: Verstärkung

    func testClampKeepsZeroToTwoAndRejectsNonsense() {
        XCTAssertEqual(TapMixer.clamp(0.5), 0.5)
        XCTAssertEqual(TapMixer.clamp(-3), 0)
        XCTAssertEqual(TapMixer.clamp(9), 2)
        XCTAssertEqual(TapMixer.clamp(.nan), 1, "unsinnig → unverändert")
        XCTAssertEqual(TapMixer.clamp(.infinity), 1)
    }

    func testTapOnlyWhenNotAtHundredPercent() {
        XCTAssertFalse(TapMixer.needsTap(1.0))
        XCTAssertFalse(TapMixer.needsTap(1.004), "Rundung am Regler")
        XCTAssertTrue(TapMixer.needsTap(0.9))
        XCTAssertTrue(TapMixer.needsTap(1.5))
        XCTAssertTrue(TapMixer.needsTap(0))
    }

    // MARK: Begrenzer

    func testLimiterIsTransparentBelowKnee() {
        for x in stride(from: Float(-0.8), through: 0.8, by: 0.05) { XCTAssertEqual(TapMixer.limit(x), x, accuracy: 1e-7) }
    }

    func testLimiterNeverReachesOneAndIsMonotonic() {
        var last: Float = -.infinity
        for x in stride(from: Float(-10), through: 10, by: 0.01) {
            let y = TapMixer.limit(x)
            XCTAssertLessThanOrEqual(abs(y), 1.0)
            XCTAssertGreaterThanOrEqual(y, last, "monoton bei \(x)")
            last = y
        }
        XCTAssertLessThan(TapMixer.limit(1.2), 1.0)
        XCTAssertEqual(TapMixer.limit(-5), -TapMixer.limit(5), "symmetrisch")
    }

    func testLimiterIsContinuousAtKnee() {
        XCTAssertEqual(TapMixer.limit(0.8), 0.8, accuracy: 1e-6)
        XCTAssertEqual(TapMixer.limit(0.8001), 0.8001, accuracy: 1e-3)
    }

    func testQuieterIsPlainMultiplicationWithoutLimiter() {
        XCTAssertEqual(TapMixer.scaled(1.037, 0.5), 0.5185, accuracy: 1e-6, "Spitzen über 1,0 bleiben bei g ≤ 1 bitgenau skaliert")
        XCTAssertEqual(TapMixer.scaled(0.9, 1.0), 0.9)
    }

    func testLouderIsLimited() {
        XCTAssertLessThan(TapMixer.scaled(0.9, 2.0), 1.0)
        XCTAssertEqual(TapMixer.scaled(0.1, 2.0), 0.2, accuracy: 1e-6, "leise Stellen unverändert doppelt")
    }

    // MARK: Puffer

    func testStereoInterleavedHalfGain() {
        let input = Buffers(channels: [2], frames: 4) { _, f, c in Float(f + 1) * (c == 0 ? 0.1 : 0.2) }
        let output = Buffers(channels: [2], frames: 4)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 0.5, gainEnd: 0.5)
        for f in 0..<4 {
            XCTAssertEqual(output.sample(0, f, 0), Float(f + 1) * 0.05, accuracy: 1e-6)
            XCTAssertEqual(output.sample(0, f, 1), Float(f + 1) * 0.1, accuracy: 1e-6)
        }
    }

    func testGainOneIsBitExact() {
        let input = Buffers(channels: [2], frames: 3) { _, f, c in Float(f) * 0.37 + Float(c) * 0.011 }
        let output = Buffers(channels: [2], frames: 3)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        for f in 0..<3 { for c in 0..<2 { XCTAssertEqual(output.sample(0, f, c), input.sample(0, f, c)) } }
    }

    func testTwoMonoBuffersIntoOneMonoOutput() {
        // Wie Apple Music über das virtuelle Teams-Gerät (gemessen: 2 Eingangs-Puffer à 1 Kanal, 1 Ausgangs-Puffer à 1 Kanal).
        let input = Buffers(channels: [1, 1], frames: 2) { i, f, _ in Float(i + 1) * 0.1 + Float(f) * 0.01 }
        let output = Buffers(channels: [1], frames: 2)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        XCTAssertEqual(output.sample(0, 0), 0.1, accuracy: 1e-6, "erster Kanal")
        XCTAssertEqual(output.sample(0, 1), 0.11, accuracy: 1e-6)
    }

    func testMonoInputFillsBothStereoChannels() {
        let input = Buffers(channels: [1], frames: 2) { _, f, _ in Float(f + 1) * 0.1 }
        let output = Buffers(channels: [2], frames: 2)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        XCTAssertEqual(output.sample(0, 1, 0), 0.2, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 1, 1), 0.2, accuracy: 1e-6)
    }

    func testSeparateBuffersIntoInterleavedStereo() {
        let input = Buffers(channels: [1, 1], frames: 2) { i, _, _ in i == 0 ? 0.3 : 0.6 }
        let output = Buffers(channels: [2], frames: 2)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        XCTAssertEqual(output.sample(0, 0, 0), 0.3, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 0, 1), 0.6, accuracy: 1e-6)
    }

    func testGainRampsAcrossTheBuffer() {
        let input = Buffers(channels: [1], frames: 5) { _, _, _ in 0.5 }
        let output = Buffers(channels: [1], frames: 5)
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 0, gainEnd: 1)
        XCTAssertEqual(output.sample(0, 0), 0, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 2), 0.25, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 4), 0.5, accuracy: 1e-6)
    }

    func testNoInputGivesSilenceNotGarbage() {
        let input = Buffers(channels: [], frames: 0)
        let output = Buffers(channels: [2], frames: 3) { _, _, _ in 0.9 }
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        for f in 0..<3 { XCTAssertEqual(output.sample(0, f, 0), 0); XCTAssertEqual(output.sample(0, f, 1), 0) }
    }

    func testShorterInputIsPaddedWithSilence() {
        let input = Buffers(channels: [1], frames: 2) { _, _, _ in 0.5 }
        let output = Buffers(channels: [1], frames: 4) { _, _, _ in 0.9 }
        TapMixer.render(input: input.const, output: output.list.unsafeMutablePointer, gainStart: 1, gainEnd: 1)
        XCTAssertEqual(output.sample(0, 1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(output.sample(0, 3), 0, "kein Rest vom vorigen Puffer")
    }
}

extension TapMixerTests {
    func testHasSignalIsOnlyAYesNo() {
        let silent = Buffers(channels: [2], frames: 8)
        XCTAssertFalse(TapMixer.hasSignal(silent.const), "Nullen = keine Freigabe oder Stille")
        let sound = Buffers(channels: [2], frames: 8) { _, f, _ in f == 5 ? 0.001 : 0 }
        XCTAssertTrue(TapMixer.hasSignal(sound.const))
    }
}
