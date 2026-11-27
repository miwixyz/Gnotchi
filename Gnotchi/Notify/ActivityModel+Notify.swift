import Foundation

/// Mitteilungen und Anrufe in der Insel (0.6.0, specs/2026-10-22-gnotchi-0.6.0-mitteilungen-anrufe.md, G29/G30).
///
/// Ablauf einer Mitteilung: Das Hilfsprogramm meldet sie → hier in die Warteschlange. Erst wenn eine Insel sie
/// **wirklich zeigt** (`noteDisplayed`), geht `shown` zurück und das Hilfsprogramm versteckt Apples Banner – so geht
/// nichts verloren, solange Gnotchi sie nicht zeigen kann (Aufnahme, große Insel offen). Nach `noteDuration` (steht,
/// solange die Maus darüber ist) → `release`: Apples Banner kommt zurück bzw. ist schon in der Mitteilungszentrale.
/// Knöpfe senden `act` nur aus einem Klick (G30).
extension ActivityModel {

    nonisolated static let maxQueuedNotes = 20

    var currentNote: NotifyWire.Note? { notes.first }

    /// Anzahl wartender Mitteilungen hinter der angezeigten („+2“).
    var queuedNotes: Int { max(0, notes.count - 1) }

    // MARK: Vom Hilfsprogramm

    func receiveNote(_ n: NotifyWire.Note) {
        switch n.kind {
        case .call:
            guard callDismissedID != n.id else { return }
            // Gleicher Zustand noch einmal (z. B. nach Neuverbindung): nicht neu entschärfen.
            guard call != n else { return }
            call = n
            callArmed = false
            callArmTask?.cancel()
            callArmTask = Task { [weak self, callArmDelay] in
                try? await Task.sleep(for: callArmDelay)
                guard !Task.isCancelled, self?.call?.id == n.id else { return }
                self?.callArmed = true
            }
        case .note:
            guard !notes.contains(where: { $0.id == n.id }) else { return }
            notes.append(n)
            // Türklingel (Michael 27.11.: „automatisch“): Klingel-App sofort nach vorn, damit Mac und Fernseher
            // (CleanFrame) das Livebild zeigen. Nimmt bewusst den Fokus, deshalb nur mit eigenem Schalter.
            if doorbellAutoOpen, n.bundle == Self.homeBundle { openApp(doorbellApp) }
            // Flut: die älteste **wartende** fliegt raus (nie gezeigt → Apples Banner war nie versteckt).
            if notes.count > Self.maxQueuedNotes { notes.remove(at: 1) }
        }
    }

    /// Banner ist bei Apple weg (weggeklickt, abgelaufen, Anruf beendet).
    func noteGone(_ id: String) {
        if callDismissedID == id { callDismissedID = nil }
        if call?.id == id { endCall() }
        if notes.first?.id == id {
            advanceNote()
        } else {
            notes.removeAll { $0.id == id }
        }
    }

    /// Verbindung zum Hilfsprogramm weg oder Schalter aus: alles verwerfen (nichts gespeichert).
    func clearNotify() {
        noteTask?.cancel()
        noteTask = nil
        noteShownID = nil
        if !notes.isEmpty { notes = [] }
        endCall()
        callDismissedID = nil
        if !unread.isEmpty { unread = [] }
        notifyTrust = nil
        doorbellFeed.stop()
    }

    /// Ungelesen-Zahlen vom Hilfsprogramm (Schema geprüft, G33). `allowed` = ausgewählte Apps: Gnotchi filtert selbst noch
    /// einmal (wie bei Mitteilungen) – ein falsches Hilfsprogramm könnte sonst per Klick beliebige Apps öffnen lassen.
    func receiveBadges(_ list: [NotifyWire.Badge], allowed: Set<String>? = nil) {
        let kept = allowed.map { a in list.filter { a.contains($0.bundle) } } ?? list
        if unread != kept { unread = kept }
    }

    /// Summe für die kleine Insel (höchstens 9999).
    var unreadTotal: Int { min(unread.reduce(0) { $0 + $1.count }, NotifyWire.maxBadgeCount) }

    /// Was die kleine Insel zeigt: 0, wenn der Zähler dort ausgeschaltet ist.
    var compactUnreadTotal: Int { compactUnread ? unreadTotal : 0 }

    // MARK: Anzeige

    /// Eine Insel zeigt die vorderste Mitteilung: jetzt erst darf Apples Banner weg, jetzt läuft die Zeit.
    func noteDisplayed() {
        guard let n = notes.first, noteShownID != n.id else { return }
        noteShownID = n.id
        if n.id != Self.testDoorbellID { notifyCommand(.shown(n.id)) }
        noteTask?.cancel()
        let duration = showsDoorbellCamera(n) ? doorbellNoteDuration : noteDuration
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            // Maus darüber: stehen lassen (Spec).
            while !Task.isCancelled, self?.rotationPaused == true {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled, let self, self.notes.first?.id == n.id else { return }
            if n.id != Self.testDoorbellID { self.notifyCommand(.release(n.id)) }
            self.advanceNote()
        }
    }

