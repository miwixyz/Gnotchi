import AppKit
import Carbon.HIToolbox
import os

/// Als reinen Text einfügen per Kürzel (SECURE-DESIGN G60). Reine Hilfsfunktionen über eine Zwischenablage –
/// testbar mit einer eigenen, benannten Zwischenablage statt `NSPasteboard.general`.
enum PlainPaste {

    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Größere Momentaufnahmen werden nicht gehalten: reiner Text wird eingefügt, das Original nicht zurückgeholt.
    static let maxSnapshotBytes = 50_000_000

    /// Inhalt vor dem Umwandeln, nur im Arbeitsspeicher (G60). `items == nil` = zu groß zum Zurückholen.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]?
        /// Passwort-App, Tresor (G39) oder erkanntes Geheimnis (G43): wird nie zurückgeschrieben, sondern geleert.
        let concealed: Bool
    }

    static func capture(_ pasteboard: NSPasteboard, limit: Int = maxSnapshotBytes) -> Snapshot {
        let items = pasteboard.pasteboardItems ?? []
        let concealed = items.contains { $0.types.contains(concealedType) }
        var total = 0
        var maps: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                total += data.count
                if total > limit { return Snapshot(items: nil, concealed: concealed) }
                map[type] = data
            }
            maps.append(map)
        }
        return Snapshot(items: maps, concealed: concealed)
    }

    /// Nur reiner Text, als Zwischenstand markiert (kein Verlaufseintrag, auch nicht in fremden Verlaufs-Apps).
    static func writePlain(_ text: String, concealed: Bool, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: transientType)
        if concealed { item.setData(Data(), forType: concealedType) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    /// Original zurück – ebenfalls als Zwischenstand markiert, sonst landete es erneut im Verlauf.
    static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        let objects = items.compactMap { map -> NSPasteboardItem? in
            guard !map.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in map { item.setData(data, forType: type) }
            item.setData(Data(), forType: transientType)
            return item
        }
        pasteboard.clearContents()
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
    }
}

/// Kürzel „Als reinen Text einfügen“ (G60): eigener Schalter, ab Werk aus, unabhängig vom Verlauf (G37).
/// Liest die Zwischenablage nur beim Tastendruck. Einfügen über das Hilfsprogramm (G42), Gnotchi drückt nichts selbst.
@MainActor
final class PlainPasteLink: NotchPart {

    enum Outcome: String {
        case busy = "verworfen: läuft schon"
        case again = "nochmal eingefügt"
        case noText = "verworfen: kein Text"
        case convertedOnly = "nur umgewandelt (ohne Hilfsprogramm)"
        case restored = "eingefügt, zurückgeholt"
        case cleared = "eingefügt, vertraulich geleert"
        case tooLarge = "eingefügt, zu groß zum Zurückholen"
        case newerCopy = "eingefügt, neuere Kopie bleibt"
    }

