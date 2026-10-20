// SYNTHETISCH – Messwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Machbarkeit 0.2.0 (20.10.): Lassen sich Mikrofon, Kamera und Ausgabegeräte OHNE neue
// Berechtigung abfragen? Nur lesend. Gibt Zahlen und Übertragungsarten aus, keine App-Namen.
// Aufruf: swift spike/feature-probe.swift
import CoreAudio
import CoreMediaIO
import Foundation

func addr(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func u32(_ o: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var a = addr(s, scope); var v: UInt32 = 0; var n = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(o, &a, 0, nil, &n, &v) == noErr ? v : nil
}
func list(_ o: AudioObjectID, _ s: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = addr(s); var n: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(o, &a, 0, nil, &n) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(n) / MemoryLayout<AudioObjectID>.size)
    return AudioObjectGetPropertyData(o, &a, 0, nil, &n, &ids) == noErr ? ids : []
}
func streams(_ d: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
    var a = addr(kAudioDevicePropertyStreams, scope); var n: UInt32 = 0
    return AudioObjectGetPropertyDataSize(d, &a, 0, nil, &n) == noErr ? Int(n) / MemoryLayout<AudioStreamID>.size : 0
}
func fourcc(_ v: UInt32?) -> String {
    guard let v else { return "?" }
    let b = [24, 16, 8, 0].map { UInt8((v >> UInt32($0)) & 0xff) }
    return String(bytes: b, encoding: .ascii) ?? "\(v)"
}

let sys = AudioObjectID(kAudioObjectSystemObject)
let devices = list(sys, kAudioHardwarePropertyDevices)
let defOut = u32(sys, kAudioHardwarePropertyDefaultOutputDevice)
let defIn = u32(sys, kAudioHardwarePropertyDefaultInputDevice)
print("Audio-Geräte: \(devices.count)")
for d in devices {
    let ins = streams(d, kAudioObjectPropertyScopeInput), outs = streams(d, kAudioObjectPropertyScopeOutput)
    let running = u32(d, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 9
    print("  id \(d) transport=\(fourcc(u32(d, kAudioDevicePropertyTransportType))) in=\(ins) out=\(outs) läuftIrgendwo=\(running)\(d == defOut ? " [Standard-Ausgang]" : "")\(d == defIn ? " [Standard-Eingang]" : "")")
}
let procs = list(sys, kAudioHardwarePropertyProcessObjectList)
let micProcs = procs.filter { (u32($0, kAudioProcessPropertyIsRunningInput) ?? 0) != 0 }
print("Prozesse mit Audio: \(procs.count), davon Mikrofon aktiv: \(micProcs.count)")

// Kamera über CoreMediaIO
var ca = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                   mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                   mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var size: UInt32 = 0
let sysCam = CMIOObjectID(kCMIOObjectSystemObject)
if CMIOObjectGetPropertyDataSize(sysCam, &ca, 0, nil, &size) == noErr {
    var cams = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    _ = CMIOObjectGetPropertyData(sysCam, &ca, 0, nil, size, &used, &cams)
    print("Kameras: \(cams.count)")
    for c in cams {
        var ra = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                           mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                           mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        var v: UInt32 = 9; var got: UInt32 = 0
        let st = CMIOObjectGetPropertyData(c, &ra, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &v)
        print("  kamera \(c) läuftIrgendwo=\(v) status=\(st)")
    }
} else { print("Kameras: Abfrage gescheitert") }
