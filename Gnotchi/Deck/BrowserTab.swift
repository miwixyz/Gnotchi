import AppKit
import OSLog

/// Stream Deck, Stufe 1 des Browser-Wegs (G59 Punkt 10): Play/Pause und Titel für YouTube in Helium, **gezielt am Tab**, auch
/// wenn macOS gerade eine andere Quelle (Spotify) als aktiv führt. MediaRemote kennt nur die aktive Quelle (Messpunkt M3).
///
/// - Ab Werk aus („Browser-Tab steuern“). Aus = Gnotchi schickt Helium nie ein Apple Event.
/// - JavaScript nur in Tabs mit Host `www.youtube.com` / `music.youtube.com` (geparst, nicht per Teilzeichenfolge) und
///   zusätzlich im Skript selbst geprüft (`location.hostname`) – Tab-Nummern können sich zwischen zwei Aufrufen verschieben.
/// - Alle Skripte sind Konstanten. Einzige variable Größen sind zwei Ganzzahlen (Fenster-ID, Tab-ID) im Bereich 1…Int32.max.
/// - Tab-Adressen werden nur zum Filtern gelesen und danach verworfen: nie gespeichert, protokolliert oder gesendet.
/// - Titel und Kanal kommen aus der Seite, sind also fremde Daten: gekürzt, ohne Steuerzeichen (`LiveText.sanitize`).
/// - Kein Netz. Die Seite lädt der Browser, nicht Gnotchi.
///
/// Ablauf: `DeckLink` ruft `refresh()` im 0,5-s-Takt auf, aber nur, solange das Plugin verbunden ist und Helium auf dem Deck
/// beobachtet wird. `refresh()` fragt höchstens einmal je Sekunde: erst die Tab-Liste (`listScript`), dann je passendem Tab das
/// Lese-JavaScript. Das Ergebnis liegt in `latest`; `DeckController` baut daraus Titel, Zustand und `canPlay`. Ein Tastendruck
/// ruft `toggle()`, das den Tab per Fenster-/Tab-ID umschaltet.
///
/// Gemessen am 17.11. (Mac mini, Helium, macOS 27) und im Code berücksichtigt:
/// - Im `tell`-Block von Helium ist `tab` eine Klasse, kein Tabulator → Tabulator vorher holen (`listScript`).
/// - Fenster-/Tab-**Positionen** wandern, sobald ein anderes Fenster nach vorn kommt → IDs verwenden.
/// - Ist „JavaScript von Apple Events erlauben“ aus, meldet Helium Fehler 12 → `Failure.javascriptOff`.
/// - Der erste Apple-Event löst den Automation-Dialog von macOS aus; die Skripte laufen mit 5-s-Zeitgrenze, damit die Queue
///   nicht ewig hängt. `busy` verhindert, dass sich Abfragen stauen, solange der Dialog offen ist.
/// Nicht gemessen: mehrere YouTube-Tabs gleichzeitig, Verhalten im laufenden Gnotchi bei ausgeschaltetem Helium-Schalter.
@MainActor
final class BrowserTab {

