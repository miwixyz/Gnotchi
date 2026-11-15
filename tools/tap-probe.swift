// Spike 15.11. (Mixer-Spike, specs/2026-11-15-gnotchi-lautstaerkemixer-meeting-leiser.md, Stufe 2):
// Geht ein Lautstärkeregler je App über Core-Audio-Prozess-Taps (macOS 14.2+)? Misst Freigabe, Latenz, Aussetzer, Last.
// Nichts davon ist Gnotchi-Code und nichts wird gespeichert: Der Ton läuft nur im Speicher durch dieses Programm.
//
// Bauen: swiftc -O -swift-version 5 tools/tap-probe.swift -o /tmp/tap-probe
// Lauf:  /tmp/tap-probe liste                       zeigt alle Audio-Prozesse (legt KEINEN Tap an, keine Freigabe nötig)
//        /tmp/tap-probe lesen  com.spotify [sek]    Tap NUR LESEND (Original bleibt hörbar): prüft Freigabe und Pegel
//        /tmp/tap-probe regeln com.spotify [sek]    Tap schaltet das Original stumm und spielt es mit Verstärkung 1,0 → 0,3 → 1,0 ab
//
// Vorsicht „regeln“: Solange der Tap läuft, hört man Spotify nur über dieses Programm. Endet es (auch Strg-C, kill),
// räumt macOS den Tap mit dem Prozess weg und der Ton ist wieder normal.
import AudioToolbox
import CoreAudio
import Foundation

// MARK: Core-Audio-Hilfen

func addr(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func getU32(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
    var a = addr(s, scope), v: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
}

func getString(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> String? {
    var a = addr(s), v: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
    return v.takeRetainedValue() as String
}

func ids(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> [AudioObjectID] {
    var a = addr(s), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &out) == noErr else { return [] }
    return out
}

struct AudioProc {
    let object: AudioObjectID
    let pid: Int32
    let bundle: String
    let outputRunning: Bool
}

func audioProcesses() -> [AudioProc] {
    ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).map { o in
        AudioProc(object: o, pid: Int32(getU32(o, kAudioProcessPropertyPID) ?? 0),
                  bundle: getString(o, kAudioProcessPropertyBundleID) ?? "?",
                  outputRunning: (getU32(o, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0)
    }
}

func fail(_ what: String, _ status: OSStatus) -> Never {
    print("FEHLER \(what): OSStatus \(status) (\(fourCC(status)))")
    exit(2)
}

func fourCC(_ s: OSStatus) -> String {
    let n = UInt32(bitPattern: s)
    let b = [UInt8((n >> 24) & 255), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]
    return b.allSatisfy { $0 >= 32 && $0 < 127 } ? String(decoding: b, as: UTF8.self) : "—"
}

// MARK: Argumente

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "liste"
let prefix = args.count > 2 ? args[2] : "com.spotify"
let seconds = args.count > 3 ? max(5, min(60, Double(args[3]) ?? 15)) : 15
/// Optionen (nach den festen Argumenten): `--ziel=Gerätename` = Wiedergabe auf diesem Gerät statt dem Standard-Ausgang,
/// `--geraetetap` = Tap nur auf dem Gerät, auf dem der Prozess spielt (Geräte-UID + Stream) statt über alle Geräte.
let ziel = args.first { $0.hasPrefix("--ziel=") }.map { String($0.dropFirst(7)) }
let deviceTap = args.contains("--geraetetap")

/// Ausgabegeräte, die ein Prozess gerade benutzt (`kAudioProcessPropertyDevices`, Ausgabe): Name des Geräts.
/// Liest nur eine Eigenschaft, legt keinen Tap an, braucht keine Freigabe.
func outputDevices(of o: AudioObjectID) -> [String] {
    var a = addr(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(o, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var d = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(o, &a, 0, nil, &size, &d) == noErr else { return [] }
    return d.map { getString($0, kAudioObjectPropertyName) ?? "Gerät \($0)" }
}

/// App hinter einem Prozess (Browser-Helfer → die Browser-App): Name des äußersten .app im Programmpfad.
func appName(pid: Int32) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return "?" }
    let path = String(cString: buf)
    guard let r = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards) else { return (path as NSString).lastPathComponent }
    return ((String(path[..<r.upperBound]).replacingOccurrences(of: ".app/", with: ".app")) as NSString).lastPathComponent
}

let procs = audioProcesses()
print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(procs.count) Audio-Prozesse")
for p in procs.sorted(by: { $0.outputRunning && !$1.outputRunning }) {
    let dev = outputDevices(of: p.object)
    print(String(format: "  %@ pid %6d  %@  [%@]%@", p.outputRunning ? "▶︎" : " ", p.pid, p.bundle, appName(pid: p.pid),
                 dev.isEmpty ? "" : "  → " + dev.joined(separator: ", ")))
}
let outs = ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).filter {
    var a = addr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput); var s: UInt32 = 0
    return AudioObjectGetPropertyDataSize($0, &a, 0, nil, &s) == noErr && s > 0
}
print("Ausgabegeräte: " + outs.map { getString($0, kAudioObjectPropertyName) ?? "?" }.joined(separator: " · "))
if mode == "liste" { exit(0) }
guard mode == "lesen" || mode == "regeln" else { print("Modus: liste | lesen | regeln"); exit(1) }

