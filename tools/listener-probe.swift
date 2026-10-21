// Diagnose 21.10. (Ressourcenfund PrivacyMonitor): baut die Beobachter-Logik von PrivacyMonitor
// 1:1 nach und löst echte Geräteänderungen aus (öffentliches Aggregat-Gerät anlegen/entfernen).
// Misst je Runde: wie oft „Geräte geändert“ ankommt, Status beim Abmelden, und wie lange
// 2000 Anmelden/Abmelden-Paare dauern (wächst mit der internen Liste von Core Audio).
// Bauen: swiftc -O tools/listener-probe.swift -o /tmp/listener-probe ; Lauf: /tmp/listener-probe <runden>
import CoreAudio
import Foundation

struct L { let obj: AudioObjectID; let addr: AudioObjectPropertyAddress; let block: AudioObjectPropertyListenerBlock }
var listeners: [L] = []
var devicesChangedCalls = 0
var removeFailures = 0

func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}
func objectList(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = addr(s); var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}
func hasInput(_ d: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(d, &a, 0, nil, &size) == noErr && size > 0
}
func add(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector, _ action: @escaping () -> Void) {
    var a = addr(s)
    let b: AudioObjectPropertyListenerBlock = { _, _ in action() }
    if AudioObjectAddPropertyListenerBlock(obj, &a, .main, b) == noErr { listeners.append(L(obj: obj, addr: a, block: b)) }
}
func removeAll() {
    for l in listeners { var a = l.addr; if AudioObjectRemovePropertyListenerBlock(l.obj, &a, .main, l.block) != noErr { removeFailures += 1 } }
    listeners.removeAll()
}
// Modus (2. Argument): sofort = wie PrivacyMonitor heute · verzoegert = Tausch per main.async ·
// einmal = System-Beobachter nur einmal anmelden, Geräte-Beobachter verzögert tauschen
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "sofort"
var deviceListeners: [L] = []
func registerSystem() {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    add(sys, kAudioHardwarePropertyDevices) { devicesChanged() }
    add(sys, kAudioHardwarePropertyProcessObjectList) {}
}
func registerDevices() {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    for d in objectList(sys, kAudioHardwarePropertyDevices) where hasInput(d) { add(d, kAudioDevicePropertyDeviceIsRunningSomewhere) {} }
}
func register() { registerSystem(); registerDevices() }
func refreshDevicesOnly() {
    // Nur Geräte-Beobachter (alles ab Index 2) tauschen, System-Beobachter bleiben.
    let keep = Array(listeners.prefix(2)); let drop = Array(listeners.dropFirst(2))
    for l in drop { var a = l.addr; if AudioObjectRemovePropertyListenerBlock(l.obj, &a, .main, l.block) != noErr { removeFailures += 1 } }
    listeners = keep; registerDevices()
}
var pending = false
func devicesChanged() {
    devicesChangedCalls += 1
    switch mode {
    case "verzoegert":
        guard !pending else { return }; pending = true
        DispatchQueue.main.async { pending = false; removeAll(); register() }
    case "einmal":
        guard !pending else { return }; pending = true
        DispatchQueue.main.async { pending = false; refreshDevicesOnly() }
    default:
        removeAll(); register()
    }
}

func addRemoveCost() -> Double {   // ms für 2000 Paare auf dem System-Objekt
    let t = Date(); let sys = AudioObjectID(kAudioObjectSystemObject)
    for _ in 0..<2000 {
        var a = addr(kAudioHardwarePropertyDefaultInputDevice); let b: AudioObjectPropertyListenerBlock = { _, _ in }
        AudioObjectAddPropertyListenerBlock(sys, &a, .main, b); AudioObjectRemovePropertyListenerBlock(sys, &a, .main, b)
    }
    return Date().timeIntervalSince(t) * 1000
}
func toggleAggregate() {
    let uid = "dev.mwlr.gnotchi.probe.\(UUID().uuidString)"
    let desc: [String: Any] = [kAudioAggregateDeviceUIDKey: uid, kAudioAggregateDeviceNameKey: "Gnotchi-Probe (wird entfernt)",
                               kAudioAggregateDeviceIsPrivateKey: 0]
    var dev: AudioObjectID = 0
    guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &dev) == noErr else { print("Aggregat anlegen fehlgeschlagen"); exit(2) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    AudioHardwareDestroyAggregateDevice(dev)
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
}

let rounds = Int(CommandLine.arguments.dropFirst().first ?? "10") ?? 10
register()
print(String(format: "Start: %d Beobachter, Kosten %.1f ms", listeners.count, addRemoveCost()))
for r in 1...rounds {
    let before = devicesChangedCalls
    toggleAggregate()
    let quiet = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "still"
    if quiet {
        print("Runde \(r): Geräte-geändert-Aufrufe \(devicesChangedCalls - before), Beobachter \(listeners.count), Abmelde-Fehler \(removeFailures)")
    } else {
        print(String(format: "Runde %2d: Geräte-geändert-Aufrufe %d, Beobachter %d, Abmelde-Fehler %d, Kosten %.1f ms",
                     r, devicesChangedCalls - before, listeners.count, removeFailures, addRemoveCost()))
    }
}
print(String(format: "Ende: Kosten %.1f ms", addRemoveCost()))
