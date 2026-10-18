# Gnotchi – Sicherheitsentwurf

Stand 2026-10-18. Abgeleitet aus Seams Durchgang E17 „Mediensteuerung in der Notch“
(`rafter-secure-design`, 2026-10-18, vor dem Code) samt den Review-Fixes bis Seam-Commit `dc0e71d`
(Zweig `feature/notch-medien`). Format je Punkt: **entschieden / verworfen / warum**. Bei der
Umsetzung `rafter-code-review` gegen diese Liste laufen lassen.

Die Entscheidungen heißen hier **G1 …**. Wo eine aus Seam stammt, steht die alte Nummer dabei
(„vormals Seam E17a“), damit Verweise in Spezifikation, Plan und Seams Historie auffindbar bleiben.

| Gnotchi | vormals Seam | Thema |
|---|---|---|
| G1 | – (neu) | keine Bedienungshilfen, keine Eingaben |
| G2 | E17a | Bundle-Signatur + Identität vor jedem Adapter-Start |
| G3 | E17b | Start ohne Shell, feste Umgebung |
| G4 | E17c | Strom als nicht vertrauenswürdig lesen |
| G5 | E17d | Anzeige ohne Interpretation |
| G6 | E17e | Cover begrenzt dekodieren |
| G7 | E17f | AppleScript fest im Code |
| G8 | E17g, E11 | Protokoll ohne Inhalte |
| G9 | E17h | Kindprozess sauber führen |
| G10 | E17i | Insel stört nichts |
| G11 | E9 | Updates wie Kalli/Seam |
| G12 | E8 | Gnotchi härten, Berechtigungen per Positivliste |
| G13 | E7 | niemand außer dem Nutzer steuert Gnotchi |
| G14 | E10 | gespeicherte Daten |
| G15 | – (neu) | Wiedergabeweg aus Core Audio, nur lesen |
| G16 | – (neu) | keine echten Hördaten im Repo |

## Was Gnotchi ist und welche Macht es hat

Menüleisten-App für macOS 27. Eine Insel in der MacBook-Notch (auf Bildschirmen ohne Notch eine
Pille oben mittig) zeigt den laufenden Titel jeder Quelle und steuert die Wiedergabe. Apple bietet
dafür keine öffentliche Schnittstelle; Gnotchi nutzt wie Boring Notch/Cyclop `mediaremote-adapter`
(BSD-3), der über den systemeigenen `/usr/bin/perl` an `MediaRemote.framework` kommt. Rückfall:
AppleScript für Spotify und Musik; Spotify spult außerdem immer per AppleScript (G7).

**Warum eine eigene App:** Entworfen wurde das in Seam. Seam hält die Bedienungshilfen-Freigabe,
und der Perl-Kindprozess könnte Seams Freigaben erben (vermutet, siehe G2). Eine Freigabe, mit der
ein Prozess die Oberfläche aller Apps lesen und Eingaben auslösen kann, gehört nicht in die Nähe
eines Interpreters, der Fremdcode lädt. Gnotchi trennt das.

**Befugnisse von Gnotchi:**

- **Keine Bedienungshilfen-Freigabe.** Gnotchi fragt sie nie an und prüft sie nie (G1).
- **Apple Events** (Berechtigung `com.apple.security.automation.apple-events`), tatsächlich
  benutzt nur für Spotify und Musik (Rückfall G7) und fürs Spulen in Spotify. Welche App Gnotchi steuern darf, erteilt der Nutzer je
  Ziel-App im macOS-Dialog (Automation).
- **Ein Kindprozess:** `/usr/bin/perl` mit dem Adapter-Skript und -Framework aus dem eigenen
  Bundle. Er liest systemweit, was gerade spielt, und sendet Steuerbefehle (Play/Pause, Weiter,
  Zurück, Spulen).
- **Netz:** nur die Update-Prüfung (Sparkle, G11).

Die wertvollsten Güter sind damit (1) **was Michael hört und sieht** (Titel, Interpret, Cover –
privat), (2) die **Automation-Freigabe für Spotify/Musik** und (3) die **Unversehrtheit dessen,
was unter Gnotchis Verantwortung im Perl-Prozess läuft**.

## Datenfluss und Vertrauensgrenzen

```
[Websites / Apps] ─(1) Now-Playing-Daten─▶ [MediaRemote] ─▶ [/usr/bin/perl + Adapter (Bundle)]
                                                                 │ (2) JSON-Zeilen, stdout
                                                                 ▼
[Nutzer: Klick in Insel] ─(3)─▶ [Gnotchi: MediaAdapter / NowPlayingInfo] ─(4) feste Befehle─▶ [Adapter]
                                        │ (5) AppleScript (fest im Code) ─▶ [Spotify / Musik]
                                        ▼
                                 [Insel: Text(verbatim:), Cover]
[Gnotchi] ─(6) Einstellungen ─▶ [UserDefaults, nur dieser Mac]
[Gnotchi] ─(7) Update-Prüfung ─▶ [GitHub: appcast.xml, Release-ZIP]
```