let targets = procs.filter { $0.bundle.lowercased().hasPrefix(prefix.lowercased()) }
guard !targets.isEmpty else { print("Kein Audio-Prozess mit Kennung „\(prefix)…“. Läuft die App?"); exit(1) }
print("Tap auf: " + targets.map { "\($0.bundle)#\($0.pid)" }.joined(separator: ", ") + " · Modus \(mode) · \(Int(seconds)) s")
if !targets.contains(where: \.outputRunning) { print("HINWEIS: Keiner dieser Prozesse gibt gerade Ton aus – Spotify abspielen und neu starten.") }

// MARK: Tap + privates Aggregat-Gerät

/// Geräte-UID, auf der der Ziel-Prozess gerade spielt (für den Geräte-Tap und als Standard-Wiedergabeweg).
func uidOfProcessDevice(_ o: AudioObjectID) -> String? {
    var a = addr(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput), size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(o, &a, 0, nil, &size) == noErr, size > 0 else { return nil }
    var d = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(o, &a, 0, nil, &size, &d) == noErr, let first = d.first else { return nil }
    return getString(first, kAudioDevicePropertyDeviceUID)
}
let procDeviceUID = targets.lazy.compactMap { uidOfProcessDevice($0.object) }.first
let desc: CATapDescription
if deviceTap, let uid = procDeviceUID {
    desc = CATapDescription(__processes: targets.map { NSNumber(value: $0.object) }, andDeviceUID: uid, withStream: 0)
    print("Geräte-Tap auf \(uid), Stream 0")
} else {
    desc = CATapDescription(stereoMixdownOfProcesses: targets.map(\.object))
}
desc.name = "Gnotchi tap-probe"
desc.uuid = UUID()
desc.isPrivate = true
desc.muteBehavior = mode == "regeln" ? .mutedWhenTapped : .unmuted

var tapID = AudioObjectID(kAudioObjectUnknown)
var st = AudioHardwareCreateProcessTap(desc, &tapID)
if st != noErr { fail("AudioHardwareCreateProcessTap (Freigabe „Audio-Aufnahme“ fehlt?)", st) }

func deviceNamed(_ name: String) -> AudioObjectID? {
    ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).first { getString($0, kAudioObjectPropertyName) == name }
}
var outDev = getU32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
if let ziel {
    guard let z = deviceNamed(ziel) else { _ = AudioHardwareDestroyProcessTap(tapID); print("Kein Gerät „\(ziel)“"); exit(1) }
    outDev = z
    print("Wiedergabe auf „\(ziel)“ statt dem Standard-Ausgang")
}
guard outDev != 0, let outUID = getString(outDev, kAudioDevicePropertyDeviceUID) else { print("Kein Ausgabegerät"); exit(2) }
let outName = getString(outDev, kAudioObjectPropertyName) ?? outUID

let aggUID = UUID().uuidString
let dict: [String: Any] = [
    kAudioAggregateDeviceNameKey: "Gnotchi tap-probe",
    kAudioAggregateDeviceUIDKey: aggUID,
    kAudioAggregateDeviceMainSubDeviceKey: outUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
]
var aggID = AudioObjectID(kAudioObjectUnknown)
st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
if st != noErr { _ = AudioHardwareDestroyProcessTap(tapID); fail("AudioHardwareCreateAggregateDevice", st) }

