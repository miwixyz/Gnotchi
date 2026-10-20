// SYNTHETISCH – Testwerkzeug, enthält keine Hördaten (Datenschutz-Gate, SECURE-DESIGN G16)
// Songtext-Treffer-Test (0.3.0-Recherche, Michael 20.10.): Wie oft findet LRCLIB zu dem, was Michael
// wirklich hört, synchronisierte Songtexte – getrennt nach Spotify, Apple Music, Browser (YouTube)?
//
// Datenschutz: Titel und Interpret stehen NUR im Arbeitsspeicher. In die Ergebnisdatei und auf die
// Konsole kommen ausschließlich Zähler. Die Titel gehen an lrclib.net – das ist der Test selbst
// (von Michael am 20.10. freigegeben).
//
// Aufruf: swiftc -O tools/lyrics-hitrate.swift -o /tmp/gnotchi-lyrics-hitrate
//         /tmp/gnotchi-lyrics-hitrate <Stunden> <Ergebnisdatei>
// Quelle: der Medien-Adapter aus /Applications/Gnotchi.app (wie Gnotchi selbst, nur lesend).
import Foundation

let hours = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 24
let outPath = CommandLine.arguments.dropFirst(2).first ?? "/tmp/gnotchi-lyrics-hitrate.json"
let app = "/Applications/Gnotchi.app/Contents"
let script = "\(app)/Resources/mediaremote-adapter.pl"
let framework = "\(app)/Frameworks/MediaRemoteAdapter.framework"
let userAgent = "Gnotchi-Treffertest/0.3 (https://github.com/miwixyz/Gnotchi)"

enum Result: String { case synced = "synchron", plain = "nur Text", instrumental, none = "nichts", error = "Fehler" }

// MARK: Quelle bestimmen (nur Bundle-ID)

func source(_ bundle: String?) -> String {
    switch bundle ?? "" {
    case "com.spotify.client": return "Spotify"
    case "com.apple.Music": return "Apple Music"
    case "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "net.imput.helium",
         "company.thebrowser.Browser", "org.mozilla.firefox": return "Browser"
    default: return "Andere"
    }
}

// MARK: Browser-Titel aufräumen („Interpret - Titel (Official Video)“)

func cleanBrowserTitle(_ t: String) -> (artist: String?, track: String) {
    var s = t
    for pattern in [#"\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|hd|4k|remaster)[^\)\]]*[\)\]]"#,
                    #"\s*\|.*$"#, #"\s+-\s+YouTube$"#] {
        s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }
    let parts = s.components(separatedBy: " - ")
    if parts.count >= 2 { return (parts[0].trimmingCharacters(in: .whitespaces),
                                  parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)) }
    return (nil, s.trimmingCharacters(in: .whitespaces))
}

// MARK: LRCLIB

/// Kurze Störungen (5xx, Netz weg) zählen nicht als „nichts gefunden“: 3 neue Versuche nach 5, 15, 45 s
/// (20.10.: erster Lauf bekam 503, Sekunden später wieder 200).
func fetch(_ path: String, _ query: [String: String]) -> (Int, Any?) {
    var result = fetchOnce(path, query)
    for wait in [5.0, 15, 45] where result.0 == 0 || result.0 >= 500 {
        Thread.sleep(forTimeInterval: wait)
        result = fetchOnce(path, query)
    }
    return result
}

func fetchOnce(_ path: String, _ query: [String: String]) -> (Int, Any?) {
    var c = URLComponents(string: "https://lrclib.net\(path)")!
    c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    var req = URLRequest(url: c.url!, timeoutInterval: 15)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    let done = DispatchSemaphore(value: 0)
    var status = 0
    var body: Any?
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let data { body = try? JSONSerialization.jsonObject(with: data) }
        done.signal()
    }.resume()
    done.wait()
    if status == 429 { Thread.sleep(forTimeInterval: 60) }
    return (status, body)
}

func classify(_ obj: [String: Any]) -> Result {
    if obj["instrumental"] as? Bool == true { return .instrumental }
    if let s = obj["syncedLyrics"] as? String, !s.isEmpty { return .synced }
    if let p = obj["plainLyrics"] as? String, !p.isEmpty { return .plain }
    return .none
}

func best(_ list: Any?) -> Result {
    let items = (list as? [[String: Any]]) ?? []
    let results = items.prefix(5).map(classify)
    for r in [Result.synced, .plain, .instrumental] where results.contains(r) { return r }
    return .none
}