Grenzen: (1)/(2) fremde Herkunft → Gnotchi – Titel, Interpret, Cover und Bundle-ID sind **nicht
vertrauenswürdig** (bei Browsern frei von jeder Website gesetzt) · (2)/(4) Gnotchi ↔ Kindprozess ·
(5) Gnotchi → andere Apps · (7) Gnotchi ↔ Netz.

## Entscheidungen

### G1 – Keine Bedienungshilfen, keine Eingaben (neu, 2026-10-18)
- **Entschieden:** Kein `AXIsProcessTrusted`, keine Freigabe-Anfrage, keine AX-Elemente oder
  -Beobachter, keine Event-Taps, kein globaler Ereignis-Beobachter, keine künstlichen Eingaben.
  Maschinell: SwiftLint-Regel `keine_bedienungshilfen` (Fehler, auch in Tests; Gegenprobe
  18.10.: Regel schlägt bei `AXIsProcessTrusted()` an).
- **Warum:** Das ist der Grund für die Auslagerung aus Seam. Was Gnotchi nicht hat, kann der
  Perl-Prozess nicht erben.

### G2 – Bundle-Signatur und Identität vor jedem Start (vormals Seam E17a, Kern)
- **Entschieden:** `/usr/bin/perl` prüft keine Signatur und lädt das Framework ohne
  Bibliotheksprüfung (belegt: die Homebrew-Fassung des Adapters ist nur ad hoc signiert und läuft
  trotzdem, 18.10.). Gnotchi ist für den Kindprozess „verantwortlich“; **vermutet, nicht
  gemessen:** TCC rechnet dem Perl-Prozess Gnotchis Freigaben zu. Deshalb prüft Gnotchi vor
  **jedem** Perl-Start (Strom, Test, Befehl, Neustart) per `SecStaticCodeCheckValidity` das eigene
  Bundle (verschachtelter Code + Ressourcen, strikt, alle Architekturen) **gegen eine feste
  Anforderung**:
  `anchor apple generic and identifier "dev.mwlr.gnotchi" and certificate leaf[subject.OU] = "LTKJ6Z2VYB"`
  (Apple Development und Developer ID tragen beide die Team-OU). Die Prüfung läuft außerhalb des
  Hauptthreads (30–50 ms gemessen, Review 18.10.). Code: `Gnotchi/Media/BundleIntegrity.swift`,
  `BundleIntegrity.appRequirement`.
- **Warum die Identität:** Gültigkeit ohne Identität stellt jeder mit Schreibrecht per
  `codesign -fs -` wieder her – gemessen 18.10. Ad hoc signiert besteht die Anforderung nicht
  (-67050, Test `testAdHocSignedBundleRejectedByDefaultRequirement`). Ungültig → kein
  Adapter-Start, Rückfall G7, Hinweis in den Einstellungen, Protokolleintrag mit OSStatus
  (-67050 Anforderung nicht erfüllt: falsches Team, ad hoc, Dev-Build ohne Team;
  -67056/-67062 unsigniert bzw. ohne Siegel; -67054/-67021 verändert).
- **Verworfen:** eingebaute SHA-256-Prüfsumme – das Signieren verändert die Framework-Datei nach
  dem Kompilieren, die Konstante wäre nie gültig (Fund 18.10. beim Planen).
  `responsibility_spawnattrs_setdisclaim` – private Schnittstelle.
- **Restrisiko:** Rennen zwischen Prüfung und dem Lesen des Skripts bzw. `dlopen` des Frameworks
  durch Perl; per Dateiüberwachung gewinnbar. Hürde ist das Schreibrecht auf Gnotchi.app (bei
  notarisierten Apps in /Applications zusätzlich der App-Verwaltungs-Schutz von macOS – vermutet,
  nicht gemessen).
- **Messen im Sichttest (offen, für Gnotchi neu):** Erbt der Perl-Prozess Gnotchis Freigaben
  (Automation)? Gemessen werden muss mit Gnotchi selbst – signiert, aus Finder/`open` gestartet.
  **Läufe aus dem Terminal zählen nicht:** dort ist Terminal der verantwortliche Prozess, nicht
  Gnotchi. Ergebnis hier nachtragen. Die Messung in Seam steht ebenfalls aus und gilt nicht für
  Gnotchi.

### G3 – Start ohne Shell, feste Umgebung (vormals Seam E17b)
- **Entschieden:** `Process` mit `executableURL = /usr/bin/perl` (SIP-geschützt) und festem
  Argument-Array; Pfade nur aus `Bundle.main` (`Contents/Resources/mediaremote-adapter.pl`,
  `Contents/Frameworks/MediaRemoteAdapter.framework`, `Contents/MacOS/MediaRemoteAdapterTestClient`).
  Steuerbefehle nur als feste IDs; `seek` als ganze Mikrosekunden (Int64), ≥ 0, endlich, höchstens
  7 Tage; die Obergrenze Dauer setzt die Oberfläche (Regler, Spulen erst beim Loslassen). Nie Daten
  aus dem Strom in Argumente. Jeder Kindprozess (Perl, pgrep) startet mit fester Umgebung
  `PATH=/usr/bin:/bin` – sonst lädt Perl über geerbte `PERL5OPT`/`PERL5LIB` (z. B. per
  `launchctl setenv`) fremden Code, ganz ohne Eingriff ins Bundle (Review 18.10., gemessen).
  Einzige Stelle, die einen Perl-Prozess baut: `MediaAdapter.perlProcess`. Maschinell:
  SwiftLint-Regel `kindprozess_nur_im_adapter` (kein `Process()`, `posix_spawn`, `system(`,
  `popen(` außerhalb von `MediaAdapter.swift`).
