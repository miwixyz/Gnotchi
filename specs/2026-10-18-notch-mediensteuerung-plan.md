# Notch-Mediensteuerung – Implementation Plan

> **Herkunft:** Entstanden am 18.10. im Seam-Repo (Zweig feature/notch-medien), am 18.10. nach Gnotchi verschoben; Aufgaben 1–7 umgesetzt, Aufgaben 8–15 folgen hier; Seam-Bezüge (Engine, Abdunkeln, SettingsView) gelten sinngemäß für Gnotchi. Pfade: `Seam/Notch/*` → `Gnotchi/Media/*`, `SeamTests/` → `GnotchiTests/`; Sicherheitsentscheidungen E17a–i → `docs/SECURE-DESIGN.md` G2–G10. Übernommen aus Seam-Commit dc0e71d.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seam zeigt in der Notch (bzw. als Pille oben mittig) den laufenden Titel jeder Quelle und steuert Play/Pause, Weiter, Zurück, Spulen – im macOS-Systemstil.

**Architecture:** Ein eingespielter `mediaremote-adapter` (BSD-3) wird als Framework + Test-Programm von Seams Build gebaut und im Bundle mitgeliefert. Seam startet `/usr/bin/perl <Skript> <Framework> stream …` als Kindprozess, liest JSON-Zeilen, normalisiert sie zu `NowPlayingInfo` und zeigt sie in einem `NSPanel` je Bildschirm. Vor jedem Start prüft Seam die Signatur des eigenen Bundles (E17a).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, XcodeGen (`project.yml`), XCTest, Objective-C (Adapter, unverändert), Security.framework, ImageIO.

**Quellen:** Spezifikation `specs/2026-10-18-notch-mediensteuerung.md` · Sicherheitsentwurf `docs/SECURE-DESIGN.md` E17.

---

## Vorab: Was der Ausführende über dieses Repo wissen muss

- **`docs/` ist die Website.** Pläne/Spezifikationen liegen in `specs/`.
- **Projekt ist generiert:** nach jeder Änderung an `project.yml` → `make gen`. `Seam.xcodeproj` nie von Hand ändern.
- **Tests:** `make test` (alle) oder einzeln:
  ```bash
  make gen && xcodebuild -project Seam.xcodeproj -scheme Seam -destination 'platform=macOS' \
    -derivedDataPath build -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates \
    test -only-testing:SeamTests/<Klasse>
  ```
  Der Test-Host ist die App selbst; im Testlauf startet Seam keine Beobachter (`Engine.isRunningTests`).
- **Lint:** `make lint` muss sauber sein (SwiftLint, `.swiftlint.yml`).
- **Protokoll:** `Logger(subsystem: "dev.mwlr.seam", category: "medien")`. **Nie Titel/Interpret ins Protokoll** (E17g).
- **Einstellungen:** `Seam/Core/Preferences.swift` (`@Observable`, `UserDefaults`, Schlüssel in `enum Key`).
- **Kommentare auf Deutsch**, kurz, mit „warum“.
- **Gemessen 18.10.:** Adapter läuft unter macOS 27.0.1. `seek` erwartet beim Perl-Skript **Mikrosekunden** (die Homebrew-CLI nahm Sekunden). Befehls-IDs: play 0, pause 1, toggle 2, next 4, previous 5.

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `Vendor/mediaremote-adapter/…` | Adapter-Quelltext, fester Commit `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd`, unverändert |
| `Vendor/mediaremote-adapter/VENDOR.md` | Herkunft, SHA, Update-Verfahren |
| `project.yml` | zwei neue Targets + Einbettung in Seam |
| `Seam/Notch/NowPlayingInfo.swift` | JSON-Zeile → bereinigter Zustand, Fortschritt hochrechnen |
| `Seam/Notch/LineSplitter.swift` | Bytes → Zeilen, Längenlimit |
| `Seam/Notch/Artwork.swift` | Cover begrenzt dekodieren |
| `Seam/Notch/BundleIntegrity.swift` | Signaturprüfung des eigenen Bundles |
| `Seam/Notch/MediaAdapter.swift` | Kindprozess: test, stream, Befehle, Neustart |
| `Seam/Notch/NowPlayingModel.swift` | `@Observable` Zustand für die Oberfläche |
| `Seam/Notch/IslandGeometry.swift` | Notch-/Pillen-Maße (reine Rechnung) |
| `Seam/Notch/IslandController.swift` | Panels je Bildschirm, Hover, Vollbild |
| `Seam/Notch/IslandView.swift` | SwiftUI-Ansicht klein/groß |
| `SeamTests/NowPlayingInfoTests.swift` … | je ein Test pro reinem Baustein |

---

### Task 1: Adapter-Quelltext einspielen

**Files:**
- Create: `Vendor/mediaremote-adapter/` (aus GitHub, fester SHA)
- Create: `Vendor/mediaremote-adapter/VENDOR.md`
- Modify: `Seam/Resources/THIRD-PARTY-LICENSES.md`

- [ ] **Step 1: Quelltext am festen Commit holen**

```bash
cd ~/Coding/Seam
SHA=0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd
TMP=$(mktemp -d /tmp/mra.XXXXXX)
git clone --quiet https://github.com/ungive/mediaremote-adapter.git "$TMP/src"
git -C "$TMP/src" checkout --quiet "$SHA"
mkdir -p Vendor/mediaremote-adapter
for p in LICENSE README.md bin include src; do cp -R "$TMP/src/$p" Vendor/mediaremote-adapter/; done
rm -rf Vendor/mediaremote-adapter/src/test/.gitkeep 2>/dev/null || true
git -C "$TMP/src" log -1 --format='%H %cI'
```
Expected: `0e82bf1c… 2026-10-17T…`

- [ ] **Step 2: Perl-Skript lesen (Pflicht, E17 Negativraum 2)**