/// Erst exakt (/api/get mit Dauer), dann Suche. Liefert Ergebnis und Weg.
func lookup(track: String, artist: String?, album: String?, duration: Int?, browser: Bool) -> (Result, String) {
    var t = track, a = artist
    var prefix = ""
    if browser { let c = cleanBrowserTitle(track); t = c.track; a = c.artist ?? artist }
    if let a, let duration, !browser {
        var q = ["track_name": t, "artist_name": a, "duration": String(duration)]
        if let album, !album.isEmpty { q["album_name"] = album }
        // Ohne Wiederholung: /api/get antwortete am 20.10. bei Titeln ohne Treffer dauerhaft 503, beim
        // Doku-Beispiel sofort 200 – Vermutung: 503 = Nachsuche bei Fremdquellen gescheitert. Dann zur Suche.
        let (st, body) = fetchOnce("/api/get", q)
        if st == 200, let obj = body as? [String: Any] { return (classify(obj), "get") }
        prefix = st == 404 ? "get 404 → " : "get \(st) → "
    }
    if let a {
        let (st, body) = fetch("/api/search", ["track_name": t, "artist_name": a])
        if st == 200 { let r = best(body); if r != .none { return (r, prefix + "search") } }
    }
    let (st, body) = fetch("/api/search", ["q": a.map { "\($0) \(t)" } ?? t])
    if st == 200 { return (best(body), prefix + "search-q") }
    return (.error, prefix + "search \(st)")
}

// MARK: Zähler (nur Zahlen auf Platte)

var counts: [String: [String: Int]] = [:]
var paths: [String: Int] = [:]
var seen = Set<String>()        // nur im Arbeitsspeicher
let started = Date()

func save() {
    let summary: [String: Any] = [
        "gestartet": ISO8601DateFormatter().string(from: started),
        "stand": ISO8601DateFormatter().string(from: Date()),
        "titel_gesamt": seen.count,
        "je_quelle": counts,
        "treffer_weg": paths,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
    }
}

/// Eine Adapter-Zeile auswerten (Strom oder einmalige Abfrage beim Start).
func handle(_ line: Data) {
    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let p = obj["payload"] as? [String: Any],
      let title = p["title"] as? String, !title.isEmpty,
      p["playing"] as? Bool == true else { return }
    let artist = (p["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let key = "\(artist ?? "")\u{1F}\(title)"
    guard !seen.contains(key) else { return }
    seen.insert(key)
    let bundle = (p["parentApplicationBundleIdentifier"] as? String) ?? (p["bundleIdentifier"] as? String)
    let src = source(bundle)
    let duration = (p["durationMicros"] as? Double).map { Int(($0 / 1_000_000).rounded()) }
    let (result, path) = lookup(track: title, artist: artist, album: p["album"] as? String,
                                duration: duration, browser: src == "Browser")
    counts[src, default: [:]][result.rawValue, default: 0] += 1
    paths["\(src): \(path)", default: 0] += 1
    save()
    print("\(Date().formatted(date: .omitted, time: .standard)) \(src): \(result.rawValue) (\(path)) – gesamt \(seen.count)")
    fflush(stdout)
}

// MARK: Adapter-Strom

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
proc.arguments = [script, framework, "stream", "--no-diff", "--micros", "--debounce=1000"]
proc.environment = ["PATH": "/usr/bin:/bin"]
let pipe = Pipe()
proc.standardOutput = pipe
proc.standardError = FileHandle.nullDevice
try proc.run()

let deadline = started.addingTimeInterval(hours * 3600)
DispatchQueue.global().asyncAfter(deadline: .now() + hours * 3600) { proc.terminate() }
save()
// Der Strom meldet nur Änderungen – den Titel, der beim Start schon läuft, einmal abfragen.
let get = Process()
get.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
get.arguments = [script, framework, "get", "--micros"]
get.environment = ["PATH": "/usr/bin:/bin"]
let getPipe = Pipe()
get.standardOutput = getPipe
get.standardError = FileHandle.nullDevice
if (try? get.run()) != nil {
    let data = getPipe.fileHandleForReading.readDataToEndOfFile()
    get.waitUntilExit()
    handle(Data(#"{"payload":"#.utf8) + data + Data("}".utf8))
}
print("läuft bis \(deadline.formatted(date: .numeric, time: .shortened)), Ergebnis: \(outPath)")
fflush(stdout)

var buffer = Data()
let handle = pipe.fileHandleForReading
while true {
    let chunk = handle.availableData
    if chunk.isEmpty { break }
    buffer.append(chunk)
    while let nl = buffer.firstIndex(of: 0x0A) {
        let line = buffer[buffer.startIndex..<nl]
        buffer.removeSubrange(buffer.startIndex...nl)
        handle(line)
    }
}
save()
print("fertig")