- **Ergänzt 18.10. (Security-Review B11):** Lint-Regel `kindprozess_nur_im_adapter` erkennt jetzt auch
  `Process (…)`/`Process(…)` mit Argumenten und die Klassenmethode `Process.run(…)`; Gegenprobe 18.10.
  an einer Probedatei: alle drei Formen Fehler, `ProcessInfo` und Kommentare nicht. Dabei fiel
  `AudioRoute.Process` auf (gleichnamig mit Foundation) → umbenannt in `AudioProcess`.

### G4 – Strom als nicht vertrauenswürdig lesen (vormals Seam E17c)
- **Entschieden:** Zeilenweise, **max. 4 MB je Zeile** (längere verwerfen + zählen, auch über
  Paketgrenzen, `LineSplitter`); `JSONDecoder` in ein `Codable`-Struct mit optionalen Feldern
  (kein `[String: Any]`). Texte: höchstens 2000 Skalare ansehen, Steuer-/Format-/Richtungszeichen
  (U+202A–202E, U+2066–2069, LRM/RLM, BOM …) und Zeilentrenner entfernen, ZWJ/ZWNJ nur zwischen zwei
  behaltenen Zeichen und höchstens 8 je Feld (Emoji-Sequenzen, persische Schrift), höchstens 4
  kombinierende Zeichen in Folge (Zalgo), auf 300 Zeichen **und** 1200 UTF-8-Bytes kürzen.
  Dauer nur endlich, > 0, ≤ 48 h; Position immer endlich und in [0, Dauer]. Bundle-ID nur, wenn
  `BundleID.isValid` (ASCII-Buchstaben/-Ziffern, Punkt, Bindestrich, ≤ 255; aus Seams Link-Regeln
  übernommen); Safari meldet den WebKit-Hilfsprozess, deshalb zuerst die Eltern-App (Mitschnitt
  18.10., `spike/`). Eine unlesbare Zeile leert die Anzeige nicht (sonst Flackern), sie wird
  gezählt; leeres `payload` heißt „nichts läuft“.
- **Ergänzt 18.10. (Security-Review B3):** Zeilen schneiden und JSON dekodieren laufen auf dem
  Lese-Thread (`StreamReader`), nicht auf dem MainActor; zum Hauptthread geht nur das Ergebnis. Je
  Paket zählt nur die letzte brauchbare Zeile (von hinten dekodiert, `MediaAdapter.latestEvent`,
  Test) – frühere sind überholt. Leeres `payload` leert weiterhin, unlesbare Zeilen nicht.

### G5 – Anzeige ohne Interpretation (vormals Seam E17d)
- **Entschieden:** Titel/Interpret nur über `Text(verbatim:)` – SwiftUI würde Markdown in
  `LocalizedStringKey` auswerten. Kein `AttributedString(markdown:)`, keine Links. (Umsetzung mit
  der Insel, Plan Aufgabe 10.)
- **Ergänzt 18.10. (Security-Review B9):** Auch die Versionsnummer aus dem Appcast („Update … verfügbar“
  im Menü) nur per `Text(verbatim:)`.

### G6 – Cover begrenzt dekodieren (vormals Seam E17e)
- **Entschieden:** Base64 ≤ 2 MB, sonst kein Cover. Dekodieren über ImageIO
  (`CGImageSourceCreateWithData`, ohne Zwischenspeicher), nur Typ JPEG/PNG/HEIC. **Vor** dem
  Dekodieren den Header lesen: je Seite ≤ 8192 px und ≤ 16 Mio. Pixel – ein winziges (z. B.
  interlaced) PNG kann 30000 × 30000 px deklarieren und beim Dekodieren hunderte MB und Sekunden
  kosten (Dekompressionsbombe). Dann `CGImageSourceCreateThumbnailAtIndex` mit max. 256 px,
  außerhalb des Hauptthreads (bis ~0,3 s). **Nie URLs aus dem Strom laden** (kein
  `artworkURL`-Abruf → kein SSRF, kein Tracking-Pixel).
- **Ergänzt 18.10. (Security-Review B3):** Höchstens ein Dekodieren gleichzeitig; was währenddessen
  kommt, wartet – nur das neueste (`LatestWins`, Test). Ein wartendes Cover eines schon abgelösten
  Titels wird nicht mehr dekodiert.

### G7 – AppleScript fest im Code (vormals Seam E17f)
- **Entschieden:** Rückfall-Skripte sind Konstanten; einzige variable Größe ist die Spulposition
  als formatierte Zahl. Automation nur für Spotify und Musik, angefragt erst, wenn der Rückfall
  greift oder zum ersten Mal in Spotify gespult wird (siehe unten). Dafür trägt die App die Berechtigung `com.apple.security.automation.apple-events` und
  `NSAppleEventsUsageDescription` (G12). (Umsetzung Plan Aufgabe 11a.)