    private static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "reiner-text")

    private let prefs: Preferences
    private let pasteboard: NSPasteboard
    /// Hilfsprogramm verbunden und freigegeben (wie `ClipboardLink.canPaste`).
    var canPaste: () -> Bool
    /// Befehl `paste` ans Hilfsprogramm (G42).
    var sendPaste: () -> Void
    /// ⇧/⌥/⌃ noch gedrückt? Sonst käme das ⌘V womöglich als ⇧⌘V an.
    var modifiersHeld: () -> Bool = { !NSEvent.modifierFlags.isDisjoint(with: [.shift, .option, .control]) }
    var releaseWaitLimit: TimeInterval = 1
    /// Zeit, bis die vordere App die Zwischenablage gelesen hat (wie Tippi, `pasteEffectLimit`).
    var restoreDelay: TimeInterval = 1
    /// Ohne Hilfsprogramm: vertraulichen reinen Text nach dieser Zeit leeren (wie Tresor, G39).
    var concealedClearDelay: TimeInterval = 60

    private var running = false
    /// `changeCount` des eigenen reinen Texts, solange ein Durchgang läuft.
    private var ownChange: Int?
    /// Zeitpunkt fürs Zurückholen; ein zweiter Druck schiebt ihn hinaus.
    private var restoreAt: Date?
    private var hotKeyID: UInt32?
    private var registeredHotKey: Preferences.HotKey?

    init(activity: ActivityModel, prefs: Preferences, pasteboard: NSPasteboard = .general) {
        self.prefs = prefs
        self.pasteboard = pasteboard
        canPaste = { [weak activity] in activity?.notifyTrust == true }
        sendPaste = { [weak activity] in activity?.notifyCommand(.paste) }
    }

    static func defaultHotKey() -> Preferences.HotKey? {
        HotKeyCenter.keyCode(producing: "v").map {
            Preferences.HotKey(keyCode: $0, modifiers: UInt32(shiftKey | cmdKey))
        }
    }

    // MARK: - NotchPart

    func start() {
        if prefs.plainPasteHotKey == nil { prefs.plainPasteHotKey = Self.defaultHotKey() }
        registerHotKey()
        Self.log.notice("Reiner Text an")
    }

    func stop() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = nil
        Self.log.notice("Reiner Text aus")
    }

    func recheck() {
        guard registeredHotKey != prefs.plainPasteHotKey else { return }
        registerHotKey()
    }

    // MARK: - Ablauf

    /// Ein Durchgang nach Michaels Tastendruck. Protokoll nur mit festen Texten, nie Inhalt (G8).
    @discardableResult
    func run() async -> Outcome {
        if running { return await pasteAgain() }
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return log(.noText) }
        running = true
        defer { running = false; ownChange = nil; restoreAt = nil }
        let snapshot = PlainPaste.capture(pasteboard)
        // Von Gnotchi erkannter Schlüssel (G43) zählt wie eine vertrauliche Kopie: Das Zurückschreiben hätte Gnotchis
        // 5-Minuten-Uhr außer Kraft gesetzt (Code-Audit 18.11.).
        let sensitive = snapshot.concealed
            || (prefs.clipboard && prefs.clipboardSecrets && SecretDetector.kind(of: text) != nil)
        PlainPaste.writePlain(text, concealed: sensitive, to: pasteboard)
        let ours = pasteboard.changeCount
        guard canPaste() else {
            if sensitive { clearLater(ifStill: ours, after: concealedClearDelay) }
            return log(.convertedOnly)
        }
        ownChange = ours
        await waitForRelease()
        sendPaste()
        restoreAt = Date().addingTimeInterval(restoreDelay)
        // Ein zweiter Druck in der Wartezeit schiebt das Zurückholen hinaus (`pasteAgain`).
        while let at = restoreAt, at.timeIntervalSinceNow > 0 {
            try? await Task.sleep(for: .seconds(at.timeIntervalSinceNow))
        }
        guard pasteboard.changeCount == ours else { return log(.newerCopy) }
        if sensitive {
            pasteboard.clearContents()
            return log(.cleared)
        }
        guard let items = snapshot.items else { return log(.tooLarge) }
        PlainPaste.restore(items, to: pasteboard)
        return log(.restored)
    }

    /// Zweiter Druck, solange der reine Text noch in der Zwischenablage liegt: nochmal einfügen (zwei Felder
    /// hintereinander), Zurückholen hinausschieben. Sonst verwerfen.
    private func pasteAgain() async -> Outcome {
        guard let own = ownChange, pasteboard.changeCount == own, canPaste() else { return log(.busy) }
        await waitForRelease()
        guard ownChange == own, pasteboard.changeCount == own else { return log(.busy) }
        sendPaste()
        restoreAt = Date().addingTimeInterval(restoreDelay)
        return log(.again)
    }

    private func waitForRelease() async {
        let start = Date()
        while modifiersHeld(), Date().timeIntervalSince(start) < releaseWaitLimit {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func clearLater(ifStill change: Int, after delay: TimeInterval) {
        // Die Zwischenablage selbst halten, nicht `self`: Das Leeren gilt auch, wenn der Schalter inzwischen aus ist.
        let board = pasteboard
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard board.changeCount == change else { return }
            board.clearContents()
        }
    }

    private func log(_ outcome: Outcome) -> Outcome {
        Self.log.notice("\(outcome.rawValue, privacy: .public)")
        return outcome
    }

    private func registerHotKey() {
        if let hotKeyID { HotKeyCenter.shared.unregister(hotKeyID) }
        hotKeyID = nil
        registeredHotKey = prefs.plainPasteHotKey
        guard let hotKey = prefs.plainPasteHotKey else { return }
        hotKeyID = HotKeyCenter.shared.register(hotKey) { [weak self] in
            Task { await self?.run() }
        }
        if hotKeyID == nil { Self.log.error("Tastenkürzel nicht registriert") }
    }
}