```bash
wc -l Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl
grep -nE 'system|exec|`|open\(|unlink|curl|http' Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl
```
Expected: 290 Zeilen; keine Treffer außer Hilfetext. Jeden Treffer ansehen und im Commit-Text begründen.

- [ ] **Step 3: `VENDOR.md` schreiben**

```markdown
# mediaremote-adapter (eingespielt)

- Quelle: https://github.com/ungive/mediaremote-adapter
- Commit: 0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd (2026-10-17)
- Lizenz: BSD-3-Clause (`LICENSE`)
- Unverändert übernommen: `bin/`, `include/`, `src/`, `LICENSE`, `README.md`

## Update-Verfahren (docs/SECURE-DESIGN.md E17)

1. Neuen Commit klonen, `diff -r` gegen diesen Ordner, **jede** Änderung am Perl-Skript lesen.
2. Ordner ersetzen, SHA hier eintragen.
3. `make test` + Sichttest (Insel zeigt Spotify und einen Browser).
Die Signatur des Bundles deckt Skript und Framework ab; eine Prüfsumme muss nicht gepflegt werden.
```

- [ ] **Step 4: Lizenz in `Seam/Resources/THIRD-PARTY-LICENSES.md` ergänzen**

Den Einleitungssatz von „zwei Komponenten“ auf „drei Komponenten“ ändern und „sowie (ab 0.7.0) den Medien-Adapter mediaremote-adapter“ ergänzen. Am Dateiende anhängen:

```markdown
---

## mediaremote-adapter

Quelle: https://github.com/ungive/mediaremote-adapter (Commit 0e82bf1c)
Verwendet für die Mediensteuerung in der Notch.

```
Danach den Lizenztext anhängen:
```bash
cat Vendor/mediaremote-adapter/LICENSE >> Seam/Resources/THIRD-PARTY-LICENSES.md
```

- [ ] **Step 5: Commit**

```bash
git add Vendor/mediaremote-adapter Seam/Resources/THIRD-PARTY-LICENSES.md
git commit -m "mediaremote-adapter 0e82bf1 eingespielt (BSD-3), Lizenzhinweis

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Adapter mit Seams Build bauen und einbetten

**Files:**
- Modify: `project.yml`
- Modify: `scripts/install-signed.sh:29-33`

- [ ] **Step 1: Zwei Targets in `project.yml` anlegen** (unter `targets:`, nach `SeamTests`)

```yaml
  # Medien-Adapter (Vendor/, BSD-3). Seam lädt dieses Framework NIE selbst:
  # /usr/bin/perl lädt es als Kindprozess (docs/SECURE-DESIGN.md E17). Deshalb
  # eingebettet, aber nicht gelinkt.
  MediaRemoteAdapter:
    type: framework
    platform: macOS
    sources:
      - path: Vendor/mediaremote-adapter/src/adapter
      - path: Vendor/mediaremote-adapter/src/private
      - path: Vendor/mediaremote-adapter/src/utility
      - path: Vendor/mediaremote-adapter/include
        buildPhase: headers
        headerVisibility: public
    dependencies:
      - sdk: Foundation.framework
      - sdk: AppKit.framework
      - sdk: UniformTypeIdentifiers.framework
    settings:
      base:
        PRODUCT_NAME: MediaRemoteAdapter
        PRODUCT_BUNDLE_IDENTIFIER: dev.mwlr.seam.mediaremoteadapter
        GENERATE_INFOPLIST_FILE: YES
        CLANG_ENABLE_OBJC_ARC: YES
        HEADER_SEARCH_PATHS: "$(SRCROOT)/Vendor/mediaremote-adapter/src $(SRCROOT)/Vendor/mediaremote-adapter/include"
        OTHER_CFLAGS: "-fvisibility=default"
        DEFINES_MODULE: NO
        SKIP_INSTALL: YES
        ENABLE_HARDENED_RUNTIME: YES
        GCC_TREAT_WARNINGS_AS_ERRORS: NO

  MediaRemoteAdapterTestClient:
    type: tool
    platform: macOS
    sources:
      - path: Vendor/mediaremote-adapter/src/test
    dependencies:
      - sdk: Foundation.framework
      - sdk: AppKit.framework
    settings:
      base:
        PRODUCT_NAME: MediaRemoteAdapterTestClient
        PRODUCT_BUNDLE_IDENTIFIER: dev.mwlr.seam.mediaremoteadapter.testclient
        CLANG_ENABLE_OBJC_ARC: YES
        HEADER_SEARCH_PATHS: "$(SRCROOT)/Vendor/mediaremote-adapter/src $(SRCROOT)/Vendor/mediaremote-adapter/include"
        SKIP_INSTALL: YES
        ENABLE_HARDENED_RUNTIME: YES
```

Im Target `Seam` unter `dependencies:` ergänzen und unter `resources:` das Skript:

```yaml
      - target: MediaRemoteAdapter
        embed: true
        link: false
        codeSign: true
      - target: MediaRemoteAdapterTestClient
        embed: true
        link: false
        codeSign: true
        copy:
          destination: executables
```
```yaml
      - path: Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl
```

- [ ] **Step 2: Bauen und Lage prüfen**

```bash
make build 2>&1 | grep -E 'error:|BUILD' | tail -3
APP=build/Build/Products/Debug/Seam.app
ls "$APP/Contents/Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter" \
   "$APP/Contents/MacOS/MediaRemoteAdapterTestClient" \
   "$APP/Contents/Resources/mediaremote-adapter.pl"
otool -L "$APP/Contents/MacOS/Seam" | grep -c MediaRemoteAdapter
```
Expected: `** BUILD SUCCEEDED **`, drei Pfade vorhanden, letzter Befehl `0` (Seam linkt den Adapter nicht).
Scheitert der Test-Client am Linken: in `Vendor/mediaremote-adapter/CMakeLists.txt` den Abschnitt `add_executable(… TEST_CLIENT …)` lesen und dessen `target_link_libraries`/Quellen 1:1 in das Target übernehmen.

- [ ] **Step 3: Adapter aus dem Bundle von Hand testen**

```bash
APP=build/Build/Products/Debug/Seam.app
/usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" \
  "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" \
  "$APP/Contents/MacOS/MediaRemoteAdapterTestClient" test; echo "exit=$?"
```
Expected: `exit=0`. (Unsigniert gebaut – bestätigt nebenbei, dass Perl keine Signatur verlangt.)

- [ ] **Step 4: `scripts/install-signed.sh` – Adapter vor der App signieren**

Nach der Sparkle-Schleife (vor `codesign … "$STAGE/Seam.app"`) einfügen:

```sh
# Medien-Adapter (E17): eigene Teile von innen nach außen signieren, ohne Seams Berechtigungen.
for part in "$STAGE/Seam.app/Contents/MacOS/MediaRemoteAdapterTestClient" \
            "$STAGE/Seam.app/Contents/Frameworks/MediaRemoteAdapter.framework"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$part"
done
```

- [ ] **Step 5: Commit**

```bash
git add project.yml scripts/install-signed.sh
git commit -m "Adapter als Framework + Test-Programm bauen, eingebettet, nicht gelinkt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Zeilen aus dem Strom schneiden (`LineSplitter`)

**Files:**
- Create: `Seam/Notch/LineSplitter.swift`
- Test: `SeamTests/LineSplitterTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Seam

/// E17c: Strom zeilenweise, überlange Zeilen verwerfen statt Speicher fluten.
final class LineSplitterTests: XCTestCase {

    func testSplitsAcrossChunks() {
        var s = LineSplitter(maxLineBytes: 100)
        XCTAssertEqual(s.feed(Data("{\"a\":1}\n{\"b\"".utf8)), [Data("{\"a\":1}".utf8)])
        XCTAssertEqual(s.feed(Data(":2}\n".utf8)), [Data("{\"b\":2}".utf8)])
    }

    func testDropsOverlongLineAndCounts() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("1234567890\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(s.dropped, 1)
    }

    func testOverlongAcrossChunksStaysDropped() {
        var s = LineSplitter(maxLineBytes: 5)
        XCTAssertEqual(s.feed(Data("123456".utf8)), [])
        XCTAssertEqual(s.feed(Data("789\nok\n".utf8)), [Data("ok".utf8)])
        XCTAssertEqual(s.dropped, 1)
    }

    func testIgnoresEmptyLines() {
        var s = LineSplitter(maxLineBytes: 10)
        XCTAssertEqual(s.feed(Data("\n\nx\n".utf8)), [Data("x".utf8)])
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`cannot find 'LineSplitter' in scope`)

```bash
make gen && xcodebuild -project Seam.xcodeproj -scheme Seam -destination 'platform=macOS' -derivedDataPath build -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates test -only-testing:SeamTests/LineSplitterTests 2>&1 | tail -5
```

- [ ] **Step 3: Implementation**

```swift
import Foundation

/// Schneidet den stdout-Strom des Adapters in Zeilen (E17c). Eine Zeile über
/// `maxLineBytes` wird komplett verworfen und gezählt – auch wenn sie über mehrere
/// Pakete verteilt ankommt –, damit ein entgleister Strom Seam nicht volllaufen lässt.
struct LineSplitter {
    let maxLineBytes: Int
    private(set) var dropped = 0
    private var buffer = Data()
    private var skipping = false

    init(maxLineBytes: Int) { self.maxLineBytes = maxLineBytes }

    mutating func feed(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        for byte in chunk {
            if byte == 0x0A {
                if skipping {
                    skipping = false
                } else if !buffer.isEmpty {
                    lines.append(buffer)
                }
                buffer.removeAll(keepingCapacity: true)
                continue
            }
            guard !skipping else { continue }
            buffer.append(byte)
            if buffer.count > maxLineBytes {
                dropped += 1
                skipping = true
                buffer.removeAll(keepingCapacity: true)
            }
        }
        return lines
    }
}
```

- [ ] **Step 4: Run – expect PASS** (gleicher Befehl wie Step 2)

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/LineSplitter.swift SeamTests/LineSplitterTests.swift
git commit -m "LineSplitter: Adapter-Strom zeilenweise mit Laengenlimit (E17c)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: JSON-Zeile → `NowPlayingInfo`

**Files:**
- Create: `Seam/Notch/NowPlayingInfo.swift`
- Test: `SeamTests/NowPlayingInfoTests.swift`

Testzeilen entsprechen dem Mitschnitt `spike/nowplaying-mitschnitt-2026-10-18.jsonl`, umgeschrieben auf das `--micros`-Format, das Seam nutzt.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Seam

/// E17c/E17d + Mitschnitt 18.10.: Was aus dem Strom wird.
final class NowPlayingInfoTests: XCTestCase {

    private let spotify = #"{"type":"data","diff":false,"payload":{"playbackRate":1,"album":"Beispielalbum","bundleIdentifier":"com.spotify.client","title":"Beispieltitel Eins","artist":"Testband","durationMicros":206937000,"elapsedTimeMicros":30004000,"timestampEpochMicros":1792312654000000,"contentItemIdentifier":"8A34","playing":true}}"#
    private let safari = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"DEMO-MIX 2026","artist":"DEMO-KANAL official","durationMicros":3600000000,"elapsedTimeMicros":0,"timestampEpochMicros":1792312654000000,"playing":true,"playbackRate":1}}"#
    private let heliumFirst = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"net.imput.helium","title":"DEMO-MIX 2026","artist":"","playing":true}}"#
    private let empty = #"{"type":"data","diff":false,"payload":{}}"#

    private func parse(_ s: String) -> NowPlayingInfo? {
        NowPlayingInfo.parse(line: Data(s.utf8))
    }

    func testSpotify() throws {
        let i = try XCTUnwrap(parse(spotify))
        XCTAssertEqual(i.title, "Beispieltitel Eins")
        XCTAssertEqual(i.artist, "Testband")
        XCTAssertEqual(i.appBundleID, "com.spotify.client")
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(try XCTUnwrap(i.duration), 206.937, accuracy: 0.001)
        XCTAssertFalse(i.isIncomplete)
    }

    func testSafariUsesParentApp() throws {
        XCTAssertEqual(try XCTUnwrap(parse(safari)).appBundleID, "com.apple.Safari")
    }

    func testBrowserFirstEventIsIncomplete() throws {
        let i = try XCTUnwrap(parse(heliumFirst))
        XCTAssertNil(i.artist)
        XCTAssertTrue(i.isIncomplete)
    }

    func testEmptyPayloadMeansNothingPlays() {
        XCTAssertNil(parse(empty))
    }

    func testGarbageIsNil() {
        XCTAssertNil(parse("kein json"))
        XCTAssertNil(parse(#"{"type":"data","payload":"x"}"#))
    }

    func testSanitizeRemovesControlAndBidiAndTruncates() {
        XCTAssertEqual(NowPlayingInfo.sanitize("A\u{202E}B\u{0007}C\u{2066}"), "ABC")
        XCTAssertEqual(NowPlayingInfo.sanitize(String(repeating: "x", count: 400))?.count, 300)
        XCTAssertNil(NowPlayingInfo.sanitize("  \u{202E} "))
    }

    func testElapsedRunsOnWhilePlaying() throws {
        let i = try XCTUnwrap(parse(spotify))
        let t0 = Date(timeIntervalSince1970: 1_792_312_654)
        XCTAssertEqual(i.elapsed(at: t0.addingTimeInterval(10)), 40.004, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: t0.addingTimeInterval(10_000)), 206.937, accuracy: 0.001)  // nie über Dauer
    }

    func testElapsedStandsWhenPaused() throws {
        let paused = spotify.replacingOccurrences(of: #""playbackRate":1"#, with: #""playbackRate":0"#)
            .replacingOccurrences(of: #""playing":true"#, with: #""playing":false"#)
        let i = try XCTUnwrap(parse(paused))
        XCTAssertEqual(i.elapsed(at: Date(timeIntervalSince1970: 1_792_312_754)), 30.004, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/NowPlayingInfoTests`)

- [ ] **Step 3: Implementation**

```swift
import Foundation

/// Bereinigter Wiedergabe-Zustand aus einer Adapter-Zeile (E17c). Alles, was hier
/// ankommt, kann eine beliebige Website gesetzt haben – deshalb gekürzt und ohne
/// Steuer- und Richtungszeichen.
struct NowPlayingInfo: Equatable, Sendable {
    let title: String
    let artist: String?
    let album: String?
    /// App für Symbol/Name. Safari meldet den WebKit-Hilfsprozess → Eltern-App (Mitschnitt 18.10.).
    let appBundleID: String?
    let isPlaying: Bool
    let duration: TimeInterval?
    let elapsedAtStamp: TimeInterval
    let stamp: Date
    let rate: Double
    let contentID: String?
    /// Base64, noch nicht dekodiert (Artwork.decode begrenzt Größe und Typ).
    let artworkBase64: String?

    static let maxTextLength = 300

    /// Browser liefern zuerst Titel ohne Interpret/Dauer (Mitschnitt 18.10.).
    var isIncomplete: Bool { artist == nil || duration == nil }

    func elapsed(at now: Date) -> TimeInterval {
        let run = isPlaying ? now.timeIntervalSince(stamp) * rate : 0
        let value = max(0, elapsedAtStamp + run)
        return duration.map { min(value, $0) } ?? value
    }

    private struct Envelope: Decodable { let payload: Payload? }
    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let playing: Bool?
        let playbackRate: Double?
        let durationMicros: Double?
        let elapsedTimeMicros: Double?
        let timestampEpochMicros: Double?
        let contentItemIdentifier: String?
        let artworkData: String?
    }

    static func parse(line: Data) -> NowPlayingInfo? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: line),
              let p = env.payload, let title = sanitize(p.title) else { return nil }
        let playing = p.playing ?? false
        return NowPlayingInfo(
            title: title,
            artist: sanitize(p.artist),
            album: sanitize(p.album),
            appBundleID: bundleID(p.parentApplicationBundleIdentifier) ?? bundleID(p.bundleIdentifier),
            isPlaying: playing,
            duration: p.durationMicros.flatMap { $0 > 0 ? $0 / 1_000_000 : nil },
            elapsedAtStamp: (p.elapsedTimeMicros ?? 0) / 1_000_000,
            stamp: p.timestampEpochMicros.map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date(),
            rate: p.playbackRate ?? (playing ? 1 : 0),
            contentID: sanitize(p.contentItemIdentifier),
            artworkBase64: p.artworkData)
    }

    /// Kürzen, Steuerzeichen und Richtungs-Überschreibungen (U+202A–202E, U+2066–2069) weg.
    static func sanitize(_ s: String?) -> String? {
        guard let s else { return nil }
        let bidi: ClosedRange<UInt32> = 0x202A...0x202E
        let isolate: ClosedRange<UInt32> = 0x2066...0x2069
        let kept = s.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !bidi.contains($0.value) && !isolate.contains($0.value)
        }
        let cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxTextLength))
    }

    /// Nur plausible Bundle-IDs weiterreichen (gleiche Prüfung wie bei den Link-Regeln).
    private static func bundleID(_ s: String?) -> String? {
        guard let s, LinkRules.isBundleID(s) else { return nil }
        return s
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/NowPlayingInfo.swift SeamTests/NowPlayingInfoTests.swift
git commit -m "NowPlayingInfo: Adapter-Zeile bereinigen, Safari-Eltern-App, Fortschritt

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Cover begrenzt dekodieren

**Files:**
- Create: `Seam/Notch/Artwork.swift`
- Test: `SeamTests/ArtworkTests.swift`

- [ ] **Step 1: Failing test**

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Seam

/// E17e: nur JPEG/PNG/HEIC, Base64 ≤ 2 MB, verkleinert auf ≤ 256 px.
final class ArtworkTests: XCTestCase {

    private func image(_ type: UTType, size: Int) -> Data {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testPNGDecodesAndShrinks() throws {
        let cg = try XCTUnwrap(Artwork.decode(base64: image(.png, size: 600).base64EncodedString()))
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 256)
    }

    func testGIFRejected() {
        XCTAssertNil(Artwork.decode(base64: image(.gif, size: 20).base64EncodedString()))
    }

    func testGarbageRejected() {
        XCTAssertNil(Artwork.decode(base64: Data("kein bild".utf8).base64EncodedString()))
        XCTAssertNil(Artwork.decode(base64: "%%%"))
    }

    func testOversizeRejectedBeforeDecoding() {
        XCTAssertNil(Artwork.decode(base64: String(repeating: "A", count: Artwork.maxBase64Bytes + 4)))
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/ArtworkTests`)

- [ ] **Step 3: Implementation**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cover aus dem Adapter-Strom (E17e). Bilddaten kommen von beliebigen Websites;
/// ImageIO ist der Systemparser, wir begrenzen nur, was er zu sehen bekommt.
enum Artwork {
    static let maxBase64Bytes = 2 * 1024 * 1024
    static let maxPixel = 256
    private static let allowed: Set<String> = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]

    static func decode(base64: String) -> CGImage? {
        guard base64.utf8.count <= maxBase64Bytes,
              let data = Data(base64Encoded: base64),
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(src) as String?, allowed.contains(type) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/Artwork.swift SeamTests/ArtworkTests.swift
git commit -m "Artwork: Cover nur JPEG/PNG/HEIC, Groesse begrenzt, verkleinert (E17e)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Signatur des eigenen Bundles prüfen (E17a)

**Files:**
- Create: `Seam/Notch/BundleIntegrity.swift`
- Test: `SeamTests/BundleIntegrityTests.swift`

Warum Signatur statt Prüfsumme: Das Signieren verändert die Framework-Datei *nach* dem Kompilieren; eine eingebaute Prüfsumme wäre nie gültig. Die Bundle-Signatur versiegelt Skript (Ressource), Framework und Test-Programm (eingebetteter Code) zugleich.

- [ ] **Step 1: Failing test** (baut sich ein eigenes, ad hoc signiertes Mini-Bundle – unabhängig vom Test-Host)

```swift
import XCTest
@testable import Seam

/// E17a: Seam startet den Adapter nur aus einem unveränderten, signierten Bundle.
final class BundleIntegrityTests: XCTestCase {

    private func makeSignedBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Probe.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("MacOS/Probe").path)
        try Data("print 1;\n".utf8).write(to: app.appendingPathComponent("Resources/skript.pl"))
        let plist: [String: Any] = ["CFBundleExecutable": "Probe", "CFBundleIdentifier": "dev.mwlr.seam.probe",
                                    "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", root.appendingPathComponent("Probe.app").path]
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
        return root.appendingPathComponent("Probe.app")
    }

    func testIntactBundlePasses() throws {
        XCTAssertTrue(BundleIntegrity.isIntact(try makeSignedBundle()))
    }

    func testChangedScriptFails() throws {
        let app = try makeSignedBundle()
        try Data("system('evil');\n".utf8).write(to: app.appendingPathComponent("Contents/Resources/skript.pl"))
        XCTAssertFalse(BundleIntegrity.isIntact(app))
    }

    func testUnsignedFails() {
        XCTAssertFalse(BundleIntegrity.isIntact(URL(fileURLWithPath: "/tmp/gibt-es-nicht.app")))
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/BundleIntegrityTests`)

- [ ] **Step 3: Implementation**

```swift
import Foundation
import Security

/// E17a: /usr/bin/perl prüft keine Signatur. Bevor Seam den Adapter startet, muss das
/// eigene Bundle unverändert sein – Ressourcen (Perl-Skript) und eingebetteter Code
/// (Framework, Test-Programm) sind von der Signatur versiegelt.
enum BundleIntegrity {
    static func isIntact(_ bundleURL: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: SECURE-DESIGN E17a anpassen**

In `docs/SECURE-DESIGN.md` den Absatz **E17a** ersetzen durch:

```markdown
- **E17a – Bundle-Signatur vor jedem Start (Kern).** `/usr/bin/perl` prüft keine Signatur und lädt das
  Framework ohne Bibliotheksprüfung (belegt: die Homebrew-Fassung ist nur ad hoc signiert und
  läuft trotzdem, 18.10.). Seam ist Kind-Prozess-„verantwortlich“; **vermutet, nicht gemessen:**
  TCC rechnet dem Perl-Prozess dann Seams Freigaben zu. Deshalb prüft Seam vor jedem Start
  `SecStaticCodeCheckValidity` auf das eigene Bundle (verschachtelter Code + Ressourcen, strikt).
  Ungültig → kein Start, Hinweis in den Einstellungen, ein Protokolleintrag.
  *Verworfen:* eingebaute SHA-256-Prüfsumme – das Signieren verändert die Framework-Datei nach
  dem Kompilieren, die Konstante wäre nie gültig (Fund 18.10. beim Planen). *Verworfen:*
  `responsibility_spawnattrs_setdisclaim` – private Schnittstelle. *Restrisiko:* Zeitfenster
  zwischen Prüfung und Laden durch Perl; braucht Schreibrecht auf Seam.app *und* exaktes Timing.
  *Messen im Sichttest:* erbt der Kindprozess die Freigabe? Ergebnis hier nachtragen.
```

In **E17h** „per `sysctl`/`proc_pidpath`“ ersetzen durch „per `pgrep -f <vollständiger Skriptpfad im Bundle>` ohne Shell, eigene PID ausgeschlossen“.

- [ ] **Step 6: Commit**

```bash
git add Seam/Notch/BundleIntegrity.swift SeamTests/BundleIntegrityTests.swift docs/SECURE-DESIGN.md
git commit -m "BundleIntegrity: Signatur des eigenen Bundles vor Adapter-Start (E17a)

Pruefsumme verworfen: Signieren aendert das Framework nach dem Build.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Kindprozess führen (`MediaAdapter`)

**Files:**
- Create: `Seam/Notch/MediaAdapter.swift`
- Test: `SeamTests/MediaAdapterTests.swift` (nur reine Teile: Wartezeiten, Argumente)

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Seam

/// E17b/E17h: feste Argumente, Neustart mit wachsender Pause, nach 3 Abbrüchen Schluss.
final class MediaAdapterTests: XCTestCase {

    private let paths = MediaAdapter.Paths(
        script: URL(fileURLWithPath: "/A/Seam.app/Contents/Resources/mediaremote-adapter.pl"),
        framework: URL(fileURLWithPath: "/A/Seam.app/Contents/Frameworks/MediaRemoteAdapter.framework"),
        testClient: URL(fileURLWithPath: "/A/Seam.app/Contents/MacOS/MediaRemoteAdapterTestClient"))

    func testBackoff() {
        XCTAssertEqual(MediaAdapter.restartDelay(afterFailures: 1), 1)
        XCTAssertEqual(MediaAdapter.restartDelay(afterFailures: 2), 5)
        XCTAssertNil(MediaAdapter.restartDelay(afterFailures: 3))
    }

    func testStreamArguments() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .stream),
                       [paths.script.path, paths.framework.path, "stream", "--no-diff", "--micros", "--debounce=100"])
    }

    func testTestArgumentsIncludeClient() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .test),
                       [paths.script.path, paths.framework.path, paths.testClient.path, "test"])
    }

    func testCleanEnvironmentHasNoPerlVariables() {
        // E17b (Review 18.10.): PERL5OPT/PERL5LIB per `launchctl setenv` würden sonst fremden Code laden.
        XCTAssertEqual(MediaAdapter.cleanEnvironment, ["PATH": "/usr/bin:/bin"])
    }

    func testCommandAndSeekArguments() {
        XCTAssertEqual(MediaAdapter.arguments(paths, .send(.toggle)).suffix(2), ["send", "2"])
        // Perl-Skript erwartet Mikrosekunden (gemessen 18.10.), begrenzt auf ≥ 0.
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(61.5)).suffix(2), ["seek", "61500000"])
        XCTAssertEqual(MediaAdapter.arguments(paths, .seek(-3)).suffix(2), ["seek", "0"])
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/MediaAdapterTests`)

- [ ] **Step 3: Implementation**

```swift
import Foundation
import OSLog
import Security

/// Führt `/usr/bin/perl mediaremote-adapter.pl …` als Kindprozess (docs/SECURE-DESIGN.md E17).
/// Pfade nur aus dem signierten Bundle, Argumente fest, keine Shell (E17b).
@MainActor
final class MediaAdapter {

    enum Command: Int { case play = 0, pause = 1, toggle = 2, next = 4, previous = 5 }
    enum Call { case stream, test, send(Command), seek(TimeInterval) }
    enum State: Equatable { case starting, running, unavailable(String) }

    struct Paths: Equatable {
        let script: URL
        let framework: URL
        let testClient: URL

        static func bundled(_ b: Bundle = .main) -> Paths? {
            guard let script = b.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let fw = b.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
                  let client = b.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient"),
                  FileManager.default.fileExists(atPath: fw.path) else { return nil }
            return Paths(script: script, framework: fw, testClient: client)
        }
    }

    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "medien")
    nonisolated static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    /// Feste Umgebung für JEDEN Kindprozess (E17b, Review 18.10.): Seam erbt sonst z. B.
    /// `PERL5OPT=-M…` aus `launchctl setenv` und Perl lädt fremden Code – ganz ohne Eingriff ins Bundle.
    nonisolated static let cleanEnvironment = ["PATH": "/usr/bin:/bin"]

    var onInfo: ((NowPlayingInfo?) -> Void)?
    var onState: ((State) -> Void)?
    private(set) var state: State = .starting { didSet { if state != oldValue { onState?(state) } } }

    private var paths: Paths?
    private var process: Process?
    private var generation = 0
    private var failures = 0
    private var stopped = true
    private var splitter = LineSplitter(maxLineBytes: 4 << 20)
    private var badLines = 0

    // MARK: Reine Teile (getestet)

    nonisolated static func restartDelay(afterFailures n: Int) -> TimeInterval? {
        switch n { case 1: 1; case 2: 5; default: nil }
    }

    nonisolated static func arguments(_ p: Paths, _ call: Call) -> [String] {
        let base = [p.script.path, p.framework.path]
        switch call {
        case .stream: return base + ["stream", "--no-diff", "--micros", "--debounce=100"]
        case .test: return base + [p.testClient.path, "test"]
        case .send(let c): return base + ["send", String(c.rawValue)]
        case .seek(let s): return base + ["seek", String(Int64((max(0, s) * 1_000_000).rounded()))]
        }
    }

    // MARK: Betrieb

    func start() {
        guard stopped else { return }
        stopped = false
        state = .starting
        guard let p = Paths.bundled() else { return fail("Adapter fehlt im Programmpaket") }
        paths = p
        Task {
            guard await self.verified() else { return }
            await Task.detached { Self.killOrphans(scriptPath: p.script.path) }.value
            let ok = await Self.runTest(p)
            guard !self.stopped else { return }
            if ok { self.launchStream() } else { self.fail("macOS blockiert den Zugriff auf die Wiedergabe") }
        }
    }

    /// E17a: Bundle-Signatur inkl. Team-Anforderung, vor JEDEM Perl-Start, außerhalb des
    /// Hauptthreads (30–50 ms gemessen, Review 18.10.).
    private func verified() async -> Bool {
        let url = Bundle.main.bundleURL
        let status = await Task.detached { BundleIntegrity.check(url) }.value
        guard !stopped else { return false }
        guard status == errSecSuccess else {
            fail("Signatur des Programmpakets ungültig (OSStatus \(status)) – Adapter nicht gestartet")
            return false
        }
        return true
    }

    func stop() {
        stopped = true
        generation += 1
        terminateProcess()
    }

    func perform(_ call: Call) {
        guard case .running = state, let p = paths else { return }
        if case .stream = call { return }
        if case .test = call { return }
        let args = Self.arguments(p, call)
        Task {
            guard await self.verified() else { return }
            await Task.detached {
                let proc = Process()
                proc.executableURL = Self.perl
                proc.arguments = args
                proc.environment = Self.cleanEnvironment
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
            }.value
        }
    }

    private func fail(_ reason: String) {
        Self.log.error("Medien-Adapter aus: \(reason, privacy: .public)")
        state = .unavailable(reason)
        onInfo?(nil)
    }

    private func launchStream() {
        guard !stopped, let p = paths else { return }
        generation += 1
        let gen = generation
        splitter = LineSplitter(maxLineBytes: 4 << 20)
        let proc = Process()
        proc.executableURL = Self.perl
        proc.arguments = Self.arguments(p, .stream)
        proc.environment = Self.cleanEnvironment
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data, generation: gen) } }
        }
        proc.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.exited(status: status, generation: gen) } }
        }
        do {
            try proc.run()
            process = proc
            state = .running
            Self.log.notice("Medien-Adapter läuft")
        } catch {
            exited(status: -1, generation: gen)
        }
    }

    private func consume(_ data: Data, generation gen: Int) {
        guard gen == generation, !data.isEmpty else { return }
        let droppedBefore = splitter.dropped
        for line in splitter.feed(data) {
            if line.contains(UInt8(ascii: "{")), let info = NowPlayingInfo.parse(line: line) {
                failures = 0
                badLines = 0
                onInfo?(info)
            } else if String(decoding: line, as: UTF8.self).contains(#""payload":{}"#) {
                failures = 0
                onInfo?(nil)
            } else {
                badLines += 1
                if badLines == 10 { Self.log.error("Medien-Adapter: 10 unlesbare Zeilen in Folge") }
            }
        }
        if splitter.dropped > droppedBefore { Self.log.error("Medien-Adapter: überlange Zeile verworfen") }
    }

    private func exited(status: Int32, generation gen: Int) {
        guard gen == generation, !stopped else { return }
        process = nil
        failures += 1
        Self.log.error("Medien-Adapter beendet (Status \(status, privacy: .public), Abbruch \(self.failures, privacy: .public))")
        guard let delay = Self.restartDelay(afterFailures: failures) else {
            return fail("Adapter bricht wiederholt ab")
        }
        state = .starting
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard gen == self.generation, !self.stopped, await self.verified() else { return }
            self.launchStream()
        }
    }

    private func terminateProcess() {
        guard let proc = process else { return }
        process = nil
        (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
    }

    /// `test` mit 10 s Zeitlimit, außerhalb des Hauptthreads.
    nonisolated static func runTest(_ p: Paths) async -> Bool {
        let args = arguments(p, .test)
        return await Task.detached {
            let proc = Process()
            proc.executableURL = perl
            proc.arguments = args
            proc.environment = cleanEnvironment
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            let done = DispatchGroup()
            done.enter()
            proc.terminationHandler = { _ in done.leave() }
            guard (try? proc.run()) != nil else { return false }
            if done.wait(timeout: .now() + 10) == .timedOut {
                proc.terminate()
                return false
            }
            return proc.terminationStatus == 0
        }.value
    }

    /// E17h: verwaiste Adapter-Prozesse DIESES Bundles beenden (nach Absturz von Seam).
    /// Abgleich über den vollständigen Skriptpfad, ohne Shell, eigene PID ausgeschlossen.
    nonisolated static func killOrphans(scriptPath: String) {
        let pg = Process()
        pg.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pg.arguments = ["-f", scriptPath]
        pg.environment = cleanEnvironment
        let out = Pipe()
        pg.standardOutput = out
        guard (try? pg.run()) != nil else { return }
        pg.waitUntilExit()
        let own = getpid()
        String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").compactMap { pid_t($0) }
            .filter { $0 != own }
            .forEach { kill($0, SIGTERM) }
    }
}
```

- [ ] **Step 4: Run – expect PASS**, dann `make lint`
Expected: Tests grün, keine Lint-Fehler. Meldet SwiftLint `cyclomatic_complexity`/`function_body_length` für `consume`: die drei Zweige in eine `private func handle(line:)` auslagern.

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/MediaAdapter.swift SeamTests/MediaAdapterTests.swift
git commit -m "MediaAdapter: Kindprozess mit Signaturpruefung, Test, Strom, Neustart (E17b/h)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Zustand für die Oberfläche (`NowPlayingModel`)

**Files:**
- Create: `Seam/Notch/NowPlayingModel.swift`
- Test: `SeamTests/NowPlayingModelTests.swift`

- [ ] **Step 1: Failing test** (nur die reine Sichtbarkeitsregel)

```swift
import XCTest
@testable import Seam

/// Spezifikation: sichtbar bei Wiedergabe; nach 5 s Pause zurück in die Notch.
final class NowPlayingModelTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testVisibleWhilePlaying() {
        XCTAssertTrue(NowPlayingModel.isVisible(hasInfo: true, playing: true, pausedSince: nil, now: t0))
    }

    func testVisibleShortlyAfterPause() {
        XCTAssertTrue(NowPlayingModel.isVisible(hasInfo: true, playing: false, pausedSince: t0, now: t0.addingTimeInterval(4)))
    }

    func testHiddenFiveSecondsAfterPause() {
        XCTAssertFalse(NowPlayingModel.isVisible(hasInfo: true, playing: false, pausedSince: t0, now: t0.addingTimeInterval(5)))
    }

    func testHiddenWithoutInfo() {
        XCTAssertFalse(NowPlayingModel.isVisible(hasInfo: false, playing: false, pausedSince: nil, now: t0))
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/NowPlayingModelTests`)

- [ ] **Step 3: Implementation**

```swift
import AppKit
import Observation

/// Was die Insel zeigt. Eine Instanz für alle Bildschirme.
@MainActor
@Observable
final class NowPlayingModel {

    nonisolated static let pauseHide: TimeInterval = 5
    /// Halbe Browser-Meldung: so lange auf die vollständige warten (Mitschnitt 18.10.).
    static let completeWait: Duration = .milliseconds(300)

    private(set) var info: NowPlayingInfo?
    private(set) var artwork: NSImage?
    private(set) var isVisible = false
    /// nil = Adapter läuft oder startet; sonst Grund für den Hinweis in den Einstellungen.
    private(set) var unavailableReason: String?

    @ObservationIgnored private let adapter = MediaAdapter()
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var pausedSince: Date?
    @ObservationIgnored private var artworkKey: String?

    init() {
        adapter.onInfo = { [weak self] i in self?.receive(i) }
        adapter.onState = { [weak self] s in
            if case .unavailable(let r) = s { self?.unavailableReason = r } else { self?.unavailableReason = nil }
        }
    }

    func start() { adapter.start() }

    func stop() {
        adapter.stop()
        apply(nil)
    }

    func playPause() { adapter.perform(.send(.toggle)) }
    func next() { adapter.perform(.send(.next)) }
    func previous() { adapter.perform(.send(.previous)) }
    func seek(to seconds: TimeInterval) { adapter.perform(.seek(seconds)) }

    nonisolated static func isVisible(hasInfo: Bool, playing: Bool, pausedSince: Date?, now: Date) -> Bool {
        guard hasInfo else { return false }
        if playing { return true }
        guard let p = pausedSince else { return false }
        return now.timeIntervalSince(p) < pauseHide
    }

    private func receive(_ new: NowPlayingInfo?) {
        pending?.cancel()
        guard let new, new.isIncomplete else { return apply(new) }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.completeWait)
            guard !Task.isCancelled else { return }
            self?.apply(new)
        }
    }

    private func apply(_ new: NowPlayingInfo?) {
        let wasPlaying = info?.isPlaying ?? false
        info = new
        if let new, !new.isPlaying, wasPlaying || pausedSince == nil { pausedSince = Date() }
        if new?.isPlaying == true || new == nil { pausedSince = nil }
        updateArtwork(new)
        updateVisibility()
    }

    private func updateArtwork(_ new: NowPlayingInfo?) {
        let key = new.map { "\($0.appBundleID ?? "")|\($0.contentID ?? $0.title)" }
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = new?.artworkBase64.flatMap(Artwork.decode).map { NSImage(cgImage: $0, size: .zero) }
    }

    private func updateVisibility() {
        isVisible = Self.isVisible(hasInfo: info != nil, playing: info?.isPlaying ?? false,
                                   pausedSince: pausedSince, now: Date())
        hideTask?.cancel()
        guard isVisible, let paused = pausedSince else { return }
        let left = Self.pauseHide - Date().timeIntervalSince(paused)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, left)))
            guard !Task.isCancelled else { return }
            self?.updateVisibility()
        }
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/NowPlayingModel.swift SeamTests/NowPlayingModelTests.swift
git commit -m "NowPlayingModel: Zustand, halbe Browser-Meldungen abwarten, Pause-Ausblenden

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Notch- und Pillen-Maße (`IslandGeometry`)

**Files:**
- Create: `Seam/Notch/IslandGeometry.swift`
- Test: `SeamTests/IslandGeometryTests.swift`

Koordinaten: AppKit (Ursprung unten links), wie `NSScreen.frame`.

- [ ] **Step 1: Failing test**

```swift
import CoreGraphics
import XCTest
@testable import Seam

/// Spezifikation „Aufbau 4“: Lage aus den Notch-Maßen; ohne Notch Pille 180 × 24 oben mittig.
final class IslandGeometryTests: XCTestCase {

    // MacBook Air 13": 1470 × 956, Notch ~ 185 breit, 32 hoch.
    private let mac = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956), safeTop: 32, auxLeftWidth: 642.5, auxRightWidth: 642.5)
    private let ext = IslandGeometry.ScreenMetrics(
        frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440), safeTop: 0, auxLeftWidth: nil, auxRightWidth: nil)

    func testNotchRect() throws {
        let n = try XCTUnwrap(IslandGeometry.layout(for: mac).notch)
        XCTAssertEqual(n.width, 185, accuracy: 0.5)
        XCTAssertEqual(n.height, 32)
        XCTAssertEqual(n.maxY, 956)
        XCTAssertEqual(n.midX, 735, accuracy: 0.5)
    }

    func testCompactWrapsNotchWithWings() throws {
        let l = IslandGeometry.layout(for: mac)
        let n = try XCTUnwrap(l.notch)
        XCTAssertEqual(l.compact.width, n.width + 2 * IslandGeometry.wing, accuracy: 0.5)
        XCTAssertEqual(l.compact.maxY, 956)
        XCTAssertEqual(l.compact.midX, n.midX, accuracy: 0.5)
    }

    func testPillWithoutNotch() {
        let l = IslandGeometry.layout(for: ext)
        XCTAssertNil(l.notch)
        XCTAssertEqual(l.compact.size, CGSize(width: 180, height: 24))
        XCTAssertEqual(l.compact.midX, 1470 + 1280, accuracy: 0.5)
        XCTAssertEqual(l.compact.maxY, 1440)
    }

    func testExpandedCenteredAndInside() {
        for m in [mac, ext] {
            let l = IslandGeometry.layout(for: m)
            XCTAssertEqual(l.expanded.width, IslandGeometry.expandedSize.width)
            XCTAssertEqual(l.expanded.midX, l.compact.midX, accuracy: 0.5)
            XCTAssertEqual(l.expanded.maxY, m.frame.maxY)
            XCTAssertTrue(m.frame.contains(l.expanded))
        }
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/IslandGeometryTests`)

- [ ] **Step 3: Implementation**

```swift
import AppKit

/// Wo die Insel liegt. Reine Rechnung, getestet; `metrics(of:)` liest nur NSScreen.
enum IslandGeometry {

    struct ScreenMetrics: Equatable {
        let frame: CGRect
        let safeTop: CGFloat
        let auxLeftWidth: CGFloat?
        let auxRightWidth: CGFloat?
    }

    struct Layout: Equatable {
        /// nil = Bildschirm ohne Notch.
        let notch: CGRect?
        let compact: CGRect
        let expanded: CGRect
    }

    /// Platz links (Cover) und rechts (Pegel) neben der Notch.
    static let wing: CGFloat = 40
    static let pillSize = CGSize(width: 180, height: 24)
    /// Inhaltsfläche der grossen Ansicht: 380 pt breit, 110 pt unterhalb der Notch (mit Notch 142 pt hoch;
    /// nachgezogen 18.10. mit Aufgabe 10, Code: `expanded(…, extraHeight: notch.height, …)`).
    static let expandedSize = CGSize(width: 380, height: 110)

    static func layout(for m: ScreenMetrics) -> Layout {
        let top = m.frame.maxY
        if m.safeTop > 0, let l = m.auxLeftWidth, let r = m.auxRightWidth {
            let notch = CGRect(x: m.frame.minX + l, y: top - m.safeTop,
                               width: m.frame.width - l - r, height: m.safeTop)
            let compact = notch.insetBy(dx: -wing, dy: 0)
            return Layout(notch: notch, compact: compact, expanded: expanded(midX: notch.midX, top: top, in: m.frame))
        }
        let midX = m.frame.midX
        let pill = CGRect(x: midX - pillSize.width / 2, y: top - pillSize.height,
                          width: pillSize.width, height: pillSize.height)
        return Layout(notch: nil, compact: pill, expanded: expanded(midX: midX, top: top, in: m.frame))
    }

    private static func expanded(midX: CGFloat, top: CGFloat, in frame: CGRect) -> CGRect {
        var x = midX - expandedSize.width / 2
        x = min(max(x, frame.minX), frame.maxX - expandedSize.width)
        return CGRect(x: x, y: top - expandedSize.height, width: expandedSize.width, height: expandedSize.height)
    }

    @MainActor
    static func metrics(of s: NSScreen) -> ScreenMetrics {
        let l = s.auxiliaryTopLeftArea?.width
        let r = s.auxiliaryTopRightArea?.width
        return ScreenMetrics(frame: s.frame, safeTop: s.safeAreaInsets.top, auxLeftWidth: l, auxRightWidth: r)
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: Commit**

```bash
git add Seam/Notch/IslandGeometry.swift SeamTests/IslandGeometryTests.swift
git commit -m "IslandGeometry: Notch-Masse, Pille ohne Notch, grosse Ansicht

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Ansicht (`IslandView`) im macOS-Systemstil

**Files:**
- Create: `Seam/Notch/IslandView.swift`

Keine Unit-Tests (reine Darstellung); geprüft im Sichttest (Task 14). Regeln: SF Pro (Systemschrift, **kein** `FamilyTheme.font`), Weiß/Grau auf Schwarz, `Text(verbatim:)` (E17d), SF Symbols, Federn `.smooth`/`.snappy`.

- [ ] **Step 1: Implementation**

```swift
import AppKit
import SwiftUI

/// Zustand einer Insel, geteilt zwischen Panel (Größe, Mausdurchlass) und Ansicht.
@MainActor
@Observable
final class IslandState {
    enum Mode { case hidden, compact, expanded }
    var mode: Mode = .hidden
    var layout: IslandGeometry.Layout
    init(layout: IslandGeometry.Layout) { self.layout = layout }
}

/// Die Insel. Tiefschwarz, oben bündig, unten weich gerundet – soll aussehen wie ein Teil
/// von macOS (Michael, 18.10.: „seamless wie macOS“). Bewusst Systemschrift statt Familien-Design.
struct IslandView: View {
    @Environment(NowPlayingModel.self) private var model
    let state: IslandState
    let onHover: (Bool) -> Void

    private var size: CGSize {
        switch state.mode {
        case .hidden: state.layout.notch?.size ?? CGSize(width: IslandGeometry.pillSize.width, height: 0)
        case .compact: state.layout.compact.size
        case .expanded: state.layout.expanded.size
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: corner, bottomTrailingRadius: corner, style: .continuous)
                    .fill(.black)
                content
            }
            .frame(width: size.width, height: size.height)
            .onHover(perform: onHover)
            Spacer(minLength: 0)
        }
        // Füllt das Panel (klein ODER groß); die Insel hängt oben mittig – beide Rechtecke teilen midX und Oberkante.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.32), value: state.mode)
        .environment(\.colorScheme, .dark)
    }

    private var corner: CGFloat { state.mode == .expanded ? 22 : 10 }

    @ViewBuilder private var content: some View {
        if let info = model.info, state.mode != .hidden {
            if state.mode == .compact { compact(info) } else { expanded(info) }
        }
    }

    private func compact(_ info: NowPlayingInfo) -> some View {
        HStack {
            cover(18, radius: 4)
            Spacer()
            LevelBars(playing: info.isPlaying)
        }
        .padding(.horizontal, 10)
        .frame(height: state.layout.compact.height)
        .transition(.opacity)
    }

    private func expanded(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                cover(56, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    if let a = info.artist {
                        Text(verbatim: a).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                appIcon(info.appBundleID)
            }
            HStack(spacing: 22) {
                button("backward.fill") { model.previous() }
                button(info.isPlaying ? "pause.fill" : "play.fill") { model.playPause() }
                button("forward.fill") { model.next() }
            }
            ProgressRow(info: info) { model.seek(to: $0) }
        }
        .padding(EdgeInsets(top: (state.layout.notch?.height ?? 6) + 4, leading: 16, bottom: 12, trailing: 16))
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }

    @ViewBuilder private func cover(_ side: CGFloat, radius: CGFloat) -> some View {
        Group {
            if let img = model.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.5)).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    @ViewBuilder private func appIcon(_ id: String?) -> some View {
        if let id, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

/// Animierter Pegel – reine Animation, kein Audiosignal (Spezifikation „Nicht in diesem Schritt“).
private struct LevelBars: View {
    let playing: Bool
    var body: some View {
        TimelineView(.animation(paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white)
                        .frame(width: 2.5, height: playing ? 5 + 7 * abs(sin(t * (3 + Double(i)) + Double(i))) : 4)
                }
            }
            .frame(height: 14)
        }
    }
}

/// Fortschritt mit Zeiten, spulbar.
private struct ProgressRow: View {
    let info: NowPlayingInfo
    let onSeek: (TimeInterval) -> Void
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let dur = info.duration ?? 0
            let now = dragValue ?? info.elapsed(at: ctx.date)
            HStack(spacing: 8) {
                Text(verbatim: Self.clock(now)).monospacedDigit()
                Slider(value: Binding(get: { now }, set: { dragValue = $0 }), in: 0...max(dur, 1)) { editing in
                    if !editing, let v = dragValue { onSeek(v); dragValue = nil }
                }
                .controlSize(.mini)
                .disabled(dur == 0)
                Text(verbatim: dur > 0 ? Self.clock(dur) : "–:––").monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    static func clock(_ s: TimeInterval) -> String {
        let t = Int(s.rounded(.down))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }
}
```

- [ ] **Step 2: Bauen**

```bash
make build 2>&1 | grep -E 'error:|BUILD' | tail -3 && make lint
```
Expected: `** BUILD SUCCEEDED **`, Lint sauber.

- [ ] **Step 3: Commit**

```bash
git add Seam/Notch/IslandView.swift
git commit -m "IslandView: Insel klein/gross im macOS-Systemstil, Text(verbatim:)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Panels je Bildschirm (`IslandController`)

**Files:**
- Create: `Seam/Notch/IslandController.swift`

- [ ] **Step 1: Implementation**

```swift
import AppKit
import SwiftUI

/// Ein Panel je Bildschirm. Ohne Fokus, über der Menüleiste und über der Abdunklung
/// (Dimmer = `.normal`). Im Zustand „unsichtbar“ lässt es Klicks durch (E17i).
@MainActor
final class IslandController {

    private let model: NowPlayingModel
    private var panels: [CGDirectDisplayID: (panel: NSPanel, state: IslandState)] = [:]
    private var observers: [NSObjectProtocol] = []
    private var collapseTask: Task<Void, Never>?
    private var running = false

    init(model: NowPlayingModel) { self.model = model }

    func start() {
        guard !running else { return }
        running = true
        rebuild()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observeModel()
    }

    func stop() {
        running = false
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        panels.values.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.isVisible
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.refresh()
                self.observeModel()
            } }
        }
    }

    private func rebuild() {
        panels.values.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let state = IslandState(layout: IslandGeometry.layout(for: IslandGeometry.metrics(of: screen)))
            let panel = makePanel(state: state, displayID: id)
            panels[id] = (panel, state)
        }
        refresh()
    }

    private func makePanel(state: IslandState, displayID: CGDirectDisplayID) -> NSPanel {
        let p = NSPanel(contentRect: state.layout.compact, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.ignoresMouseEvents = true
        let view = IslandView(state: state) { [weak self] inside in self?.hover(inside, displayID: displayID) }
            .environment(model)
        p.contentView = NSHostingView(rootView: view)
        p.setFrame(state.layout.expanded, display: false)
        return p
    }

    /// Sichtbarkeit je Bildschirm: Musik läuft, und auf diesem Bildschirm ist keine App im Vollbild.
    private func refresh() {
        for (id, entry) in panels {
            let screen = NSScreen.screens.first { $0.displayID == id }
            let show = model.isVisible && !(screen.map { Self.hasFullscreenWindow(on: $0) } ?? false)
            if !show {
                entry.state.mode = .hidden
                entry.panel.ignoresMouseEvents = true
                entry.panel.orderOut(nil)
            } else {
                if entry.state.mode == .hidden { entry.state.mode = .compact }
                entry.panel.ignoresMouseEvents = false
                entry.panel.setFrame(frame(for: entry.state), display: true)
                entry.panel.orderFrontRegardless()
            }
        }
    }

    /// Panel nur so groß wie der sichtbare Zustand, damit die Menüleiste daneben klickbar bleibt.
    private func frame(for s: IslandState) -> CGRect {
        s.mode == .expanded ? s.layout.expanded : s.layout.compact
    }

    private func hover(_ inside: Bool, displayID: CGDirectDisplayID) {
        guard let entry = panels[displayID], entry.state.mode != .hidden else { return }
        collapseTask?.cancel()
        if inside {
            // Beim Ziehen/Andocken eines Fensters nicht aufgehen (Spezifikation).
            guard NSEvent.pressedMouseButtons == 0 else { return }
            entry.panel.setFrame(entry.state.layout.expanded, display: true)
            entry.state.mode = .expanded
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, let e = self.panels[displayID] else { return }
                e.state.mode = .compact
                try? await Task.sleep(for: .milliseconds(350))   // Animation auslaufen lassen
                guard !Task.isCancelled, e.state.mode == .compact else { return }
                e.panel.setFrame(e.state.layout.compact, display: true)
            }
        }
    }

    /// Vollbild-App auf diesem Bildschirm: ein Fenster auf Ebene 0, das einer NORMALEN App gehört
    /// (`activationPolicy == .regular`, nie Gnotchi selbst), deckt ihn exakt ab. Ohne die App-Bedingung
    /// zählte Seams Abdunkel-Fenster (Ebene 0, exakt bildschirmgroß, gemessen 18.10.) als Vollbild.
    /// Umgesetzt (Gnotchi 18.10.) als reine, getestete Teile: `windows(from:ownPID:isRegular:)`
    /// (liest nur PID, Ebene, Lage; Art je PID einmal erfragt) und `coversScreen(windows:target:)`;
    /// Koordinaten über `cgWindowRect(fromAppKit:primaryHeight:)` statt Seams `Geometry.toAX`.
    private static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let target = cgWindowRect(fromAppKit: screen.frame, primaryHeight: h)
        let own = ProcessInfo.processInfo.processIdentifier
        return list.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
                  let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b as CFDictionary) else { return false }
            return r.equalTo(target)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
```

Hinweis: `CGWindowListCopyWindowInfo` liest nur Lage, Ebene und Eigentümer-PID (kein Fenstertitel, kein App-Name; Lint-Regel `keine_fenstertitel`) – passt zu E3 bzw. Gnotchi G10. Gibt es `NSScreen.displayID` bereits im Projekt (`grep -rn "displayID" Seam`), die Erweiterung weglassen und die vorhandene nutzen.

- [ ] **Step 2: Bauen + Lint**

```bash
grep -rn "var displayID" Seam | grep -v IslandController
make build 2>&1 | grep -E 'error:|BUILD' | tail -3 && make lint
```
Expected: BUILD SUCCEEDED, Lint sauber.

- [ ] **Step 3: Commit**

```bash
git add Seam/Notch/IslandController.swift
git commit -m "IslandController: Panel je Bildschirm, Hover, Vollbild aus, Klicks durchlassen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11a: AppleScript-Rückfall für Spotify und Musik (Michael, 18.10.: „gleich mitbauen“)

**Files:**
- Create: `Seam/Notch/AppleScriptSource.swift`
- Test: `SeamTests/AppleScriptSourceTests.swift`
- Modify: `Seam/Notch/NowPlayingModel.swift` (Umschalten)
- Modify: `Seam/Resources/Seam.entitlements`, `Seam/Resources/Info.plist`, `scripts/release.sh:192-196`, `docs/SECURE-DESIGN.md` (E8, E17f)

Greift nur, wenn der Adapter `unavailable` meldet. Fragt nur Apps ab, die **schon laufen** (`tell application` würde sie sonst starten). NSAppleScript läuft auf einer eigenen seriellen Queue – die erste Abfrage wartet auf den Automation-Dialog und darf den Hauptthread nicht blockieren.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Seam

/// E17f: Antworten der Rückfall-Skripte und feste Befehle.
final class AppleScriptSourceTests: XCTestCase {
    private let sep = "\u{1F}"
    private let now = Date(timeIntervalSince1970: 1000)

    func testSpotifyDurationInMilliseconds() throws {
        let raw = ["Beispieltitel Eins", "Testband", "206937", "30.5", "playing"].joined(separator: sep)
        let i = try XCTUnwrap(AppleScriptSource.parse(raw, bundleID: "com.spotify.client", now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 206.937, accuracy: 0.001)
        XCTAssertEqual(i.elapsed(at: now), 30.5, accuracy: 0.001)
        XCTAssertTrue(i.isPlaying)
        XCTAssertEqual(i.appBundleID, "com.spotify.client")
    }

    func testMusicDurationInSecondsAndPaused() throws {
        let raw = ["Beispieltitel Zwei", "Beispielkünstler", "245.3", "12", "paused"].joined(separator: sep)
        let i = try XCTUnwrap(AppleScriptSource.parse(raw, bundleID: "com.apple.Music", now: now))
        XCTAssertEqual(try XCTUnwrap(i.duration), 245.3, accuracy: 0.001)
        XCTAssertFalse(i.isPlaying)
    }

    func testStoppedOrGarbageIsNil() {
        XCTAssertNil(AppleScriptSource.parse("", bundleID: "com.apple.Music", now: now))
        XCTAssertNil(AppleScriptSource.parse("nur ein feld", bundleID: "com.apple.Music", now: now))
    }

    func testSeekScriptIsNumberOnly() {
        XCTAssertTrue(AppleScriptSource.script(.seek(61.5), bundleID: "com.apple.Music").contains("set player position to 61.500"))
        XCTAssertTrue(AppleScriptSource.script(.seek(-4), bundleID: "com.apple.Music").contains("set player position to 0.000"))
        XCTAssertTrue(AppleScriptSource.script(.send(.next), bundleID: "com.spotify.client").contains("next track"))
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/AppleScriptSourceTests`)

- [ ] **Step 3: Implementation**

```swift
import AppKit
import OSLog

/// Rückfall ohne Adapter (E17f): Spotify und Musik per AppleScript. Alle Skripte sind
/// Konstanten; einzige variable Größe ist die Spulposition als formatierte Zahl.
@MainActor
final class AppleScriptSource {

    nonisolated static let supported = ["com.spotify.client", "com.apple.Music"]
    private static let log = Logger(subsystem: "dev.mwlr.seam", category: "medien")
    private nonisolated static let sep = "\u{1F}"

    var onInfo: ((NowPlayingInfo?) -> Void)?
    /// Gesetzt, wenn der Nutzer die Automation verweigert hat (Fehler -1743).
    var onDenied: (() -> Void)?

    private let queue = DispatchQueue(label: "dev.mwlr.seam.applescript")
    private var timer: Timer?
    private var active: String?
    private var denied = Set<String>()

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.3
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        active = nil
    }

    func perform(_ call: MediaAdapter.Call) {
        guard let id = active else { return }
        let source = Self.script(call, bundleID: id)
        queue.async { _ = Self.run(source) }
    }

    private func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let candidates = Self.supported.filter { running.contains($0) && !denied.contains($0) }
        guard !candidates.isEmpty else { active = nil; onInfo?(nil); return }
        queue.async { [weak self] in
            var best: (String, NowPlayingInfo)?
            var deniedNow: [String] = []
            for id in candidates {
                let result = Self.run(Self.script(.stream, bundleID: id))
                if result.error == -1743 { deniedNow.append(id); continue }
                if let info = result.text.flatMap({ Self.parse($0, bundleID: id, now: Date()) }),
                   best == nil || (info.isPlaying && !(best?.1.isPlaying ?? false)) {
                    best = (id, info)
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, self.timer != nil else { return }
                if !deniedNow.isEmpty {
                    self.denied.formUnion(deniedNow)
                    Self.log.error("Automation verweigert für \(deniedNow.joined(separator: ","), privacy: .public)")
                    self.onDenied?()
                }
                self.active = best?.0
                self.onInfo?(best?.1)
            } }
        }
    }

    // MARK: Reine Teile (getestet)

    nonisolated static func script(_ call: MediaAdapter.Call, bundleID: String) -> String {
        let body: String
        switch call {
        case .stream, .test:
            body = """
            if player state is stopped then return ""
            set t to current track
            set s to ASCII character 31
            return (name of t) & s & (artist of t) & s & (duration of t) & s & (player position) & s & (player state as string)
            """
        case .send(.toggle): body = "playpause"
        case .send(.play): body = "play"
        case .send(.pause): body = "pause"
        case .send(.next): body = "next track"
        case .send(.previous): body = "previous track"
        case .seek(let sec): body = "set player position to " + String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, sec))
        }
        return "tell application id \"\(bundleID)\"\n\(body)\nend tell"
    }

    /// Spotify liefert die Dauer in Millisekunden, Musik in Sekunden.
    nonisolated static func parse(_ raw: String, bundleID: String, now: Date) -> NowPlayingInfo? {
        let f = raw.components(separatedBy: sep)
        guard f.count == 5, let title = NowPlayingInfo.sanitize(f[0]) else { return nil }
        let rawDur = Double(f[2].replacingOccurrences(of: ",", with: "."))
        let dur = rawDur.map { bundleID == "com.spotify.client" ? $0 / 1000 : $0 }
        let pos = Double(f[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        let playing = f[4] == "playing"
        return NowPlayingInfo(title: title, artist: NowPlayingInfo.sanitize(f[1]), album: nil,
                              appBundleID: bundleID, isPlaying: playing,
                              duration: dur.flatMap { $0 > 0 ? $0 : nil },
                              elapsedAtStamp: pos, stamp: now, rate: playing ? 1 : 0,
                              contentID: nil, artworkBase64: nil)
    }

    private nonisolated static func run(_ source: String) -> (text: String?, error: Int?) {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return (out?.stringValue, err?[NSAppleScript.errorNumber] as? Int)
    }
}
```

- [ ] **Step 4: Run – expect PASS**

- [ ] **Step 5: Im Modell umschalten** (`Seam/Notch/NowPlayingModel.swift`)

Eigenschaft ergänzen:
```swift
    @ObservationIgnored private let fallback = AppleScriptSource()
    @ObservationIgnored private var usingFallback = false
```
`init()` ersetzen durch:
```swift
    init() {
        adapter.onInfo = { [weak self] i in self?.receive(i) }
        fallback.onInfo = { [weak self] i in self?.receive(i) }
        fallback.onDenied = { [weak self] in
            self?.unavailableReason = "Automation für Spotify/Musik nicht erlaubt (Systemeinstellungen → Datenschutz → Automation)"
        }
        adapter.onState = { [weak self] s in
            guard let self else { return }
            if case .unavailable(let r) = s {
                self.unavailableReason = "\(r) – nur Spotify und Musik"
                self.usingFallback = true
                self.fallback.start()
            } else {
                self.unavailableReason = nil
                self.usingFallback = false
                self.fallback.stop()
            }
        }
    }
```
`stop()` ergänzen um `fallback.stop()` und `usingFallback = false`. Die vier Befehle ersetzen durch:
```swift
    func playPause() { route(.send(.toggle)) }
    func next() { route(.send(.next)) }
    func previous() { route(.send(.previous)) }
    func seek(to seconds: TimeInterval) { route(.seek(seconds)) }

    private func route(_ call: MediaAdapter.Call) {
        if usingFallback { fallback.perform(call) } else { adapter.perform(call) }
    }
```

- [ ] **Step 6: Berechtigung genau dieser einen Art zulassen**

`Seam/Resources/Seam.entitlements` – Kommentar anpassen und Schlüssel ergänzen:
```xml
	<!-- Keine App Sandbox (Bedienungshilfen). KEINE Ausnahme von der Hardened Runtime
	     (keine disable-library-validation, keine allow-dyld-environment-variables) – E8.
	     Einzige Berechtigung: Apple Events senden, für den Rückfall der Mediensteuerung
	     (Spotify/Musik, E17f). Jede Ziel-App fragt macOS einzeln beim Nutzer an. -->
	<key>com.apple.security.automation.apple-events</key>
	<true/>
```
`Seam/Resources/Info.plist` – vor `</dict>`:
```xml
	<key>NSAppleEventsUsageDescription</key>
	<string>Seam steuert Spotify und Musik in der Notch, wenn macOS den systemweiten Zugriff sperrt.</string>
```
`scripts/release.sh` – die E8-Prüfung (Zeilen 192–196) ersetzen durch:
```sh
# E8 maschinell (Code-Audit 09.10., S3; ab 0.7 E17f): genau EINE Berechtigung erlaubt –
# Apple Events senden. Jede Ausnahme wie disable-library-validation würde Code-Einschleusung
# erlauben, samt Bedienungshilfen-Freigabe.
ENTS="$(codesign -d --entitlements - --xml "${APP_PATH}" 2>/dev/null | grep -o '<key>[^<]*</key>' \
    | grep -v '^<key>com.apple.security.automation.apple-events</key>$' || true)"
[ -z "${ENTS}" ] || fail "Unerwartete Berechtigungen in der App: ${ENTS} (SECURE-DESIGN E8/E17f)"
echo "  ✓ Developer ID (Team LTKJ6Z2VYB) + Hardened Runtime, nur Apple-Events-Berechtigung"
```

- [ ] **Step 7: SECURE-DESIGN nachziehen** – in E8 einen Satz anhängen: „Ab 0.7 (E17f) trägt Seam genau eine Berechtigung, `com.apple.security.automation.apple-events`; `release.sh` lässt nur diese zu.“ In **E17f** ergänzen: „Berechtigung `automation.apple-events` (Michael, 18.10.: Rückfall gleich mitbauen). Skripte nur an `com.spotify.client`/`com.apple.Music`, nur an laufende Apps, eigene serielle Queue.“

- [ ] **Step 8: Prüfen + Commit**

```bash
make test 2>&1 | grep -E 'Executed|failed' | tail -3 && make lint
make build >/dev/null 2>&1 && codesign -d --entitlements - --xml build/Build/Products/Debug/Seam.app 2>/dev/null | grep -o '<key>[^<]*</key>' || echo "(unsigniert gebaut – Prüfung im Sichttest/Release)"
git add Seam/Notch/AppleScriptSource.swift SeamTests/AppleScriptSourceTests.swift Seam/Notch/NowPlayingModel.swift \
  Seam/Resources/Seam.entitlements Seam/Resources/Info.plist scripts/release.sh docs/SECURE-DESIGN.md
git commit -m "AppleScript-Rueckfall Spotify/Musik, einzige Berechtigung apple-events (E17f)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Einstellung „Musik in der Notch“ + Verdrahtung

**Files:**
- Modify: `Seam/Core/Preferences.swift` (Key, Eigenschaft, init)
- Modify: `Seam/App/SeamApp.swift` (Engine)
- Modify: `Seam/UI/SettingsView.swift`
- Test: `SeamTests/NotchPreferenceTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import Seam

@MainActor
final class NotchPreferenceTests: XCTestCase {
    func testDefaultOnAndPersists() {
        let d = UserDefaults(suiteName: "seam.test.\(UUID().uuidString)")!
        let p = Preferences(defaults: d)
        XCTAssertTrue(p.notchMedia)
        p.notchMedia = false
        XCTAssertFalse(Preferences(defaults: d).notchMedia)
    }
}
```

- [ ] **Step 2: Run – expect FAIL** (`-only-testing:SeamTests/NotchPreferenceTests`)

- [ ] **Step 3: Preferences**

In `enum Key` ergänzen:
```swift
        static let notchMedia = "notchMedia"
```
Bei den Eigenschaften (nach `hideIconWithSpaceName`):
```swift
    /// Mediensteuerung in der Notch (0.7, E17). Ab Werk an.
    var notchMedia: Bool { didSet { defaults.set(notchMedia, forKey: Key.notchMedia) } }
```
Im `init` (nach `restoreOnDragOut = …`):
```swift
        notchMedia = defaults.object(forKey: Key.notchMedia) as? Bool ?? true
```

- [ ] **Step 4: Engine** (`Seam/App/SeamApp.swift`)

Eigenschaften in `Engine` (bei den anderen `let`):
```swift
    /// Mediensteuerung in der Notch (E17). Läuft ohne Bedienungshilfen-Freigabe.
    let nowPlaying = NowPlayingModel()
    @ObservationIgnored private lazy var island = IslandController(model: nowPlaying)
```
Am Ende von `init()` – nach `spaces.start()`, also nur außerhalb des Testlaufs:
```swift
        applyNotchSetting()
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.nowPlaying.stop() }
        }