- **Umgesetzt (`Gnotchi/Media/AppleScriptSource.swift`):** Skripte nur an `com.spotify.client`/
  `com.apple.Music` – jede andere Bundle-ID ergibt kein Skript (Test); nur an Apps, die schon
  laufen (sonst würde `tell application` sie starten) – geprüft vor dem Senden und noch einmal im
  Skript selbst (`if application id … is running`), damit eine gerade beendete App nicht neu startet;
  eigene serielle Queue, weil die erste Abfrage auf den Automation-Dialog wartet; Befehle mit
  3-s-Zeitgrenze, höchstens einer in der Warteschlange. Die Abfrage liefert eine AppleScript-Liste
  (keine Trennzeichen im Text); Antworten laufen durch `NowPlayingInfo.sanitize` und dieselbe
  Dauerprüfung wie der Adapter (G4). Verweigert der Nutzer (Fehler -1743), fragt Gnotchi diese App
  bis zum nächsten Start des Rückfalls nicht mehr.
- **Ergänzt 18.10. – Spotify spult immer per AppleScript, auch während der Adapter läuft:** Spielt
  Spotify über Spotify Connect (externer Lautsprecher), übernimmt das Gerät den MediaRemote-
  Spulbefehl nur kurz und meldet dann die alte Position – die Zeit springt zurück. Gemessen 18.10.:
  fünf Varianten des Adapter-`seek` (brew `media-control`, Gnotchis Skript und Framework, saubere
  Umgebung) wirkungslos; `set player position` per AppleScript wirkt, MediaRemote folgt nach
  ~3 s ohne Rücksprung. Play/Pause/Weiter/Zurück über den Adapter wirken auch über Connect und
  bleiben dort. Ein Weg für lokal und Connect: Entscheidung `NowPlayingModel.seekRoute` (Test),
  Versand `AppleScriptSource.sendSeek` – dasselbe konstante Skript, dieselbe Queue, dieselben
  Prüfungen (nur `com.spotify.client`/`com.apple.Music`, App muss laufen, 3-s-Zeitgrenze, höchstens
  ein Befehl), unabhängig davon, ob der Rückfall läuft. Der erste Spulvorgang löst einmal den
  Automation-Dialog für Spotify aus. Scheitert das Skript (verweigert -1743, Zeitgrenze), spult
  Gnotchi über den Adapter (lokal wirksam, über Connect nicht) und protokolliert die Fehlernummer
  je Nummer einmal, nur mit Bundle-ID (G8). Der Rücksprung des Connect-Geräts selbst ist nicht
  testbar – getestet ist die Weichenstellung.
- **Ergänzt 18.10. (Security-Review B7, B10):** Die Statusabfrage läuft ohne Zeitgrenze nur, bis sie für
  eine App einmal ohne Fehler zurückkam (Zustimmung erteilt); danach `with timeout of 5 seconds` – eine
  hängende App blockiert die Queue nicht mehr unbegrenzt. App-Namen im Hinweis „Automation … nicht
  erlaubt“ laufen durch `AppIcons.cleanName` (bereinigt, gekürzt).

### G8 – Protokoll ohne Inhalte (vormals Seam E17g/E11)
- **Entschieden:** `os.Logger`, Subsystem `dev.mwlr.gnotchi`. Ins Protokoll nur Zustandswechsel
  (Adapter an/aus, Neustart, Rückfall, Signatur ungültig mit OSStatus, Zeilen verworfen) und die
  Bundle-ID der Quelle – **nie Titel, Interpret oder Cover**: was Michael hört und sieht, ist privat.

### G9 – Kindprozess sauber führen (vormals Seam E17h)
- **Entschieden:** Beim Beenden `terminate()`, nach 1 s `kill`. Neustart nach Abbruch mit Pausen
  1 s und 5 s, beim 3. Abbruch in Folge Schluss (Rückfall G7). Nur ein Lauf ≥ 30 s setzt den
  Zähler zurück – nicht jede gelesene Zeile: der Strom meldet direkt nach dem Start `payload:{}`,
  ein „eine Zeile, dann Absturz“-Adapter liefe sonst endlos im 1-s-Takt (Review 18.10.). Eine
  Generationsnummer verwirft veraltete Rückmeldungen nach schnellem `stop()`+`start()`. `test` mit
  10 s Zeitlimit (danach `terminate()`, nach 1 s `kill`). Beim Start verwaiste Adapter-Prozesse
  **dieses** Bundles beenden – Waisen nur per `pgrep -P 1 -f '^/usr/bin/perl <escaped Skriptpfad> '`
  ohne Shell, PID ≤ 1 und eigene PID ausgeschlossen – nicht per `pkill -f` auf einen Kurznamen
  (trifft sonst Fremdes, z. B. `less …/mediaremote-adapter.pl` oder den Adapter einer zweiten
  Instanz). Gemessen 18.10.: ein per `Process` gestartetes, verwaistes Perl erscheint als
  `/usr/bin/perl <Skript> …` mit Eltern-PID 1.
