import AppKit

/// Ersatzquelle (0.30.x): Spotify/Musik geben hörbar Ton aus, melden sich aber nicht bei MediaRemote
/// (gemessen 15.11.: macOS führt einen pausierten Browser als Now-Playing-Client). Dann fragt Gnotchi
/// die App selbst per AppleScript – derselbe Weg wie der Rückfall (G7), nur ergänzend zum Adapter.
/// Nur bei bereits erteilter Automation (`AutomationStatus`): nie ein neuer Dialog, nie ein Start der App.
extension NowPlayingModel {

    /// Takt der Prüfung, ob Ersatz nötig ist; gearbeitet wird nur, solange Spotify/Musik laufen.
    nonisolated static let assistInterval: TimeInterval = 3

    /// Welche App soll ersatzweise abgefragt werden? nil = keine.
    /// Nur wenn der Adapter nichts Spielendes meldet, die App hörbar ist und die Automation erlaubt ist.
    nonisolated static func assistTarget(adapterPlaying: Bool, audible: Set<String>,
                                         allowed: (String) -> Bool) -> String? {
        guard !adapterPlaying else { return nil }
        return AppleScriptSource.supported.first { audible.contains($0) && allowed($0) }
    }

    /// Hörbare Apps aus den Audio-Prozessen: Bundle-ID gleich oder Hilfsprozess (`<id>.helper`).
    nonisolated static func audibleSupported(_ processes: [MixerAudio.Process]) -> Set<String> {
        var result = Set<String>()
        for p in processes where p.outputting {
            guard let b = p.bundleID else { continue }
            if let id = AppleScriptSource.supported.first(where: { b == $0 || b.hasPrefix($0 + ".") }) { result.insert(id) }
        }
        return result
    }

    var fallbackActive: Bool { usingFallback || assistActive }

    func startAssistWatch() {
        guard assistTimer == nil else { return }
        let t = Timer(timeInterval: Self.assistInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.assistTick() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        assistTimer = t
    }

    func stopAssistWatch() {
        assistTimer?.invalidate()
        assistTimer = nil
        assistCandidate = nil
        assistChecking = false
        if assistActive { assistActive = false }
    }

    private func assistTick() {
        guard !usingFallback, !assistActive, !assistChecking else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard !running.isDisjoint(with: AppleScriptSource.supported) else { assistCandidate = nil; return }
        assistChecking = true
        Task { [weak self] in
            let audible = await Task.detached(priority: .utility) { Self.audibleSupported(MixerAudio.audioProcesses()) }.value
            self?.assistChecked(audible: audible)
        }
    }

    private func assistChecked(audible: Set<String>) {
        assistChecking = false
        guard timerRunning, !usingFallback, !assistActive else { return }
        let target = Self.assistTarget(adapterPlaying: adapterLast?.isPlaying == true, audible: audible) { id in
            AutomationStatus.shared.isAllowed(id)
        }
        // Zwei Treffer in Folge (~3 s): kurze Lücken beim Titelwechsel lösen nichts aus.
        guard let target, target == assistCandidate else { assistCandidate = target; return }
        assistCandidate = nil
        assistActive = true
        fallback.start()
    }

    private var timerRunning: Bool { assistTimer != nil }

    func endAssist() {
        guard assistActive else { return }
        assistActive = false
        assistCandidate = nil
        assistPausedSince = nil
        fallback.stop()
        receive(adapterLast)
    }

    func receiveFromAdapter(_ i: NowPlayingInfo?) {
        adapterLast = i
        if assistActive {
            // Meldet der Adapter selbst Wiedergabe, ist der Ersatz überflüssig; sonst bleibt die Ersatzanzeige.
            guard i?.isPlaying == true else { return }
            assistActive = false
            fallback.stop()
        }
        receive(i)
    }

    func receiveFromFallback(_ i: NowPlayingInfo?) {
        if usingFallback { return receive(i) }
        guard assistActive else { return }
        guard let i else { return endAssist() }
        if i.isPlaying { assistPausedSince = nil; return receive(i) }
        // Pause: die App noch kurz weiter zeigen (Pause-Anzeige, Tasten wirken auf sie), danach zurück zum Adapter.
        let since = assistPausedSince ?? Date()
        assistPausedSince = since
        if Date().timeIntervalSince(since) >= Self.assistPauseHold { endAssist() } else { receive(i) }
    }

    /// So lange bleibt die App nach „Pause“ im Ersatz, dann übernimmt wieder der Adapter.
    nonisolated static let assistPauseHold: TimeInterval = 10
}