```
Neue Methode (bei `applyDimSetting`):
```swift
    /// Schalter „Musik in der Notch“ (E17).
    func applyNotchSetting() {
        guard !Self.isRunningTests else { return }
        if prefs.notchMedia {
            nowPlaying.start()
            island.start()
        } else {
            island.stop()
            nowPlaying.stop()
        }
    }
```
`SettingsView` liest `engine.nowPlaying.unavailableReason` über die vorhandene `Engine`-Umgebung – keine zusätzliche `.environment` nötig. Die Insel bekommt das Modell im `IslandController` (Task 11).

- [ ] **Step 5: SettingsView** – neuer Abschnitt nach dem Abdunkeln-Block (bei Zeile ~54, gleiches Muster wie dort):

```swift
                divider
                toggleRow("Musik in der Notch", isOn: $prefs.notchMedia)
                    .onChange(of: prefs.notchMedia) { engine.applyNotchSetting() }
                if prefs.notchMedia, let reason = engine.nowPlaying.unavailableReason {
                    note("Mediensteuerung nicht verfügbar – \(reason)",
                         symbol: "exclamationmark.triangle", color: .orange)
                }
```

- [ ] **Step 6: Run tests + build**

```bash
make test 2>&1 | grep -E 'Executed|error:|failed' | tail -5 && make lint
```
Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add Seam/Core/Preferences.swift Seam/App/SeamApp.swift Seam/UI/SettingsView.swift SeamTests/NotchPreferenceTests.swift
git commit -m "Einstellung Musik in der Notch, Start/Stopp in der Engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Doku (Hilfe, CHANGELOG, README)

**Files:**
- Modify: `Seam/Resources/HILFE.md`, `CHANGELOG.md`, `README.md`

- [ ] **Step 1: Abschnitte schreiben** – Stil wie die vorhandenen Abschnitte (Deutsch, kurz, für Nutzer):

HILFE.md, neuer Abschnitt:
```markdown
## Musik in der Notch