- **Ergänzt 18.10. (Security-Review B4):** Höchstens ein Befehls-Prozess (Play/Pause, Weiter, Zurück,
  Spulen) gleichzeitig; weitere Klicks werden verworfen, nicht angestaut (`OneAtATime`, Test) – wie
  beim AppleScript-Weg.

### G10 – Insel stört nichts (vormals Seam E17i)
- **Entschieden:** `NSPanel` nicht aktivierend; im Zustand „unsichtbar“ `ignoresMouseEvents = true`,
  damit die Menüleiste darunter klickbar bleibt. (Umsetzung Plan Aufgabe 11.)
- **Entschieden (Fensterliste, 18.10.):** Für die Vollbild-Erkennung liest Gnotchi aus
  `CGWindowListCopyWindowInfo` nur Ebene, Lage und Eigentümer-PID – die PID ausschließlich, um
  normale Apps (`activationPolicy == .regular`) zu erkennen, nie Namen oder Titel (Lint-Regel
  `keine_fenstertitel`); keine Bildschirmaufnahme-Freigabe nötig.
- **Ergänzt 18.10. – zweite Notch-App erkennen:** Im selben Durchgang (nur bei sichtbarer Insel,
  außerdem bei App-Start/-Ende, Space-Wechsel und beim Öffnen der Einstellungen) liest Gnotchi aus der
  Fensterliste weiterhin **nur PID, Ebene und Lage**. Ein fremdes Fenster zählt nur, wenn alles gilt:
  Ebene ≥ 25 (über der Menüleiste; eigenes Panel 27, Thaw 23/24 gemessen), oben bündig (± 2 pt),
  schmaler als 90 % des Bildschirms, deckt waagrecht mindestens die halbe Notch-/Pillenbreite ab.
  Für die PID eines solchen Fensters – und **nur für diesen Hinweis** – holt Gnotchi über
  `NSRunningApplication(processIdentifier:)` lokal Name, Bundle-ID, Bundle-Pfad und Art; zählen nur
  Menüleisten-Apps (`.accessory`) außerhalb von macOS (`com.apple.` bzw. `/System/`). **Der App-Name
  kommt nur aus NSRunningApplication(PID), nie aus der Fensterliste; nie Fenstertitel oder
  `kCGWindowOwnerName`** (Lint-Regel `keine_fenstertitel`). Hinweis erst, wenn eine zweite Prüfung
  ~1,5 s später dieselbe App findet; ohne Treffer sofort weg. Der Name (bereinigt wie Strom-Texte,
  höchstens 40 Zeichen) erscheint nur per `Text(verbatim:)` in Menü und Einstellungen, nicht im
  Protokoll. Entscheidung `IslandController.competingNotchApp`/`confirmedCompetitor` (Test).

### G11 – Updates wie Kalli/Seam (vormals Seam E9)
- **Entschieden:** Sparkle 2.10.0 `exactVersion`, `Package.resolved` im Repo (Sparkle-Revision
  `eef1a539`), Appcast im Repo: `SUFeedURL` =
  `https://raw.githubusercontent.com/miwixyz/Gnotchi/main/appcast.xml`. `SUPublicEDKey` derselbe
  öffentliche Schlüssel wie Kalli/Tippi/Seam, `SUVerifyUpdateBeforeExtraction` = YES,
  `SURequireSignedFeed` = YES von Anfang an, `SUEnableAutomaticChecks` nicht gesetzt (Sparkle
  fragt beim ersten Mal). Keine Mitteilung bei gefundenem Update, stattdessen Menüeintrag; im
  Testlauf startet der Updater nicht. `release.sh` prüft die Appcast-Signatur kryptografisch gegen
  das ausgelieferte ZIP und die Feed-Signatur.
- **Einziger Netzwerkzugriff** der App ist diese Update-Prüfung.

### G12 – Gnotchi härten, Berechtigungen per Positivliste (vormals Seam E8)
- **Entschieden:** Hardened Runtime **ohne** Ausnahmen (keine `disable-library-validation`, keine
  `allow-dyld-environment-variables`, kein JIT), Developer ID, notarisiert, keine Sandbox (Perl als
  Kindprozess und MediaRemote gehen darin nicht). Berechtigungen: die App **genau**
  `com.apple.security.automation.apple-events`; eingebetteter Code (Adapter-Framework,
  Test-Programm) **keine**. `release.sh` prüft das am exportierten Build als Positivliste
  (geduldet nur die von Xcode beim Export eingesetzten `com.apple.application-identifier`/
  `com.apple.developer.team-identifier`); Gegenprobe 18.10. an einer ad hoc signierten Kopie:
  Berechtigung am Test-Programm, `disable-library-validation` an der App und fehlende
  Apple-Events-Berechtigung brechen jeweils ab.
- **Signierreihenfolge:** `dev-signed.sh` und `install-signed.sh` signieren von innen nach außen
  ohne `--deep` – Sparkles Teile mit ihren eigenen Berechtigungen, dann Test-Programm und
  Framework ohne, zuletzt die App mit `Gnotchi.entitlements`.
