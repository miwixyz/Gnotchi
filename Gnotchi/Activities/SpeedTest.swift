import Foundation

/// Geschwindigkeitstest (0.28.0, SECURE-DESIGN G51): startet das System-Programm `networkQuality` – nur auf Klick, mit
/// festem Pfad und festen Argumenten, ohne Shell, ein Lauf gleichzeitig, mit Zeitgrenze und Ausgabegrenze. Das Ergebnis
/// steht nur im Arbeitsspeicher. **Verbindung nach außen:** Apples Testserver, nur während des Laufs.
@MainActor
@Observable
final class SpeedTest {

    struct Result: Equatable, Sendable {
        let downMbps: Double
        let upMbps: Double
        let latencyMs: Double?
        /// Antwortfähigkeit in „Umläufen pro Minute“ (RPM, Apples Maß).
        let responsiveness: Int?
    }

    enum State: Equatable {
        case idle, running, done(Result), failed(String)
    }

    private(set) var state: State = .idle

    nonisolated static let path = "/usr/bin/networkQuality"
    /// `-c` maschinenlesbar, `-M 20` höchstens 20 Sekunden Laufzeit (gemessen 15.11.: ohne Grenze 45 s und über 1 GB).
    nonisolated static let arguments = ["-c", "-M", "20"]
    nonisolated static let timeoutSeconds = 60
    nonisolated static let maxOutput = 65_536

    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard state != .running else { return }
        state = .running
        task = Task { [weak self] in
            // Auf einer eigenen Warteschlange, nicht im Thread-Pool von Swift Concurrency: `execute` blockiert bis zu 60 s.
            let outcome = await withCheckedContinuation { (c: CheckedContinuation<Outcome, Never>) in
                DispatchQueue.global(qos: .utility).async { c.resume(returning: Self.execute()) }
            }
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .output(let data):
                if let r = Self.parse(data) { self.state = .done(r) } else { self.state = .failed("Kein Ergebnis erhalten") }
            case .failed(let why):
                self.state = .failed(why)
            }
        }
    }

    /// Ergebnis wegwerfen (Insel zu, andere Ansicht). Ein laufender Test läuft zu Ende, sein Ergebnis bleibt dann stehen.
    func clear() {
        if state != .running { state = .idle }
    }

    // MARK: Reine Teile (getestet)

    /// Aus dem JSON von `networkQuality -c`: `dl_throughput`/`ul_throughput` in Bit/s, `base_rtt` in ms, `responsiveness` in RPM.
    nonisolated static func parse(_ data: Data) -> Result? {
        guard data.count <= maxOutput,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dl = number(obj["dl_throughput"]), let ul = number(obj["ul_throughput"]) else { return nil }
        return Result(downMbps: dl / 1_000_000, upMbps: ul / 1_000_000,
                      latencyMs: number(obj["base_rtt"]),
                      responsiveness: number(obj["responsiveness"]).map { Int($0.rounded()) })
    }

    /// Nur endliche, nicht negative und plausibel große Zahlen (1 Tbit/s als Obergrenze).
    nonisolated private static func number(_ v: Any?) -> Double? {
        guard let n = (v as? NSNumber)?.doubleValue, n.isFinite, n >= 0, n <= 1_000_000_000_000 else { return nil }
        return n
    }

    /// „187 Mbit/s“; unter 10 mit einer Nachkommastelle.
    nonisolated static func mbpsText(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") : String(Int(v.rounded()))
    }

    // MARK: Prozess

    enum Outcome: Sendable {
        case output(Data)
        case failed(String)
    }

    /// Blockierend, auf einem Hintergrund-Thread. Fester Pfad, feste Argumente, keine Shell, kein Eingang, Fehlerausgabe verworfen.
    nonisolated static func execute() -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .failed("Der Test ließ sich nicht starten") }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds), execute: killer)
        var data = Data()
        let reader = out.fileHandleForReading
        while let chunk = try? reader.read(upToCount: 4096), !chunk.isEmpty {
            data.append(chunk)
            if data.count > maxOutput {
                p.terminate()
                p.waitUntilExit()   // kein Zombie-Prozess
                killer.cancel()
                return .failed("Unerwartet lange Ausgabe")
            }
        }
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return .failed("Kein Netz oder der Test wurde abgebrochen") }
        return .output(data)
    }
}
