import AppKit
import OSLog

/// Welche Browser Gnotchi am Tab steuern kann, und in welchem AppleScript-Dialekt (G59 Punkt 10, ab 0.45 mehrere Browser).
/// Nur Browser, deren Wörterbuch (sdef) am System gelesen wurde und die JavaScript im Tab ausführen können. Bundle-IDs stammen aus
/// der `Info.plist` der installierten App (gemessen 24.11., Mac mini), nicht aus dem Gedächtnis.
///
/// **Nicht steuerbar, bewusst nicht in der Tabelle:** Search (`com.officecommun.search`, sdef nur lesend: URL und Titel der Tabs,
/// kein JavaScript, kein Play/Pause) und Firefox (keine Skriptschnittstelle). Für sie bleibt nur der Weg über MediaRemote,
/// solange sie die aktive Quelle sind.
struct DeckBrowser: Equatable, Sendable {
    enum Dialect: Sendable {
        /// Chrome, Edge, Helium & Co.: Fenster und Tabs haben stabile IDs, `execute tab id N of window id M javascript "…"`.
        case chromium
        /// Safari: Fenster haben eine ID, Tabs nur die Position im Fenster, `do JavaScript "…" in tab N of window id M`.
        case safari
    }

    let id: String
    let name: String
    let dialect: Dialect

    static let chrome = DeckBrowser(id: "com.google.Chrome", name: "Chrome", dialect: .chromium)
    static let edge = DeckBrowser(id: "com.microsoft.edgemac", name: "Edge", dialect: .chromium)
    static let helium = DeckBrowser(id: "net.imput.helium", name: "Helium", dialect: .chromium)
    static let safari = DeckBrowser(id: "com.apple.Safari", name: "Safari", dialect: .safari)
    static let all = [chrome, edge, helium, safari]

    static func with(id: String) -> DeckBrowser? { all.first { $0.id == id } }

    /// Menüweg des Browser-Schalters „JavaScript von Apple Events erlauben“ (für Hinweise an Michael).
    var javascriptSettingPath: String {
        switch dialect {
        case .chromium: id == Self.helium.id ? "Darstellung → Entwickler" : "Ansicht → Entwickler"
        case .safari: "Einstellungen → Entwickler (dort erst das Entwickeln-Menü unter Erweitert einschalten; Wortlaut vermutet)"
        }
    }
}