- **Verworfen:** Seams `codesign --deep --entitlements` in `dev-signed.sh` – das hätte Gnotchis
  Berechtigung auch dem Test-Programm und dem Framework gegeben, also genau den Teilen, die unter
  `/usr/bin/perl` laufen.
- **Warum:** Wer Code in Gnotchi einschleust, erbt dessen Automation-Freigaben und dessen
  Verantwortung für den Perl-Prozess.
- **Ergänzt 18.10. (Security-Review B2, B5, B12):** Die Positivliste prüft jetzt **jeden** eingebetteten
  Code-Teil rekursiv (`scripts/entitlement-gate.sh`, von `release.sh` eingelesen): jedes Bundle (.app,
  .xpc, .framework, .appex, .bundle, .plugin) und jede lose Mach-O-Datei unter `Contents/`, ohne
  Symlinks – vorher nur `MacOS/*` und die oberste Ebene der Frameworks, Sparkles XPC-Dienste,
  Updater.app und Autoupdate blieben ungeprüft. Sparkle 2.10.0 gemessen (Release-Build): keine
  Berechtigungen außer `com.apple.application-identifier` an Autoupdate (geduldet). Trockenlauf
  18.10.: Release-Build 12 Teile sauber, signierte Testkopie 14 Teile sauber; Gegenprobe:
  `disable-library-validation` an Downloader.xpc bzw. an einer losen Datei unter
  `Contents/Library/` bricht ab (Exit 1). `release.sh` vergleicht `sparkle:shortVersionString`
  im Appcast und im veröffentlichten Feed genau statt als Teilstring. `dev-signed.sh`/
  `install-signed.sh` schreiben ihr Build-Log in eine per `mktemp` frisch angelegte Datei unter
  `build-dev/` statt an einen festen `/tmp`-Pfad.

### G13 – Niemand außer dem Nutzer steuert Gnotchi (vormals Seam E7)
- **Entschieden:** Kein URL-Schema, kein `NSAppleScriptEnabled`, keine `NSServices`, keine
  XPC-/Distributed-Notification-Schnittstelle.
- **Warum:** Sonst könnten andere Programme Gnotchi als Werkzeug benutzen und über dessen
  Automation-Freigabe Spotify/Musik steuern, ohne selbst gefragt zu werden.

### G14 – Gespeicherte Daten (vormals Seam E10)
- **Entschieden:** Nur Schalter in UserDefaults (`notchMedia`). Titel, Interpret, Cover und
  Verlauf bleiben im Speicher und sind nach dem Beenden weg.
- **Verworfen:** „Zuletzt gehört“-Liste. Das wäre ein Protokoll von Michaels Hörgewohnheiten;
  erst mit eigenem Durchgang, falls je gewünscht.
- **Ergänzt 18.10. (Security-Review) – keine echten Hördaten im Repo:** Testzeilen, Spezifikation und
  `spike/nowplaying-beispiel.jsonl` haben Aufbau, Zahlen und Zeitpunkte des Mitschnitts vom 18.10.,
  aber erfundene Titel, Interpreten, Alben, Werbetitel und IDs. Neue Mitschnitte vor dem Einchecken
  genauso umschreiben; echte Werte nur lokal außerhalb des Repos. Seit dem 18.10. maschinell geprüft, siehe G16.

### G15 – Wiedergabeweg aus Core Audio, nur lesen (neu, 2026-10-18)
- **Entschieden:** Um „Auf anderem Gerät“ (Spotify Connect) und AirPlay/Bluetooth anzuzeigen, liest
  Gnotchi über die öffentliche Core-Audio-API (keine Freigabe nötig, gemessen 18.10.) nur
  Eigenschaften: aus `kAudioHardwarePropertyProcessObjectList` je Prozess **PID, Bundle-ID und
  `kAudioProcessPropertyIsRunningOutput`** (gibt Ton aus ja/nein), vom Standard-Ausgabegerät nur
  **Transportart und Namen**. Es wird **kein Ton aufgenommen**, kein Tap, kein Aggregat-Gerät, nichts
  geändert (`Gnotchi/Media/AudioRoute.swift`, nur `AudioObjectGetPropertyData[Size]`). Abgefragt alle
  2 s, nur solange die Insel sichtbar ist und Musik läuft; Lesen außerhalb des Hauptthreads.
  Gerätenamen vergibt der Nutzer frei → bereinigt wie Strom-Texte (G4), höchstens 40 Zeichen, nur
  `Text(verbatim:)` (G5); nicht ins Protokoll (G8). Die PID der Quell-App kommt von
  `NSRunningApplication` (lokal), nicht aus dem Strom.
- **Fehlalarm vermeiden:** „Anderes Gerät“ erst nach > 2 s Stille bei laufender Wiedergabe; Helfer-
  Prozesse derselben App (`<id>.…`) zählen mit; spielt der geteilte `com.apple.WebKit.GPU`-Prozess,
  gilt Stille der App als unbekannt (Safari); kein Core-Audio-Objekt → unbekannt → nichts angezeigt.

