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

    // MARK: Cover (G59 Punkt 10e, Stufe 2)

    /// Schalter „Cover auf dem Deck“ – setzt `DeckLink`. Aus = kein Cover-JavaScript im Tab.
    var coverWanted = false {
        didSet { if !coverWanted { clearCover() } }
    }
    /// Fertiges Deck-Bild (aus `DeckCover.render`) für den angezeigten Tab, sonst nil.
    private(set) var cover: Data?
    /// Zu welchem Video (Tab + Titel + Kanal) `cover` gehört.
    private var coverKey: String?
    private var coverPending: (key: String, tries: Int)?
    /// So oft wird nach dem Start nachgefragt (je ≥ 1 s), dann gilt: kein Cover für dieses Video.
    nonisolated static let maxCoverTries = 5

    enum CoverStep: Sendable { case none, start(Tab), collect(Tab) }
    enum CoverOutcome: Sendable, Equatable { case none, started, waiting, done(Data?) }

    nonisolated static func coverKey(_ t: Tab) -> String { "\(t.window):\(t.index):\(t.title ?? "")|\(t.artist ?? "")" }

    private func clearCover() {
        let had = cover != nil
        cover = nil
        coverKey = nil
        coverPending = nil
        if had { onChange?() }
    }

    /// Welcher Cover-Schritt gehört in die nächste Abfrage? Höchstens einer je Abfrage, also höchstens 1/s (10f).
    private func nextCoverStep() -> CoverStep {
        guard coverWanted, latest.failure == nil, let t = Self.displayed(latest.tabs) else {
            if coverKey != nil || coverPending != nil { clearCover() }
            return .none
        }
        let key = Self.coverKey(t)
        if let p = coverPending { return p.key == key ? .collect(t) : .start(t) }
        return key == coverKey ? .none : .start(t)
    }

    private func apply(_ outcome: CoverOutcome, step: CoverStep) {
        let key: String
        switch step {
        case .none: return
        case .start(let t), .collect(let t): key = Self.coverKey(t)
        }
        switch outcome {
        case .none: return
        case .started: coverPending = (key, 0)
        case .waiting:
            guard let p = coverPending, p.key == key else { return }
            if p.tries + 1 >= Self.maxCoverTries { finishCover(key: key, data: nil) } else { coverPending = (key, p.tries + 1) }
        case .done(let data): finishCover(key: key, data: data)
        }
    }

    private func finishCover(key: String, data: Data?) {
        coverPending = nil
        coverKey = key
        if cover != data {
            cover = data
            onChange?()
        }
    }

    func reset() {
        generation += 1
        busy = false
        commandRunning = false
        latest = Snapshot()
        cover = nil
        coverKey = nil
        coverPending = nil
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
        let step = nextCoverStep()
        queue.async { [weak self] in
            let snap = Self.measure()
            let outcome = snap.failure == nil ? Self.runCover(step) : .none
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.busy = false
                if snap != self.latest {
                    self.latest = snap
                    self.onChange?()
                }
                self.apply(outcome, step: step)
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

    /// Cover holen, Schritt 1 (10e/10f): Der **Browser** lädt das kleinste Artwork der Media-Session mit mindestens 144 px
    /// (sonst das letzte), verkleinert es im Tab per Canvas auf 144 px Breite und legt die `data:`-Adresse in einer Variablen ab.
    /// `fetch` ist asynchron, deshalb liest Schritt 2 sie in einer späteren Abfrage. Antwort: `1` gestartet, `0` kein Artwork.
    /// Gnotchi lädt nichts aus dem Netz und sieht die Artwork-Adresse nie.
    nonisolated static let coverStartJavaScript =
        "(function(){var h=location.hostname;if(h!=='www.youtube.com'&&h!=='music.youtube.com')return '';"
            + "var m=navigator.mediaSession&&navigator.mediaSession.metadata;var a=m&&m.artwork;"
            + "if(!a||!a.length){delete window.__gnotchiCover;return '0';}"
            + "var s='',b=1e9;for(var i=0;i<a.length;i++){var z=parseInt(String(a[i].sizes||'0'),10)||0;"
            + "if(z>=144&&z<b){b=z;s=a[i].src;}}if(!s)s=a[a.length-1].src;"
            + "window.__gnotchiCover=null;"
            + "fetch(s,{mode:'cors',credentials:'omit'}).then(function(r){return r.blob();}).then(createImageBitmap)"
            + ".then(function(i){var w=144,hh=Math.max(1,Math.round(144*i.height/i.width));var c=document.createElement('canvas');"
            + "c.width=w;c.height=hh;c.getContext('2d').drawImage(i,0,0,w,hh);window.__gnotchiCover=c.toDataURL('image/jpeg',0.8);})"
            + ".catch(function(){window.__gnotchiCover='';});return '1';})()"

    /// Cover holen, Schritt 2: noch nicht fertig → `wait`; sonst Ergebnis zurück und Variable löschen (keine Spur im Tab, 10f).
    nonisolated static let coverCollectJavaScript =
        "(function(){var h=location.hostname;if(h!=='www.youtube.com'&&h!=='music.youtube.com')return '';"
            + "var c=window.__gnotchiCover;if(c===null)return 'wait';delete window.__gnotchiCover;"
            + "return typeof c==='string'&&c.length<=24000?c:'';})()"

    /// Skript für einen Tab. Fenster und Tab sind geprüfte Ganzzahlen; das JavaScript enthält keine Anführungszeichen.
    nonisolated static func tabScript(window: Int, index: Int, action: Action) -> String? {
        tabScript(window: window, index: index, javascript: javascript(action))
    }

    /// Wie oben für die festen Cover-Skripte. Nur Konstanten aus dieser Datei, nie Text von außen.
    nonisolated static func tabScript(window: Int, index: Int, javascript js: String) -> String? {
        guard idRange.contains(window), idRange.contains(index) else { return nil }
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

    /// Ein Cover-Schritt (auf der Queue, nach `measure`). Fehler zählen als „kein Cover für dieses Video“, nie als Dauerversuch.
    nonisolated static func runCover(_ step: CoverStep) -> CoverOutcome {
        switch step {
        case .none: return .none
        case .start(let t):
            guard isRunning, let source = tabScript(window: t.window, index: t.index, javascript: coverStartJavaScript) else {
                return .none
            }
            let (text, error) = execute(source)
            if let error { log.error("Browser-Tab: Cover nicht gestartet (\(error, privacy: .public))") }
            return text == "1" ? .started : .done(nil)
        case .collect(let t):
            guard isRunning, let source = tabScript(window: t.window, index: t.index, javascript: coverCollectJavaScript) else {
                return .none
            }
            let (text, error) = execute(source)
            if let error { log.error("Browser-Tab: Cover nicht gelesen (\(error, privacy: .public))") }
            return collectOutcome(error == nil ? text : nil)
        }
    }

    /// Antwort von Schritt 2 → Ergebnis. Fremde Daten: nur über `DeckCover` (Prüfung vor dem Dekodieren, eigene Skalierung).
    nonisolated static func collectOutcome(_ text: String?) -> CoverOutcome {
        guard let text else { return .done(nil) }
        if text == "wait" { return .waiting }
        return .done(DeckCover.image(dataURL: text).flatMap(DeckCover.render))
    }
}