/// Stream Deck, Stufe 1 des Browser-Wegs (G59 Punkt 10): Play/Pause und Titel für YouTube in einem Browser (`DeckBrowser`),
/// **gezielt am Tab**, auch wenn macOS gerade eine andere Quelle (Spotify) als aktiv führt. MediaRemote kennt nur die aktive
/// Quelle (Messpunkt M3). Je Browser eine Instanz; alle teilen sich eine Warteschlange und einen Takt (siehe `queue`, `lastStart`).
///
/// - Ab Werk aus („Browser-Tab steuern“). Aus = Gnotchi schickt keinem Browser je ein Apple Event.
/// - JavaScript nur in Tabs mit Host `www.youtube.com` / `music.youtube.com` (geparst, nicht per Teilzeichenfolge) und
///   zusätzlich im Skript selbst geprüft (`location.hostname`) – Tab-Nummern können sich zwischen zwei Aufrufen verschieben.
/// - Alle Skripte sind Konstanten. Einzige variable Größen sind zwei Ganzzahlen (Fenster-ID, Tab-ID) im Bereich 1…Int32.max.
/// - Tab-Adressen werden nur zum Filtern gelesen und danach verworfen: nie gespeichert, protokolliert oder gesendet.
/// - Titel und Kanal kommen aus der Seite, sind also fremde Daten: gekürzt, ohne Steuerzeichen (`LiveText.sanitize`).
/// - Kein Netz. Die Seite lädt der Browser, nicht Gnotchi.
///
/// Ablauf: `DeckLink` ruft reihum `refresh()` im 0,5-s-Takt auf, aber nur, solange das Plugin verbunden ist und der Browser auf dem Deck
/// beobachtet wird. `refresh()` fragt höchstens einmal je Sekunde: erst die Tab-Liste (`listScript`), dann je passendem Tab das
/// Lese-JavaScript. Das Ergebnis liegt in `latest`; `DeckController` baut daraus Titel, Zustand und `canPlay`. Ein Tastendruck
/// ruft `toggle()`, das den Tab per Fenster-/Tab-ID umschaltet.
///
/// Gemessen am 17.11. (Mac mini, Helium, macOS 27) und im Code berücksichtigt:
/// - Im `tell`-Block von Helium (und Chrome/Edge, gleicher Dialekt) ist `tab` eine Klasse, kein Tabulator → Tabulator vorher holen (`listScript`).
/// - Fenster-/Tab-**Positionen** wandern, sobald ein anderes Fenster nach vorn kommt → IDs verwenden.
/// - Ist „JavaScript von Apple Events erlauben“ aus, meldet Helium Fehler 12 → `Failure.javascriptOff`.
/// - Der erste Apple-Event löst den Automation-Dialog von macOS aus; die Skripte laufen mit 5-s-Zeitgrenze, damit die Queue
///   nicht ewig hängt. `busy` verhindert, dass sich Abfragen stauen, solange der Dialog offen ist.
/// Nicht gemessen: mehrere YouTube-Tabs gleichzeitig, Verhalten im laufenden Gnotchi bei ausgeschaltetem Browser-Schalter.
@MainActor
final class BrowserTab {

    nonisolated static let allowedHosts: Set<String> = ["www.youtube.com", "music.youtube.com"]
    /// So viele passende Tabs fragt Gnotchi höchstens ab (ein Fenster voller YouTube-Tabs soll keine Last erzeugen).
    nonisolated static let maxCandidates = 6
    /// Fenster- und Tab-IDs der Chromium-Browser sind stabil (Positionen verschieben sich, sobald ein anderes Fenster nach vorn kommt).
    nonisolated static let idRange = 1...Int(Int32.max)
    /// Fehlernummer, wenn „JavaScript von Apple Events erlauben“ aus ist. Chromium: 12 (gemessen 17.11. mit osascript an Helium).
    /// Safari: 8 („You must enable 'Allow JavaScript from Apple Events' in the Developer section of Safari Settings“, gemessen 24.11.).
    nonisolated static func javascriptOffError(_ browser: DeckBrowser) -> Int {
        switch browser.dialect {
        case .chromium: 12
        case .safari: 8
        }
    }
    nonisolated static let minInterval: TimeInterval = 1
    /// Eine Warteschlange für alle Browser: nie zwei Apple Events gleichzeitig (auch nicht an zwei Browser).
    private nonisolated static let queue = DispatchQueue(label: "dev.mwlr.gnotchi.browsertab", qos: .utility)
    /// Start der letzten Abfrage **irgendeines** Browsers: höchstens eine Abfrage je Sekunde insgesamt (G59/10f).
    private static var lastStart = Date.distantPast
    /// Läuft gerade irgendeine Abfrage? Dann startet keine weitere.
    private static var anyBusy = 0
    private nonisolated static let log = Logger(subsystem: "dev.mwlr.gnotchi", category: "streamdeck")

    /// Ein Tab mit Video, wie ihn die Seite meldet. `window`/`index` sind Fenster- und Tab-**IDs** (Safari: Fenster-ID und Position).
    struct Tab: Equatable, Sendable {
        let window: Int
        let index: Int
        var paused: Bool
        var title: String?
        var artist: String?
    }

    enum Failure: Equatable, Sendable {
        /// Der Browser läuft nicht.
        case notRunning
        /// „JavaScript von Apple Events erlauben“ ist im Browser aus.
        case javascriptOff
        /// macOS hat die Automation für den Browser verweigert (-1743).
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