### G16 – Keine echten Hördaten im Repo (neu, 2026-10-18)
- **Vorfall 18.10.:** Ein echter Now-Playing-Mitschnitt von Michaels Mac (was er an dem Morgen
  gehört und gesehen hat) wurde als Messgrundlage in `spike/` eingecheckt, echte Titel standen in
  Testzeilen und Spezifikation. Bemerkt im Security-Review desselben Tages. Die Daten wurden
  durch erfundene ersetzt (G14) und die Git-Historie mit `git filter-repo` umgeschrieben, damit
  die echten Werte in keinem Commit mehr stehen. Das Repo war zu dem Zeitpunkt nur lokal, nichts
  wurde veröffentlicht. Die Regel aus G14 („vor dem Einchecken umschreiben“) gab es da schon als
  Vorsatz – er hat nicht gereicht.
- **Regel:** **Messdaten nur nach `/tmp`, nie in einen Repo-Ordner.** Ins Repo kommt ein Beispiel
  erst, wenn Titel, Interpreten, Alben, Werbetitel und IDs erfunden sind.
- **Entschieden – Mechanismus statt Vorsatz:** `scripts/privacy-gate.sh` (POSIX sh) lehnt ab:
  (a) Pfade mit „mitschnitt“ oder „capture“ im Namen (Groß-/Kleinschreibung egal), `.jsonl`
  außerhalb von `spike/` und jede Datei in `spike/`, deren Zeile 1 nicht `SYNTHETISCH` enthält
  (bei `.jsonl` die Zeile `{"_hinweis":"SYNTHETISCH – …"}`, ohne `payload` – der Adapter-Leser
  überspringt sie, Test `testSyntheticMarkerLineIsSkipped`); (b) Dateien unter `GnotchiTests/`
  mit einer Now-Playing-Zeile (`"payload"` und `"title"` in einer Zeile) ohne `// SYNTHETISCH` in
  den ersten 10 Zeilen. Jeder Fund nennt Datei und „→ ZU TUN“. Kein Übergehen per Variable.
- **Verdrahtet an drei Stellen:** `make lint` (Index und ungetrackte Dateien), `scripts/release.sh`
  vor dem Bauen, `.githooks/pre-commit` nur auf den gestagten Inhalt (`--staged`, liest aus dem
  Index). Den Hook schaltet `make hooks` ein (`git config core.hooksPath .githooks`), einmal je
  Klon. Gegenprobe 18.10.: eine gestagte `spike/test-mitschnitt.jsonl` blockiert den Commit.
- **Grenze:** Ob ein Titel echt ist, kann kein Skript erkennen. Die Markierung `SYNTHETISCH` ist
  eine bewusste Unterschrift dessen, der die Daten umgeschrieben hat; das Gate erzwingt, dass
  niemand sie vergisst, und fängt die naheliegenden Dateinamen ab. Spezifikationen (`specs/`)
  prüft es nicht – dort gilt die Regel weiter als Vorsatz.

## Bedrohungsmodell (STRIDE, je Grenze)

| | Grenze | Bedrohung | Antwort |
|---|---|---|---|
| **S** | Bundle → Perl | ausgetauschtes Skript/Framework gibt sich als Adapter aus | G2 |
| **S** | Netz → Gnotchi | gefälschtes Update | G11: EdDSA vor dem Entpacken, signierter Feed, Schlüssel nur im Schlüsselbund |
| **T** | Website → Titel | manipulierte Titel (Steuerzeichen, RTL-Tricks, Zalgo, Markdown) | G4, G5 |
| **T** | anderer Prozess → Gnotchi | Code-Einschleusung | G12: Hardened Runtime ohne Ausnahmen, Bibliotheksprüfung |
| **T** | anderer Prozess → Perl | Code über geerbte Umgebung (`PERL5OPT`) | G3: feste Umgebung |
| **R** | – | Wechsel auf Rückfall ohne Spur | G8: jeder Wechsel einmal protokolliert |
| **I** | Gnotchi → Protokoll | Hörgewohnheiten im Log | G8 |
| **I** | Strom → Netz | Cover-URL lädt Tracking-Pixel | G6: keine URLs |
| **D** | Adapter → Gnotchi | Flut, Riesenzeilen, Dekompressionsbombe, Hänger, Absturzschleife | G4, G6, G9, `--debounce=100` |
| **E** | Perl als Kind | fremder Code mit Gnotchis Freigaben | G2, G3. **Neu bewertet:** Ohne Bedienungshilfen (G1) schrumpft der Schaden auf das, was Gnotchi selbst darf – Apple Events an Spotify/Musik, sofern der Nutzer sie erteilt hat, und Now-Playing lesen, was der Adapter ohnehin tut. Ob der Kindprozess überhaupt erbt, ist offen (G2, Sichttest) |
| **E** | Gnotchi → Spotify/Musik | AppleScript-Einschleusung | G7 |
| **E** | andere Programme → Gnotchi | Gnotchi als Werkzeug missbrauchen | G13 |

## Negativraum: was wir stillschweigend annehmen

