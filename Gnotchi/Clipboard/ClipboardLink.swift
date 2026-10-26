import AppKit
import CryptoKit
import LocalAuthentication
import Observation
import os

/// Zwischenablage-Verlauf (0.11.0, docs/SECURE-DESIGN.md G37–G41). Läuft nur, solange der Schalter an ist (ab Werk
/// aus). Liest `NSPasteboard.general` erst, wenn sich `changeCount` geändert hat; schreibt nur auf Michaels Klick.
/// Drückt selbst nie ⌘V – Einfügen nur über das Hilfsprogramm (G42), Gnotchi bleibt ohne Bedienungshilfen (G1).
/// Erkannte Geheimnisse: verdeckt, lose nach 5 Min. weg (G43). Protokoll ohne Inhalt, Titel oder Quell-App.
@MainActor
@Observable
final class ClipboardLink: NotchPart {

    @ObservationIgnored private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "zwischenablage")
    static let pollInterval: TimeInterval = 0.5
    static let vaultClearDelay: TimeInterval = 60
    static let pauseDuration: TimeInterval = 30 * 60

    @ObservationIgnored private let activity: ActivityModel
    @ObservationIgnored private let prefs: Preferences
    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChange = 0
    @ObservationIgnored private var hotKeyID: UInt32?
    @ObservationIgnored private var registeredHotKey: Preferences.HotKey?
    @ObservationIgnored private var vaultContext: LAContext?
    @ObservationIgnored private var vaultUnlockedAt: Date?
    @ObservationIgnored private var vaultLockTask: Task<Void, Never>?
    static var vaultOpenDuration: TimeInterval {
        #if DEBUG
        // Mess-Schalter nur in der Testfassung: `defaults write dev.mwlr.gnotchi debugVaultOpenSeconds 30`
        if let seconds = UserDefaults.standard.object(forKey: "debugVaultOpenSeconds") as? Double { return seconds }
        #endif
        return 5 * 60
    }
    /// Eigene bzw. erkannte vertrauliche Kopie in der Zwischenablage (Tresor G39, Geheimnis G43): `changeCount`,
    /// bei dem sie geleert wird – nur wenn bis dahin nichts anderes kopiert wurde.
    @ObservationIgnored private var sensitiveChange: Int?
    @ObservationIgnored private var sensitiveClearTask: Task<Void, Never>?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var lockObservers: [NSObjectProtocol] = []
    @ObservationIgnored lazy var panel = ClipboardPanelController(link: self)

    /// Geöffneter Speicher (nil = aus oder Schlüssel nicht verfügbar).
    private(set) var store: ClipboardStore?
    /// Fehler beim Start (für die Einstellungen), nie mit Inhalt.
    private(set) var startProblem: String?
    /// Tresor gerade entsperrt (für die Anzeige, 5 Min.).
    private(set) var vaultUnlocked = false

    init(activity: ActivityModel, prefs: Preferences, pasteboard: NSPasteboard = .general) {
        self.activity = activity
        self.prefs = prefs
        self.pasteboard = pasteboard
    }

    // MARK: - NotchPart

    func start() {
        guard store == nil else { return }
        do {
            store = try ClipboardStore(directory: ClipboardStore.defaultDirectory, key: ClipboardKeys.mainKey())
            startProblem = nil
        } catch {
            startProblem = String(localized: "Verlauf konnte nicht geöffnet werden (\(String(describing: error))).")
            Self.log.error("Start fehlgeschlagen: \(String(describing: error), privacy: .public)")
            return
        }
        lastChange = pasteboard.changeCount   // was vor dem Einschalten kopiert wurde, bleibt draußen
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        if prefs.clipboardPanelHotKey == nil { prefs.clipboardPanelHotKey = HotKeyCenter.defaultPanelHotKey() }
        registerHotKey()
        observeLock()
        activity.clipboard = self
        store?.secretsSince = prefs.clipboardSecretsSince
        store?.prune()
        pruneSecrets()
        // Nur Zahlen (G43): wie viele Geheimnisse offen in Sammlungen liegen, wie viele schon angeboten wurden.
        Self.log.notice("Geheimnisse in Sammlungen: \(self.store?.savedSecrets().count ?? 0, privacy: .public), angeboten: \(self.prefs.clipboardSecretsOffered, privacy: .public)")
        Self.log.notice("Zwischenablage an")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = nil
        lockObservers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        lockObservers.removeAll()
        clearSensitiveCopyIfUntouched()
        lockVault()
        panel.close()
        if activity.clipboard === self { activity.clipboard = nil }
        activity.clipboardActive = false
        store = nil   // entschlüsselte Inhalte aus dem Speicher
        Self.log.notice("Zwischenablage aus")
    }

    func recheck() {
        guard let store else { return }
        if store.secretsSince != prefs.clipboardSecretsSince {
            store.secretsSince = prefs.clipboardSecretsSince
            pruneSecrets()
        }
        guard registeredHotKey != prefs.clipboardPanelHotKey else { return }
        registerHotKey()
    }

    // MARK: - Mitlesen (G37)

    private func tick() {
        ticks += 1
        if ticks % 10 == 0 { pruneSecrets() }   // alle 5 s
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        if let own = sensitiveChange, own != change { sensitiveChange = nil; sensitiveClearTask?.cancel() }
        guard !prefs.isClipboardPaused, let store else { return }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let board = pasteboard
        let snapshot = ClipboardCapture.Snapshot(types: types, read: { board.data(forType: NSPasteboard.PasteboardType($0)) },
                                                 sourceBundleID: source)
        switch ClipboardCapture.decide(snapshot, isExcluded: { [prefs] in prefs.isClipboardExcluded($0) }) {
        case .skip(let reason):
            Self.log.debug("nicht übernommen: \(reason.rawValue, privacy: .public)")
        case .take(let payload, let kind):
            do {
                let entry = try store.add(payload, kind: kind, source: source)
                // Erkanntes Geheimnis (G43): System-Zwischenablage zum Ablauf leeren, wenn bis dahin unverändert.
                if store.secretKind(entry) != nil { scheduleSensitiveClear(change, after: ClipboardStore.secretLifetime) }
            } catch {
                Self.log.error("Speichern fehlgeschlagen: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Kopieren (nur auf Klick)

    /// Einfügen möglich (0.12.0, G42): nur über das verbundene Hilfsprogramm „Gnotchi Mitteilungen“ mit Freigabe.
    /// Sonst bleibt es beim Kopieren, Michael drückt selbst ⌘V.
    var canPaste: Bool { activity.notifyTrust == true }

    /// Hilfsprogramm drückt einmal ⌘V (G42). Nur aus Doppelklick/↵/⌘1–9 in der Seitenansicht, nach dem Schließen –
    /// kurz warten, bis die vorherige App wieder Tastatureingaben bekommt.
    func pasteAfterClose() {
        guard canPaste else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.canPaste else { return }
                self.activity.notifyCommand(.paste)
            }
        }
    }

    nonisolated static let pasteDelay: TimeInterval = 0.12

    /// Eintrag in die Zwischenablage legen. `plain` = nur reiner Text (⇧).
    func copy(_ entry: ClipEntry, plain: Bool) {
        guard let store, !entry.isVault, let payload = store.payload(entry) else { return }
        let secret = store.secretKind(entry) != nil
        write(payload, plain: plain, concealed: secret)
        store.touch(entry)
        if secret { scheduleSensitiveClear(pasteboard.changeCount, after: ClipboardStore.secretLifetime) }
    }

    /// Tresor-Eintrag: Touch ID (bzw. 5 Min. Wiederverwendung), vertraulich markiert, nach 60 s geleert (G39).
    func copyVault(_ entry: ClipEntry, done: @escaping @MainActor (Bool) -> Void = { _ in }) {
        unlockVault { [weak self] key in
            guard let self, let key, let store = self.store,
                  let payload = try? store.openVault(entry, vaultKey: key) else { return done(false) }
            self.write(payload, plain: true, concealed: true)
            self.scheduleSensitiveClear(self.pasteboard.changeCount, after: Self.vaultClearDelay)
            done(true)
        }
    }

    /// Tresor-Schlüssel holen. Touch ID blockiert – deshalb im Hintergrund, Ergebnis auf dem Hauptthread.
    /// Innerhalb von 5 Minuten nach der Bestätigung derselbe Kontext (kein Dialog), danach ein neuer (fragt).
    func unlockVault(_ completion: @escaping @MainActor (SymmetricKey?) -> Void) {
        if let at = vaultUnlockedAt, Date().timeIntervalSince(at) >= Self.vaultOpenDuration { lockVault() }
        let fresh = vaultContext == nil
        let context = vaultContext ?? ClipboardKeys.makeVaultContext()
        vaultContext = context
        let box = ContextBox(context: context)
        Task.detached {
            let key = try? ClipboardKeys.vaultKey(context: box.context)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if key == nil {
                    self.lockVault()
                } else if fresh || self.vaultUnlockedAt == nil {
                    self.vaultUnlockedAt = Date()
                    self.scheduleVaultLock()
                }
                self.vaultUnlocked = key != nil
                completion(key)
            }
        }
    }

    /// Sofort sperren (Knopf, Bildschirmsperre, Ruhezustand, nach 5 Minuten).
    func lockVault() {
        vaultLockTask?.cancel()
        vaultLockTask = nil
        vaultContext?.invalidate()
        vaultContext = nil
        vaultUnlockedAt = nil
        vaultUnlocked = false
    }

    private func scheduleVaultLock() {
        vaultLockTask?.cancel()
        vaultLockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.vaultOpenDuration))
            guard !Task.isCancelled else { return }
            self?.lockVault()
        }
    }

    private func write(_ payload: ClipPayload, plain: Bool, concealed: Bool) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if plain || concealed {
            item.setString(payload.plain, forType: .string)
        } else {
            for format in payload.formats { item.setData(format.data, forType: NSPasteboard.PasteboardType(format.type)) }
        }
        if concealed {
            item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        pasteboard.writeObjects([item])
        lastChange = pasteboard.changeCount   // die eigene Kopie nicht noch einmal aufnehmen
    }

    private func scheduleSensitiveClear(_ change: Int, after delay: TimeInterval) {
        sensitiveClearTask?.cancel()
        sensitiveChange = change
        sensitiveClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.clearSensitiveCopyIfUntouched()
        }
    }

    /// Nur leeren, wenn noch die vertrauliche Kopie drinliegt – hat Michael inzwischen etwas anderes kopiert, bleibt das.
    func clearSensitiveCopyIfUntouched() {
        sensitiveClearTask?.cancel()
        sensitiveClearTask = nil
        guard let own = sensitiveChange else { return }
        sensitiveChange = nil
        guard pasteboard.changeCount == own else { return }
        pasteboard.clearContents()
        lastChange = pasteboard.changeCount
    }

    // MARK: - Gespeicherte Geheimnisse (G43): einmal anbieten, nie automatisch löschen

    /// Anzahl offen gespeicherter Geheimnisse, wenn mehr als beim letzten Angebot – sonst 0 (kein Hinweis).
    var secretsToOffer: Int {
        _ = store?.revision
        guard let count = store?.savedSecrets().count, count > prefs.clipboardSecretsOffered else { return 0 }
        return count
    }

    /// „Später“: bis neue dazukommen nicht wieder fragen. Die Einträge bleiben verdeckt.
    func dismissSecretOffer() { prefs.clipboardSecretsOffered = store?.savedSecrets().count ?? 0 }

    /// „Alle in den Tresor“: erster Tresor (sonst neuer „Tresor“), einmal Touch ID, Titel = erkannte Art.
    func moveSavedSecretsToVault(done: @escaping @MainActor (Int?) -> Void) {
        guard let store else { return done(nil) }
        let list = store.savedSecrets()
        guard !list.isEmpty else { return done(0) }
        unlockVault { [weak self] key in
            guard let self, let key, let store = self.store else { return done(nil) }
            let vault = store.collections().first(where: \.isVault)
                ?? (try? store.createCollection(name: String(localized: "Tresor"), color: .red, symbol: "lock.fill",
                                                isVault: true))
            guard let vault else { return done(nil) }
            var moved = 0
            for entry in list {
                let title = store.title(entry) ?? store.secretKind(entry) ?? String(localized: "Schlüssel")
                if (try? store.moveToVault(entry, collection: vault, title: title, vaultKey: key)) != nil { moved += 1 }
            }
            self.prefs.clipboardSecretsOffered = store.savedSecrets().count
            Self.log.notice("\(moved, privacy: .public) gespeicherte Geheimnisse in den Tresor verschoben")
            done(moved)
        }
    }

    /// Abgelaufene lose Geheimnisse löschen (G43). Protokoll nur mit Zahl.
    private func pruneSecrets() {
        guard let removed = store?.pruneSecrets(), removed > 0 else { return }
        Self.log.notice("\(removed, privacy: .public) Geheimnis(se) abgelaufen und gelöscht")
    }

    // MARK: - Pause, Löschen

    var panelEdge: Preferences.PanelEdge { prefs.clipboardPanelEdge }
    var isPaused: Bool { prefs.isClipboardPaused }

    func pause() { prefs.clipboardPausedUntil = Date().addingTimeInterval(Self.pauseDuration) }
    func resume() { prefs.clipboardPausedUntil = nil }

    func clearHistory() { try? store?.clearHistory() }

    /// Alles weg inklusive Schlüssel (kryptografisches Löschen, G38). Danach Schalter aus.
    func resetEverything() {
        try? store?.eraseEverything()
        lockVault()
        store = nil
        try? ClipboardKeys.deleteAll()
        try? FileManager.default.removeItem(at: ClipboardStore.defaultDirectory)
        prefs.clipboard = false
    }

    // MARK: - Intern

    private func registerHotKey() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = prefs.clipboardPanelHotKey
        guard let hotKey = prefs.clipboardPanelHotKey else { return }
        hotKeyID = HotKeyCenter.shared.register(hotKey) { [weak self] in self?.panel.toggle() }
        if hotKeyID == nil { Self.log.error("Tastenkürzel nicht registriert") }
    }

    /// Bildschirmsperre, Ruhezustand, Benutzerwechsel → Tresor sofort zu (G39).
    private func observeLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            lockObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockVault() }
            })
        }
        lockObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockVault() }
            })
    }
}

/// `LAContext` ist nicht als `Sendable` markiert, Apple beschreibt ihn aber als threadsicher für genau diesen Zweck
/// (Abfrage im Hintergrund, Ergebnis auf dem Hauptthread).
private struct ContextBox: @unchecked Sendable {
    let context: LAContext
}