Läuft Musik oder ein Video – Spotify, Musik, Podcasts, YouTube in Safari, Edge oder Helium –,
zeigt Seam in der Notch das Cover und einen kleinen Pegel. Fährst du mit der Maus darauf, klappt
die Insel auf: Titel, Interpret, Zurück / Pause / Weiter und ein Fortschrittsbalken zum Spulen.
Auf Bildschirmen ohne Notch erscheint dieselbe Insel oben in der Mitte. Bei Pause verschwindet
sie nach fünf Sekunden, bei Vollbild-Apps bleibt sie aus.

Abschalten: Einstellungen → „Musik in der Notch“.

Steht dort „Mediensteuerung nicht verfügbar“, hat ein macOS-Update den Zugriff gesperrt – Seam
arbeitet sonst normal weiter.
```

CHANGELOG.md, oben unter `## [Unreleased]` (Abschnitt anlegen, falls nicht vorhanden):
```markdown
### Neu
- **Musik in der Notch:** Cover, Titel und Steuerung für Spotify, Musik, Podcasts und Browser-Videos – in der Notch oder als Insel oben mittig.
```

README.md: in der Funktionsliste eine Zeile „Musik in der Notch (Mediensteuerung)“ und unter Drittanbieter „mediaremote-adapter (BSD-3)“.

