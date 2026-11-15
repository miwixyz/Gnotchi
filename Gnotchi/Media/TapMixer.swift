import CoreAudio
import Foundation

/// Rechenkern des Mixers Stufe 2 (G55): Verstärkung, Weichbegrenzer und das Kopieren zwischen den Puffern des Taps und des Ausgabegeräts.
/// Reine Funktionen ohne Speicherzuweisung im Aufruf (Echtzeit-Thread), getestet mit selbst gebauten Puffern (`TapMixerTests`).
/// Der Ton bleibt im Arbeitsspeicher: nichts wird gespeichert, gesendet oder gemessen (kein Pegel, kein Spektrum).
enum TapMixer {
    /// 0…200 %.
    nonisolated static let gainRange: ClosedRange<Float> = 0...2
    /// Oberhalb dieser Amplitude beginnt der Weichbegrenzer.
    nonisolated static let kneeStart: Float = 0.8

    nonisolated static func clamp(_ g: Float) -> Float {
        g.isFinite ? min(gainRange.upperBound, max(gainRange.lowerBound, g)) : 1
    }

    /// Ein Tap lohnt nur, wenn der Regler nicht auf 100 % steht (Entwurf C): bei 100 % spielt die App direkt.
    nonisolated static func needsTap(_ g: Float) -> Bool { abs(clamp(g) - 1) > 0.01 }

    /// Weichbegrenzer: bis `kneeStart` unverändert, darüber gleitend auf höchstens 1,0 (stetig, monoton, nie darüber).
    nonisolated static func limit(_ x: Float) -> Float {
        let a = abs(x)
        guard a > kneeStart else { return x }
        let room = 1 - kneeStart
        let y = kneeStart + room * tanh((a - kneeStart) / room)
        return x < 0 ? -y : y
    }

    /// Eine Stichprobe: bei g ≤ 1 nur Multiplikation (bitgenau skaliert), darüber mit Begrenzer.
    @inline(__always)
    nonisolated static func scaled(_ x: Float, _ g: Float) -> Float { g <= 1 ? x * g : limit(x * g) }

    /// Steht irgendwo im Eingang ein Wert ≠ 0? Nur ein Wahrheitswert (kein Pegel, kein Spektrum): Ohne Freigabe „Audio-Aufnahme“
    /// liefert macOS Nullen statt eines Fehlers, das erkennt der Tap-Motor daran.
    nonisolated static func hasSignal(_ input: UnsafePointer<AudioBufferList>) -> Bool {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        for b in ins {
            guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<(Int(b.mDataByteSize) / MemoryLayout<Float>.size) where p[i] != 0 { return true }
        }
        return false
    }

    /// Summe der Kanäle aller Puffer einer Liste.
    nonisolated static func channelCount(_ list: UnsafePointer<AudioBufferList>) -> Int {
        let l = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var n = 0
        for b in l { n += Int(b.mNumberChannels) }
        return n
    }

    /// Kopiert den Eingang mit gleitender Verstärkung (`g0` am Anfang des Puffers, `g1` am Ende) auf den Ausgang.
    /// Kanal `c` des Ausgangs liest Kanal `c % Eingangskanäle` des Eingangs (Mono → alle Kanäle, Stereo → Mono: erster Kanal).
    /// Puffer dürfen interleaved (mehrere Kanäle in einem Puffer) oder getrennt (ein Kanal je Puffer) sein. Ohne Eingang: Stille.
    nonisolated static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                                   gainStart g0: Float, gainEnd g1: Float) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        let inChannels = channelCount(input)
        var outChannel = 0
        for ob in outs {
            let oc = Int(ob.mNumberChannels)
            guard let odata = ob.mData?.assumingMemoryBound(to: Float.self), oc > 0 else { outChannel += oc; continue }
            let frames = Int(ob.mDataByteSize) / (MemoryLayout<Float>.size * oc)
            for c in 0..<oc {
                // Quelle: Eingangskanal (outChannel + c) % inChannels → Puffer und Kanal darin
                var wanted = inChannels > 0 ? (outChannel + c) % inChannels : -1
                var src: UnsafeMutablePointer<Float>?
                var stride = 1, offset = 0, inFrames = 0
                if wanted >= 0 {
                    for ib in ins {
                        let n = Int(ib.mNumberChannels)
                        if wanted < n {
                            src = ib.mData?.assumingMemoryBound(to: Float.self)
                            stride = n
                            offset = wanted
                            inFrames = n > 0 ? Int(ib.mDataByteSize) / (MemoryLayout<Float>.size * n) : 0
                            break
                        }
                        wanted -= n
                    }
                }
                for f in 0..<frames {
                    guard let src, f < inFrames else { odata[f * oc + c] = 0; continue }
                    let t = frames > 1 ? Float(f) / Float(frames - 1) : 1
                    odata[f * oc + c] = scaled(src[f * stride + offset], g0 + (g1 - g0) * t)
                }
            }
            outChannel += oc
        }
    }
}