    let browser: DeckBrowser
    private var busy = false {
        didSet { if busy != oldValue { Self.anyBusy += busy ? 1 : -1 } }
    }
    private var generation = 0
    /// Ein Befehl läuft: weitere werden verworfen, nicht angestaut.
    private var commandRunning = false
    /// Zuletzt aktiver Tab (siehe `active(_:previous:)`); nur im Speicher.
    private(set) var active: TabID?
    init(_ browser: DeckBrowser) { self.browser = browser }

    /// Der Tab auf der Taste.
    var shown: Tab? { Self.displayed(latest.tabs, active: active) }

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
        guard coverWanted, latest.failure == nil, let t = shown else {
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
        active = nil
        cover = nil
        coverKey = nil
        coverPending = nil
    }

    /// Eine Abfrage, höchstens eine je Sekunde (über alle Browser) und nie zwei gleichzeitig. Läuft der Browser nicht: keine
    /// Apple Events (G59/10a). `true` = eine Abfrage wurde gestartet (der Aufrufer reicht sonst an den nächsten Browser weiter).
    @discardableResult
    func refresh() -> Bool {
        guard Self.anyBusy == 0, Date().timeIntervalSince(Self.lastStart) >= Self.minInterval else { return false }
        guard Self.isRunning(browser) else {
            if latest != Snapshot(tabs: [], failure: .notRunning) {
                latest = Snapshot(tabs: [], failure: .notRunning)
                onChange?()
            }
            return false
        }
        busy = true
        Self.lastStart = Date()
        let gen = generation
        let step = nextCoverStep()
        let browser = browser
        Self.queue.async { [weak self] in
            let snap = Self.measure(browser)
            let outcome = snap.failure == nil ? Self.runCover(step, browser: browser) : .none
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.busy = false
                let now = Self.active(snap.tabs, previous: self.active)
                if snap != self.latest || now != self.active {
                    self.latest = snap
                    self.active = now
                    self.onChange?()
                }
                self.apply(outcome, step: step)
            }
        }
        return true
    }