    nonisolated static let bundleID = "net.imput.helium"
    nonisolated static let allowedHosts: Set<String> = ["www.youtube.com", "music.youtube.com"]
    /// So viele passende Tabs fragt Gnotchi höchstens ab (ein Fenster voller YouTube-Tabs soll keine Last erzeugen).
    nonisolated static let maxCandidates = 6
    /// Heliums Fenster- und Tab-IDs sind stabil (Positionen verschieben sich, sobald ein anderes Fenster nach vorn kommt).
    nonisolated static let idRange = 1...Int(Int32.max)
    /// Heliums Fehlernummer, wenn „JavaScript von Apple Events erlauben“ aus ist (gemessen 17.11. mit osascript: „(12)“).
    nonisolated static let javascriptOffError = 12
    nonisolated static let minInterval: TimeInterval = 1
    private nonisolated static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "streamdeck")

    /// Ein Tab mit Video, wie ihn die Seite meldet. `window`/`index` sind Heliums Fenster- und Tab-**IDs**.
    struct Tab: Equatable, Sendable {
        let window: Int
        let index: Int
        var paused: Bool
        var title: String?
        var artist: String?
    }

    enum Failure: Equatable, Sendable {
        /// Helium läuft nicht.
        case notRunning
        /// „JavaScript von Apple Events erlauben“ ist in Helium aus.
        case javascriptOff
        /// macOS hat die Automation für Helium verweigert (-1743).
        case denied
        case other
    }

    struct Snapshot: Equatable, Sendable {
        var tabs: [Tab] = []
        var failure: Failure?
    }

    /// Letzte Messung. Bleibt stehen, bis die nächste da ist.
    private(set) var latest = Snapshot()
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "dev.mwlr.gnotchi.browsertab", qos: .utility)
    private var busy = false
    private var lastStart = Date.distantPast
    private var generation = 0
    /// Ein Befehl läuft: weitere werden verworfen, nicht angestaut.
    private var commandRunning = false

    func reset() {
        generation += 1
        busy = false
        commandRunning = false
        latest = Snapshot()
    }

    /// Eine Abfrage, höchstens eine je Sekunde und nie zwei gleichzeitig. Läuft Helium nicht: keine Apple Events (G59/10a).
    func refresh() {
        guard !busy, Date().timeIntervalSince(lastStart) >= Self.minInterval else { return }
        guard Self.isRunning else {
            if latest != Snapshot(tabs: [], failure: .notRunning) {
                latest = Snapshot(tabs: [], failure: .notRunning)
                onChange?()
            }
            return
        }
        busy = true
        lastStart = Date()
        let gen = generation
        queue.async { [weak self] in
            let snap = Self.measure()
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.busy = false
                if snap != self.latest {
                    self.latest = snap
                    self.onChange?()
                }
            }
        }
    }

    /// Play/Pause für den YouTube-Tab. `false`: kein Tab bekannt oder die letzte Messung scheiterte – der Aufrufer nimmt dann den
    /// normalen Weg (MediaRemote), damit die Taste nie tot ist.
    ///
    /// Ziel ist der Stand der letzten Messung (höchstens ~1 s alt). Steht der Tab inzwischen woanders, fangen das die IDs und der
    /// Host-Test im Skript ab (der Befehl trifft dann keinen fremden Tab, im Zweifel gar keinen). Es läuft höchstens ein Befehl;
    /// ein zweiter Druck währenddessen wird verworfen, nicht angestaut (zählt als „erledigt“ → `true`).
    @discardableResult
    func toggle() -> Bool {
        guard latest.failure == nil, let target = Self.toggleTarget(latest.tabs) else { return false }
        guard !commandRunning else { return true }
        commandRunning = true
        let gen = generation
        let action: Action = target.paused ? .play : .pause
        queue.async { [weak self] in
            let state = Self.run(window: target.window, index: target.index, action: action)
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.commandRunning = false
                // Sofort den neuen Stand zeigen, sonst hinkt die Taste bis zur nächsten Abfrage. Reihenfolge ist sicher: Die Queue
                // ist seriell, eine davor laufende Messung meldet sich also vor diesem Befehl zurück und überschreibt ihn nicht.
                if let state, let i = self.latest.tabs.firstIndex(where: { $0.window == target.window && $0.index == target.index }) {
                    self.latest.tabs[i] = state
                    self.onChange?()
                }
                self.lastStart = .distantPast
            }
        }
        return true
    }

    // MARK: Reine Teile (getestet)

    enum Action: String, Sendable { case read = "", play = "v.play();", pause = "v.pause();" }

    /// Host einer Tab-Adresse nach Positivliste. Nur https, kein Benutzer/Passwort, Host exakt (nie „enthält“).
    nonisolated static func isAllowedURL(_ s: String) -> Bool {
        guard s.utf8.count <= 2048, let u = URL(string: s), u.scheme?.lowercased() == "https", u.user == nil, u.password == nil,
              let host = u.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    /// Zeilen „Fenster⇥Tab⇥Adresse“ aus dem Listenskript → Kandidaten. Alles Unlesbare wird verworfen.
    nonisolated static func candidates(from listing: String) -> [(window: Int, index: Int)] {
        var out: [(Int, Int)] = []
        for line in listing.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard f.count == 3, let w = Int(f[0]), let t = Int(f[1]), idRange.contains(w), idRange.contains(t),
                  isAllowedURL(String(f[2])) else { continue }
            out.append((w, t))
            if out.count == maxCandidates { break }
        }
        return out
    }

    /// Welcher Tab wird umgeschaltet: der gerade spielende, sonst der erste mit Video. Ohne Tab nil.
    nonisolated static func toggleTarget(_ tabs: [Tab]) -> Tab? {
        tabs.first { !$0.paused } ?? tabs.first
    }

    /// Welcher Tab steht auf der Taste: wie `toggleTarget`.
    nonisolated static func displayed(_ tabs: [Tab]) -> Tab? { toggleTarget(tabs) }

    /// Antwort der Seite (JSON `{"p":bool,"t":"…","a":"…"}`) → Tab. Fremde Daten: unbekannte Form → nil, Texte gekürzt.
    nonisolated static func parseState(_ text: String, window: Int, index: Int) -> Tab? {
        guard text.utf8.count <= 2048, let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pn = obj["p"] as? NSNumber, CFGetTypeID(pn) == CFBooleanGetTypeID() else { return nil }
        let p = pn.boolValue
        let clean = { (s: String?) -> String? in
            guard let s else { return nil }
            let c = String(LiveText.sanitize(s).prefix(DeckWire.maxTextChars))
            return c.isEmpty ? nil : c
        }
        return Tab(window: window, index: index, paused: p, title: clean(obj["t"] as? String), artist: clean(obj["a"] as? String))
    }

    /// Listenskript: nur Adressen, kein JavaScript. Startet Helium nie (`tell application id` ohne Laufprüfung würde es starten –
    /// die Prüfung steht davor in Swift und im Skript).
    nonisolated static let listScript = """
        if application id "\(bundleID)" is not running then return ""
        -- Tabulator VOR dem tell holen: im tell-Block liest AppleScript „tab“ als Heliums Klasse (gemessen 17.11.).
        set tb to ASCII character 9
        with timeout of 5 seconds
            tell application id "\(bundleID)"
                set out to ""
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (id of w) & tb & (id of t) & tb & (URL of t) & linefeed
                    end repeat
                end repeat
                return out
            end tell
        end timeout
        """

    /// JavaScript im Tab. Konstante; `action` ist eine der drei Zeichenketten aus `Action`. Prüft den Host selbst und tut sonst nichts.
    nonisolated static func javascript(_ action: Action) -> String {
        "(function(){var h=location.hostname;if(h!=='www.youtube.com'&&h!=='music.youtube.com')return '';"
            + "var v=document.querySelector('video');if(!v)return '';\(action.rawValue)"
            + "var m=navigator.mediaSession&&navigator.mediaSession.metadata;"
            + "return JSON.stringify({p:v.paused,t:m?String(m.title):'',a:m?String(m.artist):''})})()"
    }

    /// Skript für einen Tab. Fenster und Tab sind geprüfte Ganzzahlen; das JavaScript enthält keine Anführungszeichen.
    nonisolated static func tabScript(window: Int, index: Int, action: Action) -> String? {
        guard idRange.contains(window), idRange.contains(index) else { return nil }
        let js = javascript(action)
        guard !js.contains("\"") && !js.contains("\\") else { return nil }
        return """
            with timeout of 5 seconds
                tell application id "\(bundleID)" to return execute tab id \(index) of window id \(window) javascript "\(js)"
            end timeout
            """
    }

    // MARK: Ausführen (auf der Queue)

    private nonisolated static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// NSAppleScript ist nicht Sendable – hier erzeugt, nie geteilt.
    private nonisolated static func execute(_ source: String) -> (String?, Int?) {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (out?.stringValue, err?[NSAppleScript.errorNumber] as? Int)
    }

    private nonisolated static func failure(_ code: Int) -> Failure {
        switch code {
        case javascriptOffError: .javascriptOff
        case AppleScriptSource.deniedError: .denied
        case AppleScriptSource.notRunningError: .notRunning
        default: .other
        }
    }

    /// Eine volle Messung (auf der Queue). Beim ersten Fehler wird abgebrochen: Alle Fehlerarten (Schalter aus, Automation
    /// verweigert, Zeitgrenze) gelten für Helium insgesamt, weitere Tabs würden dasselbe melden. Bereits gelesene Tabs bleiben
    /// im Ergebnis, damit die Anzeige nicht flackert.
    private nonisolated static func measure() -> Snapshot {
        guard isRunning else { return Snapshot(tabs: [], failure: .notRunning) }
        let (listing, error) = execute(listScript)
        if let error { return Snapshot(tabs: [], failure: failure(error)) }
        var tabs: [Tab] = []
        for c in candidates(from: listing ?? "") {
            guard let source = tabScript(window: c.window, index: c.index, action: .read) else { continue }
            let (text, err) = execute(source)
            if let err { return Snapshot(tabs: tabs, failure: failure(err)) }
            if let tab = text.flatMap({ parseState($0, window: c.window, index: c.index) }) { tabs.append(tab) }
        }
        return Snapshot(tabs: tabs, failure: nil)
    }

    private nonisolated static func run(window: Int, index: Int, action: Action) -> Tab? {
        guard isRunning, let source = tabScript(window: window, index: index, action: action) else { return nil }
        let (text, error) = execute(source)
        if let error {
            // G8: nur die Fehlernummer, nie Inhalte.
            log.error("Browser-Tab: Befehl gescheitert (\(error, privacy: .public))")
            return nil
        }
        return text.flatMap { parseState($0, window: window, index: index) }
    }
}