// Format des Taps und Ausgabe-Eckwerte (für die Latenz-Rechnung)
var fmt = AudioStreamBasicDescription()
var fa = addr(kAudioTapPropertyFormat), fsize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
_ = AudioObjectGetPropertyData(tapID, &fa, 0, nil, &fsize, &fmt)
let rate = fmt.mSampleRate > 0 ? fmt.mSampleRate : 48_000
let bufFrames = Double(getU32(aggID, kAudioDevicePropertyBufferFrameSize) ?? 0)
let devLatency = Double(getU32(outDev, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput) ?? 0)
let safety = Double(getU32(outDev, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput) ?? 0)
let tapLatency = Double(getU32(tapID, kAudioDevicePropertyLatency) ?? 0)
print("Ausgabe: \(outName) · Tap-Format \(Int(rate)) Hz, \(fmt.mChannelsPerFrame) Kanäle, \(fmt.mBitsPerChannel) Bit, Flags \(fmt.mFormatFlags)")
print(String(format: "Latenz-Bausteine: Puffer %.0f + Gerät %.0f + Sicherheit %.0f + Tap %.0f Frames = %.1f ms (Rechnung, nicht gemessen)",
             bufFrames, devLatency, safety, tapLatency, (bufFrames + devLatency + safety + tapLatency) / rate * 1000))

// MARK: Audio-Rückruf

final class Meter: @unchecked Sendable {   // Spike: Zähler ohne Schloss, nur von einem Thread beschrieben
    var calls = 0, frames = 0, nonzero = 0, samples = 0, xruns = 0
    var peak: Float = 0, sumSq: Double = 0
    var lastHost: UInt64 = 0, maxGap: Double = 0, sumGap: Double = 0
    var lastGain: Float = 1, target: Float = 1
    var firstCall: UInt64 = 0
    var latSum = 0.0, latMax = 0.0, latMin = Double.infinity, latCount = 0   // Eingang → Ausgabe laut Zeitstempeln (ms)
    var inBuffers = 0, outBuffers = 0, inChannels = 0, outChannels = 0
}
let meter = Meter()
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func seconds(_ h: UInt64) -> Double { Double(h) * Double(tb.numer) / Double(tb.denom) / 1e9 }
let writes = mode == "regeln"
let nominal = bufFrames > 0 ? bufFrames / rate : 0.01

var proc: AudioDeviceIOProcID?
let q = DispatchQueue(label: "tap-probe.io", qos: .userInteractive)
st = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, q) { _, inData, inTime, outData, outTime in
    let m = meter
    if inTime.pointee.mHostTime != 0, outTime.pointee.mHostTime > inTime.pointee.mHostTime {
        let ms = seconds(outTime.pointee.mHostTime - inTime.pointee.mHostTime) * 1000
        m.latSum += ms; m.latMax = max(m.latMax, ms); m.latMin = min(m.latMin, ms); m.latCount += 1
    }
    let now = mach_absolute_time()
    if m.calls == 0 { m.firstCall = now }
    if m.lastHost != 0 {
        let gap = seconds(now - m.lastHost)
        m.sumGap += gap; m.maxGap = max(m.maxGap, gap)
        if nominal > 0, gap > nominal * 1.6 { m.xruns += 1 }
    }
    m.lastHost = now; m.calls += 1

    let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
    let outs = UnsafeMutableAudioBufferListPointer(outData)
    m.inBuffers = ins.count; m.outBuffers = outs.count
    m.inChannels = ins.first.map { Int($0.mNumberChannels) } ?? 0
    m.outChannels = outs.first.map { Int($0.mNumberChannels) } ?? 0

    // Verstärkung gleitet über den Puffer vom letzten zum neuen Zielwert (kein Knacken beim Umschalten)
    let g0 = m.lastGain, g1 = m.target
    m.lastGain = g1
    for i in 0..<max(ins.count, outs.count) {
        let inB = i < ins.count ? ins[i] : nil, outB = i < outs.count ? outs[i] : nil
        let n = min(Int(inB?.mDataByteSize ?? 0), Int(outB?.mDataByteSize ?? 0)) / MemoryLayout<Float>.size
        let src = inB?.mData?.assumingMemoryBound(to: Float.self)
        let dst = outB?.mData?.assumingMemoryBound(to: Float.self)
        if let src {
            let count = Int(inB!.mDataByteSize) / MemoryLayout<Float>.size
            for k in 0..<count {
                let v = src[k]
                if v != 0 { m.nonzero += 1 }
                m.peak = max(m.peak, abs(v)); m.sumSq += Double(v * v)
            }
            m.samples += count; m.frames += count / max(1, m.inChannels)
        }
        if let dst {
            if writes, let src {
                for k in 0..<n {
                    let t = n > 1 ? Float(k) / Float(n - 1) : 1
                    dst[k] = src[k] * (g0 + (g1 - g0) * t)
                }
            } else {
                for k in 0..<(Int(outB!.mDataByteSize) / MemoryLayout<Float>.size) { dst[k] = 0 }
            }
        }
    }
}
if st != noErr { _ = AudioHardwareDestroyAggregateDevice(aggID); _ = AudioHardwareDestroyProcessTap(tapID); fail("AudioDeviceCreateIOProcIDWithBlock", st) }