- [ ] **Step 2: Doku-Gate**

```bash
ls scripts | grep -i docs && ./scripts/docs-drift-check.sh 2>/dev/null | tail -5 || echo "kein docs-drift-check im Repo"
```
Expected: kein Drift gemeldet (oder Skript nicht vorhanden).

- [ ] **Step 3: Commit**

```bash
git add Seam/Resources/HILFE.md CHANGELOG.md README.md
git commit -m "Doku: Musik in der Notch (Hilfe, CHANGELOG, README)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Sichttest am echten System (Pflicht vor Release)

**Files:** keine Code-Änderung; Ergebnisse → `docs/SECURE-DESIGN.md` (E17a-Messung), Projektnotiz im Vault.

- [ ] **Step 1: Signierte Testversion starten** – mit Skill `/app-sichttest` (abgeschottete Kopie), sonst:
```bash
./scripts/dev-signed.sh
```

- [ ] **Step 2: Messpunkte abarbeiten** (je Punkt Ergebnis notieren)

| # | Prüfung | Erwartung |
|---|---|---|
| 1 | Spotify spielt | Insel klein: Cover links, Pegel rechts der Notch |
| 2 | Maus auf Insel | klappt auf, Titel/Interpret/Tasten/Fortschritt |
| 3 | ⏯ in der Insel bei **YouTube in Helium** | Video pausiert (offener Punkt aus der Messung 18.10.) |
| 4 | ⏭ bei Spotify, Spulen per Balken | wirkt binnen ~1 s |
| 5 | Safari-Video | Safari-Symbol oben rechts (nicht WebKit) |
| 6 | Pause 5 s | Insel verschwindet |
| 7 | Fenster an den oberen Rand ziehen | Insel klappt **nicht** auf |
| 8 | Abdunkeln an | Insel liegt über der Abdunklung |
| 9 | Vollbild-Video | Insel auf diesem Bildschirm aus |
| 10 | externer Monitor | Pille 180 × 24 oben mittig (Lage per Bedienungshilfen messen) |
| 11 | Menüleiste neben der Insel | Menüs links/rechts bleiben klickbar |
| 12 | Skript im Testbundle ändern (`echo >> …/mediaremote-adapter.pl`), Seam neu starten | kein Adapter, Hinweis in den Einstellungen |
| 13 | Protokoll | `log show --last 5m --predicate 'subsystem == "dev.mwlr.seam" AND category == "medien"'` enthält **keine** Titel |
| 13b | Adapter-Pfad sperren (Skript im Testbundle ändern, Nr. 12) und Spotify abspielen | Rückfall: Insel zeigt Spotify, macOS fragt einmal nach Automation |
| 13c | Vollbild-App und „Menüleiste automatisch ausblenden“ auf dem MacBook | Notch-Erkennung bleibt (safeAreaInsets.top weiter 32, Review Task 9: ~75 % vermutet); Insel im Vollbild aus, danach wieder an der Notch |
| 14 | E17a-Messung: erbt der Perl-Prozess Seams Freigabe? | In Systemeinstellungen → Datenschutz → Bedienungshilfen nachsehen, ob „perl“ auftaucht; `log stream --predicate 'subsystem == "com.apple.TCC"'` während des Adapter-Starts mitlesen und den „responsible“-Prozess notieren |

- [ ] **Step 3: Ergebnisse festhalten** – Punkt 14 in `docs/SECURE-DESIGN.md` E17a nachtragen („gemessen 18.10.: …“), Abweichungen als neue Aufgaben. Commit:

```bash
git add docs/SECURE-DESIGN.md
git commit -m "E17a: Sichttest-Ergebnis zur TCC-Zuordnung des Kindprozesses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Sicherheits-Review vor Release

- [ ] **Step 1:** Skill `rafter-code-review` gegen E17a–E17i auf den Diff seit `7fb9467`.
- [ ] **Step 2:** `rafter run` im Repo (Kosten: Standardmodus, kein `--mode plus` ohne Michaels Zustimmung).
- [ ] **Step 3:** Befunde beheben, je Fund ein Commit; danach Release nur über `/app-release` und nur mit Michaels ausdrücklichem Go.

---

## Bewusst nicht in diesem Plan

- Weitere Notch-Funktionen, Songtexte, echter Audiopegel, Kurzeinblendung bei Titelwechsel, Einstellungen je Bildschirm.