1. **Apple duldet den Perl-Weg weiter.** Wenn nicht, greift der Rückfall G7, nichts bricht.
2. **Der Adapter-Autor bleibt vertrauenswürdig.** Deshalb Quelltext eingespielt statt geladen,
   jede neue Version per Diff gelesen (Skript 290 Zeilen, Stand 0.7.7) und vom Build neu signiert
   (`Vendor/mediaremote-adapter/VENDOR.md`).
3. **Gnotchi hat keine Bedienungshilfen-Freigabe: erbt der Perl-Prozess Gnotchis Rechte, sind das
   nur Apple Events an Spotify/Musik.** Ob er erbt, ist nicht gemessen; der Sichttest muss es mit
   Gnotchi selbst messen, nicht aus dem Terminal (G2).
4. **Schlimmster Einzelfall: Benutzerkonto kompromittiert** → kann ohnehin Gnotchi.app ersetzen;
   dann bricht die Signatur und TCC entzieht die Automation-Freigabe. G2 schließt die Lücke, dass
   der Perl-Weg diese Signaturprüfung umgehen würde – aber nur mit der festgenagelten Identität;
   ohne sie würde ein Angreifer mit Schreibrecht das Bundle per `codesign -fs -` neu versiegeln.
   Offen bleibt das Rennen zwischen Prüfung und Laden (Restrisiko G2).
5. **Michaels GitHub-Konto wird übernommen.** Ohne den EdDSA-Schlüssel (nur im Schlüsselbund) kann
   der Angreifer kein Update ausliefern, das Gnotchi annimmt.
6. **Im Ernstfall:** In den Einstellungen „Musik in der Notch“ ausschalten (kein Perl-Start mehr,
   sobald verdrahtet) und unter Systemeinstellungen → Datenschutz & Sicherheit → Automation die
   Freigabe für Spotify/Musik entziehen.

## Abhängigkeiten

| Abhängigkeit | Entscheidung | Warum |
|---|---|---|
| Sparkle | übernehmen, Version und Commit-SHA in `Package.resolved` festgeschrieben (Kalli-Muster mit eingespieltem Lockfile) | einzige ausgereifte Update-Lösung außerhalb des App Stores, bei Kalli und Seam erprobt |
| `mediaremote-adapter` (BSD-3, `github.com/ungive/mediaremote-adapter`) | **Quelltext eingespielt** (`Vendor/mediaremote-adapter/`, Commit `0e82bf1c`, Lizenz in `THIRD-PARTY-LICENSES.md`), Framework von Gnotchis Build gebaut und mit Gnotchis Developer ID signiert, **nicht gelinkt** (nur Perl lädt es); neue Version nur per gelesenem Diff, die Bundle-Signatur deckt sie ab (G2) | einziger bekannter Weg zu systemweiten Now-Playing-Daten seit macOS 15.4; ein Autor, ~290 Sterne → nicht aus der Registry, sondern eingespielt und geprüft. Kein vorgebautes Binary |
| Schrift Plus Jakarta Sans | wie Kalli/Seam, SIL OFL | App-Familie |
| Notch-Apps Boring Notch, DynamicNotch, Atoll, FunNotch, NotchMore (GPL-3.0) | **nur lesen**, kein Code | GPL wäre mit Gnotchis MIT-Lizenz unverträglich |

Kein Paket wird nach einem von einem Sprachmodell vorgeschlagenen Namen installiert, nur nach der
Adresse aus dem offiziellen README (Slopsquat).

## Ausstiegskriterien vor dem ersten Release

- [x] Lint-Regeln für G1 und G3, Gegenprobe 18.10.: beide schlagen an
- [x] Tests für G2, G3, G4, G6, G9 (`GnotchiTests/`, aus Seam übernommen) grün
- [x] Berechtigungs-Gate in `release.sh` (G12), Gegenprobe 18.10. an ad hoc signierter Kopie
- [x] G5, G7, G10 umgesetzt (Plan Aufgaben 10, 11, 11a), am Code geprüft 18.10.: Inhalte nur
      `Text(verbatim:)`, kein `AttributedString(markdown:)`; Rückfall `AppleScriptSource.swift`;
      Panel `.nonactivatingPanel` + `ignoresMouseEvents` im unsichtbaren Zustand
- [ ] Sichttest: Erbt der Perl-Prozess Gnotchis Freigaben? Mit Gnotchi selbst gemessen, nicht aus
      dem Terminal (G2)
- [ ] `codesign -d --entitlements - --xml` am signierten Build: App nur Apple Events, eingebetteter
      Code ohne
- [x] Datenschutz-Gate (G16) in `make lint`, `release.sh` und Pre-Commit-Hook, Gegenprobe 18.10.
- [x] `rafter-code-review` gegen G1–G16 (18.10., kein kritischer/hoher Fund, Härtungen B1–B12
      umgesetzt) und `rafter run` (18.10., Scan `c4fa8f06`, Standardmodus): 1 Warnung R-33E2F
      `release.sh` „curl in Interpreter“ – Fehlalarm (Feed wurde nur als Daten geparst), trotzdem
      umgestellt auf Datei laden, dann parsen
