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
            // Flut: die älteste **wartende** fliegt raus (nie gezeigt → Apples Banner war nie versteckt).
            if notes.count > Self.maxQueuedNotes { notes.remove(at: 1) }
        }
    }

    /// Banner ist bei Apple weg (weggeklickt, abgelaufen, Anruf beendet).
    func noteGone(_ id: String) {
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
        notifyTrust = nil
    }

    // MARK: Anzeige

    /// Eine Insel zeigt die vorderste Mitteilung: jetzt erst darf Apples Banner weg, jetzt läuft die Zeit.
    func noteDisplayed() {
        guard let n = notes.first, noteShownID != n.id else { return }
        noteShownID = n.id
        notifyCommand(.shown(n.id))
        noteTask?.cancel()
        noteTask = Task { [weak self, noteDuration] in
            try? await Task.sleep(for: noteDuration)
            // Maus darüber: stehen lassen (Spec).
            while !Task.isCancelled, self?.rotationPaused == true {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled, let self, self.notes.first?.id == n.id else { return }
            self.notifyCommand(.release(n.id))
            self.advanceNote()
        }
    }

    // MARK: Klicks (G30)

    /// Klick auf die Mitteilung: macOS öffnet die App an der richtigen Stelle (`AXPress` am Banner).
    func openNote() {
        guard let n = notes.first else { return }
        notifyCommand(.act(id: n.id, action: NotifyWire.openAction))
        advanceNote()
    }

    /// Knopf der Mitteilung (z. B. „Erledigt“, ×): genau diese, von macOS gemeldete Aktion.
    func performNoteAction(_ action: String) {
        guard let n = notes.first, n.actions.contains(action) else { return }
        notifyCommand(.act(id: n.id, action: action))
        advanceNote()
    }

    /// Annehmen/Ablehnen. Erst nach `callArmDelay`; danach entscheidet Apples Banner (es verschwindet → `gone`).
    func answerCall(_ action: String) {
        guard let c = call, callArmed, c.actions.contains(action) else { return }
        callArmed = false
        notifyCommand(.act(id: c.id, action: action))
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
        if call != nil { call = nil }
        if callArmed { callArmed = false }
    }
}