    /// Play/Pause für die YouTube-Tabs (Michael 17.11.): spielt etwas → **alle** spielenden pausieren; spielt nichts → den
    /// zuletzt aktiven Tab starten. `false`: kein Tab bekannt oder die letzte Messung scheiterte – der Aufrufer nimmt dann den
    /// normalen Weg (MediaRemote), damit die Taste nie tot ist.
    ///
    /// Vor dem Befehl wird **frisch** gemessen (gemessen 17.11.: mit dem bis 1 s alten Stand startete ein Druck nach einem von
    /// Hand gestarteten Video ein zweites, statt es zu pausieren). Es läuft höchstens ein Befehl; ein zweiter Druck währenddessen
    /// wird verworfen, nicht angestaut (zählt als „erledigt“ → `true`).
    @discardableResult
    func toggle() -> Bool {
        guard latest.failure == nil, !latest.tabs.isEmpty else { return false }
        guard !commandRunning else { return true }
        commandRunning = true
        let gen = generation
        let previous = active
        let browser = browser
        Self.queue.async { [weak self] in
            let snap = Self.measure(browser)
            let now = Self.active(snap.tabs, previous: previous)
            var tabs = snap.tabs
            var played: TabID?
            if snap.failure == nil, let plan = Self.plan(snap.tabs, active: now) {
                for t in plan.tabs {
                    guard let state = Self.run(browser, window: t.window, index: t.index, action: plan.action),
                          let i = tabs.firstIndex(where: { $0.window == t.window && $0.index == t.index }) else { continue }
                    tabs[i] = state
                    if plan.action == .play { played = TabID(t) }
                }
            }
            let result = Snapshot(tabs: tabs, failure: snap.failure)
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.commandRunning = false
                // Sofort den neuen Stand zeigen, sonst hinkt die Taste bis zur nächsten Abfrage.
                self.active = played ?? Self.active(result.tabs, previous: now)
                self.latest = result
                self.onChange?()
                Self.lastStart = .distantPast
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

    /// Fenster- und Tab-ID eines Tabs (bei Safari: Fenster-ID und Position).
    struct TabID: Equatable, Sendable {
        let window: Int
        let index: Int
        init(_ t: Tab) { window = t.window; index = t.index }
    }

    /// Zuletzt aktiver Tab: bleibt, solange er spielt oder (nichts spielt und) noch offen ist; sonst der erste spielende, sonst
    /// der erste Tab. So startet „Play“ das Video, das zuletzt lief, nicht einfach den ersten Tab (gemessen 17.11.).
    nonisolated static func active(_ tabs: [Tab], previous: TabID?) -> TabID? {
        let playing = tabs.filter { !$0.paused }
        if let p = previous, playing.contains(where: { TabID($0) == p }) { return p }
        if let first = playing.first { return TabID(first) }
        if let p = previous, tabs.contains(where: { TabID($0) == p }) { return p }
        return tabs.first.map(TabID.init)
    }

    /// Welcher Tab steht auf der Taste (Titel, Cover, Zustand): der aktive, sonst der erste.
    nonisolated static func displayed(_ tabs: [Tab], active: TabID?) -> Tab? {
        tabs.first { TabID($0) == active } ?? tabs.first
    }

    /// Was ein Druck tut: spielt etwas → alle spielenden pausieren; sonst den aktiven Tab starten. Ohne Tab nil.
    nonisolated static func plan(_ tabs: [Tab], active: TabID?) -> (action: Action, tabs: [Tab])? {
        let playing = tabs.filter { !$0.paused }
        if !playing.isEmpty { return (.pause, playing) }
        return displayed(tabs, active: active).map { (.play, [$0]) }
    }

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
    nonisolated static func tabScript(_ browser: DeckBrowser, window: Int, index: Int, action: Action) -> String? {
        tabScript(browser, window: window, index: index, javascript: javascript(action))
    }

    /// Wie oben für die festen Cover-Skripte. Nur Konstanten aus dieser Datei, nie Text von außen.
    nonisolated static func tabScript(_ browser: DeckBrowser, window: Int, index: Int, javascript js: String) -> String? {
        guard idRange.contains(window), idRange.contains(index) else { return nil }
        guard !js.contains("\"") && !js.contains("\\") else { return nil }
        let command = switch browser.dialect {
        case .chromium: "execute tab id \(index) of window id \(window) javascript \"\(js)\""
        case .safari: "do JavaScript \"\(js)\" in tab \(index) of window id \(window)"
        }
        return """
            with timeout of 5 seconds
                tell application id "\(browser.id)" to return \(command)
            end timeout
            """
    }

    // MARK: Ausführen (auf der Queue)

    private nonisolated static func isRunning(_ browser: DeckBrowser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).isEmpty
    }

    /// NSAppleScript ist nicht Sendable – hier erzeugt, nie geteilt.
    private nonisolated static func execute(_ source: String) -> (String?, Int?) {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (out?.stringValue, err?[NSAppleScript.errorNumber] as? Int)
    }

    nonisolated static func failure(_ code: Int, _ browser: DeckBrowser) -> Failure {
        switch code {
        case javascriptOffError(browser): .javascriptOff
        case AppleScriptSource.deniedError: .denied
        case AppleScriptSource.notRunningError: .notRunning
        default: .other
        }
    }

    /// Eine volle Messung (auf der Queue). Beim ersten Fehler wird abgebrochen: Alle Fehlerarten (Schalter aus, Automation
    /// verweigert, Zeitgrenze) gelten für den Browser insgesamt, weitere Tabs würden dasselbe melden. Bereits gelesene Tabs bleiben
    /// im Ergebnis, damit die Anzeige nicht flackert.
    private nonisolated static func measure(_ browser: DeckBrowser) -> Snapshot {
        guard isRunning(browser) else { return Snapshot(tabs: [], failure: .notRunning) }
        let (listing, error) = execute(listScript(browser))
        if let error { return Snapshot(tabs: [], failure: failure(error, browser)) }
        var tabs: [Tab] = []
        for c in candidates(from: listing ?? "") {
            guard let source = tabScript(browser, window: c.window, index: c.index, action: .read) else { continue }
            let (text, err) = execute(source)
            if let err { return Snapshot(tabs: tabs, failure: failure(err, browser)) }
            if let tab = text.flatMap({ parseState($0, window: c.window, index: c.index) }) { tabs.append(tab) }
        }
        return Snapshot(tabs: tabs, failure: nil)
    }

    private nonisolated static func run(_ browser: DeckBrowser, window: Int, index: Int, action: Action) -> Tab? {
        guard isRunning(browser), let source = tabScript(browser, window: window, index: index, action: action) else { return nil }
        let (text, error) = execute(source)
        if let error {
            // G8: nur die Fehlernummer, nie Inhalte.
            log.error("Browser-Tab: Befehl gescheitert (\(error, privacy: .public))")
            return nil
        }
        return text.flatMap { parseState($0, window: window, index: index) }
    }

    /// Ein Cover-Schritt (auf der Queue, nach `measure`). Fehler zählen als „kein Cover für dieses Video“, nie als Dauerversuch.
    nonisolated static func runCover(_ step: CoverStep, browser: DeckBrowser) -> CoverOutcome {
        switch step {
        case .none: return .none
        case .start(let t):
            guard isRunning(browser), let source = tabScript(browser, window: t.window, index: t.index, javascript: coverStartJavaScript) else {
                return .none
            }
            let (text, error) = execute(source)
            if let error { log.error("Browser-Tab: Cover nicht gestartet (\(error, privacy: .public))") }
            return text == "1" ? .started : .done(nil)
        case .collect(let t):
            guard isRunning(browser), let source = tabScript(browser, window: t.window, index: t.index, javascript: coverCollectJavaScript) else {
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

// MARK: Listenskript je Dialekt

extension BrowserTab {

    /// Listenskript: nur Adressen, kein JavaScript. Startet den Browser nie (`tell application id` ohne Laufprüfung würde ihn
    /// starten – die Prüfung steht davor in Swift und im Skript). Ausgabe je Tab: „Fenster⇥Tab⇥Adresse“. Bei Chromium sind Fenster
    /// und Tab IDs (stabil); bei Safari ist die Fenster-ID stabil, die „Tab-ID“ ist die Position im Fenster (1…n, Safari kennt
    /// keine Tab-IDs, gemessen am sdef 24.11.) – deshalb prüft das JavaScript im Tab den Host nochmal.
    nonisolated static func listScript(_ browser: DeckBrowser) -> String {
        let head = """
            if application id "\(browser.id)" is not running then return ""
            -- Tabulator VOR dem tell holen: im tell-Block liest AppleScript „tab“ als Klasse des Browsers (gemessen 17.11.).
            set tb to ASCII character 9
            with timeout of 5 seconds
                tell application id "\(browser.id)"
                    set out to ""
            """
        let body: String
        switch browser.dialect {
        case .chromium:
            body = """
                        repeat with w in windows
                            repeat with t in tabs of w
                                set out to out & (id of w) & tb & (id of t) & tb & (URL of t) & linefeed
                            end repeat
                        end repeat
                """
        case .safari:
            // URL kann bei leeren Tabs fehlen („missing value“): dann Adresse leer, Tab wird später verworfen.
            body = """
                        repeat with w in windows
                            set i to 0
                            repeat with t in tabs of w
                                set i to i + 1
                                set u to ""
                                try
                                    set u to URL of t
                                end try
                                set out to out & (id of w) & tb & i & tb & u & linefeed
                            end repeat
                        end repeat
                """
        }
        return head + "\n" + body + """

                    return out
                end tell
            end timeout
            """
    }
}