    /// Eine Insel zeigt den Anruf: jetzt darf Apples Anruf-Banner weg (0.9.0) – nur beim Klingeln. Nicht beim Mitlesen
    /// (Abschrift nur bei Apple), nicht im Gespräch (Apples Leiste hat mehr Knöpfe), nicht bei unbekanntem Zustand.
    func callDisplayed() {
        guard let c = call, callShownID != c.id, !c.actions.isEmpty, !NotifyWire.isOngoing(c), !NotifyWire.isScreening(c)
        else { return }
        callShownID = c.id
        notifyCommand(.shown(c.id))
    }

    // MARK: Klicks (G30)

    /// Kennung der Home-App. Gespiegelte iPhone-Banner (Türklingel) öffnen am Mac nichts Brauchbares → Home selbst
    /// öffnen, dort läuft das Livebild. Feste Kennung, nie aus der Mitteilung übernommen.
    nonisolated static let homeBundle = "com.apple.Home"
    /// Aqara-App (Türklingel G410). Zeigt das Livebild ohne Klick, sobald sie vorn ist (gemessen 27.11.); CleanFrame
    /// nimmt ihr Fenster dann für den Fernseher auf. Feste Kennung, nie aus der Mitteilung übernommen.
    nonisolated static let aqaraBundle = "com.lumiunited.pre.homekit"

    /// Kennung des Test-Hinweises aus den Einstellungen. Geht nie ans Hilfsprogramm (dort gibt es kein Banner dazu).
    nonisolated static let testDoorbellID = "gnotchi-test-tuerklingel"

    /// Knopf „Insel testen“ (Michael 27.11.: Klingeln lässt sich nicht jederzeit testen): ein erfundener Home-Hinweis
    /// mit dem Bild der eingetragenen Adresse, genau wie beim Klingeln. Öffnet keine App von selbst. Steht schon ein
    /// Test-Hinweis an, passiert nichts.
    func showTestDoorbell(url: URL) {
        guard !notes.contains(where: { $0.id == Self.testDoorbellID }) else { return }
        doorbellFeed.url = url
        notes.append(NotifyWire.Note(id: Self.testDoorbellID, kind: .note, app: "Home", bundle: Self.homeBundle,
                                     title: "Test: Es hat geklingelt", subtitle: "", body: "", actions: []))
        if notes.count > Self.maxQueuedNotes { notes.remove(at: 1) }
    }

    /// Zeigt die Insel zu dieser Mitteilung das Kamerabild? Nur Home-Hinweise (Türklingel) und nur mit eingetragener Adresse.
    func showsDoorbellCamera(_ n: NotifyWire.Note?) -> Bool {
        n?.bundle == Self.homeBundle && doorbellFeed.url != nil
    }

    /// Wohin ein Home-Hinweis (Türklingel) führt: Aqara, falls installiert, sonst Home.
    var doorbellApp: String { appInstalled(Self.aqaraBundle) ? Self.aqaraBundle : Self.homeBundle }

    /// Klick auf die Mitteilung: macOS öffnet die App an der richtigen Stelle (`AXPress` am Banner). Bei Home zusätzlich
    /// die Klingel-App nach vorn (Livebild der Türklingel).
    func openNote() {
        guard let n = notes.first else { return }
        if n.id != Self.testDoorbellID { notifyCommand(.act(id: n.id, action: NotifyWire.openAction)) }
        if n.bundle == Self.homeBundle { openApp(doorbellApp) }
        advanceNote()
    }

    /// Knopf der Mitteilung (z. B. „Erledigt“, ×): genau diese, von macOS gemeldete Aktion.
    func performNoteAction(_ action: String) {
        guard let n = notes.first, n.actions.contains(action) else { return }
        notifyCommand(.act(id: n.id, action: action))
        advanceNote()
    }

    /// Annehmen, Beenden, „Mitlesen beenden“. Erst nach `callArmDelay`; danach entscheidet Apples Banner (es
    /// verschwindet → `gone`, oder es meldet den nächsten Zustand).
    func answerCall(_ action: String) {
        guard let c = call, callArmed, c.actions.contains(action) else { return }
        callArmed = false
        notifyCommand(.act(id: c.id, action: action))
    }

    /// Rot (0.9.0, Michael 22.10.): Ablehnen und Apples Fenster ist weg – das Hilfsprogramm drückt danach einmal
    /// „Live-Voicemail stoppen“. Der Anrufer landet auf der Mailbox. Der Anruf verschwindet sofort aus der Insel.
    func declineCall() {
        guard let c = call, callArmed, let decline = c.actions.first(where: { NotifyWire.declineActions.contains($0) })
        else { return }
        notifyCommand(.act(id: c.id, action: decline, stopVoicemail: true))
        callDismissedID = c.id
        endCall()
    }

    /// „Mitlesen“: ablehnen ohne Folgeaktion – der Anrufer spricht auf die Mailbox, der Mac liest mit; die Insel zeigt
    /// danach „Mitlesen beenden“ und „Annehmen“.
    func screenCall() {
        guard let c = call, callArmed, let decline = c.actions.first(where: { NotifyWire.declineActions.contains($0) })
        else { return }
        callArmed = false
        notifyCommand(.act(id: c.id, action: decline))
    }

    // MARK: Intern

    private func advanceNote() {
        noteTask?.cancel()
        noteTask = nil
        noteShownID = nil
        if !notes.isEmpty { notes.removeFirst() }
    }

    private func endCall() {
        callArmTask?.cancel()
        callArmTask = nil
        callShownID = nil
        if call != nil { call = nil }
        if callArmed { callArmed = false }
    }
}