var cleaned = false
func cleanup() {
    guard !cleaned else { return }
    cleaned = true
    if let proc { _ = AudioDeviceStop(aggID, proc); _ = AudioDeviceDestroyIOProcID(aggID, proc) }
    _ = AudioHardwareDestroyAggregateDevice(aggID)
    _ = AudioHardwareDestroyProcessTap(tapID)
}
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    s.setEventHandler { cleanup(); print("abgebrochen, Tap entfernt"); exit(130) }
    s.resume()
}

var cpu0 = rusage(); getrusage(RUSAGE_SELF, &cpu0)
let wall0 = Date()
st = AudioDeviceStart(aggID, proc)
if st != noErr { cleanup(); fail("AudioDeviceStart", st) }
print(writes ? "▶︎ läuft: \(Int(seconds)) s – Original ist stumm, Ton kommt durch dieses Programm. Phasen: 1,0 → 0,3 → 1,0"
             : "▶︎ läuft: \(Int(seconds)) s – nur lesend, Spotify bleibt normal hörbar")

// Phasen: erstes Drittel 1,0 · mittleres 0,3 · letztes 1,0
let t0 = Date()
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: .milliseconds(100))
var phaseShown = -1
timer.setEventHandler {
    let el = Date().timeIntervalSince(t0)
    let phase = el < seconds / 3 ? 0 : (el < seconds * 2 / 3 ? 1 : 2)
    meter.target = phase == 1 ? 0.3 : 1.0
    if phase != phaseShown { phaseShown = phase; print(String(format: "  %.1f s  Phase %d, Verstärkung %.1f", el, phase + 1, meter.target)) }
    if el >= seconds {
        timer.cancel()
        let wall = Date().timeIntervalSince(wall0)
        var cpu1 = rusage(); getrusage(RUSAGE_SELF, &cpu1)
        func tv(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        let cpu = (tv(cpu1.ru_utime) + tv(cpu1.ru_stime)) - (tv(cpu0.ru_utime) + tv(cpu0.ru_stime))
        cleanup()
        let rms = meter.samples > 0 ? sqrt(meter.sumSq / Double(meter.samples)) : 0
        print("\n=== Ergebnis (\(mode)) ===")
        print("Rückrufe: \(meter.calls) in \(String(format: "%.1f", wall)) s · Ø Abstand \(String(format: "%.2f", meter.calls > 1 ? meter.sumGap / Double(meter.calls - 1) * 1000 : 0)) ms (Soll \(String(format: "%.2f", nominal * 1000))) · größter \(String(format: "%.2f", meter.maxGap * 1000)) ms · Aussetzer-Verdacht (>1,6× Soll): \(meter.xruns)")
        if meter.latCount > 0 {
            print(String(format: "Latenz laut Zeitstempeln (Eingang → Ausgabe): Ø %.1f ms · kleinste %.1f · größte %.1f ms (%d Rückrufe)",
                         meter.latSum / Double(meter.latCount), meter.latMin, meter.latMax, meter.latCount))
        }
        print("Puffer: \(meter.inBuffers) Eingang (\(meter.inChannels) Kanäle) / \(meter.outBuffers) Ausgang (\(meter.outChannels) Kanäle)")
        print(String(format: "Eingangspegel: Spitze %.3f · Effektivwert %.4f · Samples ≠ 0: %d von %d", meter.peak, rms, meter.nonzero, meter.samples))
        print(String(format: "Last: %.2f %% eines Kerns (CPU %.2f s in %.1f s)", cpu / wall * 100, cpu, wall))
        if meter.samples > 0, meter.nonzero == 0 {
            print("→ Alles Stille. Entweder spielt nichts, oder die Freigabe „Audio-Aufnahme“ fehlt (macOS liefert dann Nullen, keinen Fehler).")
        } else if meter.samples > 0 { print("→ Ton kommt an: Freigabe vorhanden, Tap funktioniert.") }
        print("Tap und Aggregat-Gerät entfernt. Spotify jetzt wieder normal hörbar?")
        exit(0)
    }
}
timer.resume()
dispatchMain()
