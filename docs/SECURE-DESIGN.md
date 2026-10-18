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

## Was Gnotchi ist und welche Macht es hat

Menüleisten-App für macOS 27. Eine Insel in der MacBook-Notch (auf Bildschirmen ohne Notch eine
Pille oben mittig) zeigt den laufenden Titel jeder Quelle und steuert die Wiedergabe. Apple bietet
dafür keine öffentliche Schnittstelle; Gnotchi nutzt wie Boring Notch/Cyclop `mediaremote-adapter`
(BSD-3), der über den systemeigenen `/usr/bin/perl` an `MediaRemote.framework` kommt. Rückfall:
AppleScript für Spotify und Musik.

**Warum eine eigene App:** Entworfen wurde das in Seam. Seam hält die Bedienungshilfen-Freigabe,
und der Perl-Kindprozess könnte Seams Freigaben erben (vermutet, siehe G2). Eine Freigabe, mit der
ein Prozess die Oberfläche aller Apps lesen und Eingaben auslösen kann, gehört nicht in die Nähe
eines Interpreters, der Fremdcode lädt. Gnotchi trennt das.

**Befugnisse von Gnotchi:**

- **Keine Bedienungshilfen-Freigabe.** Gnotchi fragt sie nie an und prüft sie nie (G1).
- **Apple Events** (Berechtigung `com.apple.security.automation.apple-events`), tatsächlich
  benutzt nur für Spotify und Musik. Welche App Gnotchi steuern darf, erteilt der Nutzer je
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

### G5 – Anzeige ohne Interpretation (vormals Seam E17d)
- **Entschieden:** Titel/Interpret nur über `Text(verbatim:)` – SwiftUI würde Markdown in
  `LocalizedStringKey` auswerten. Kein `AttributedString(markdown:)`, keine Links. (Umsetzung mit
  der Insel, Plan Aufgabe 10.)

### G6 – Cover begrenzt dekodieren (vormals Seam E17e)
- **Entschieden:** Base64 ≤ 2 MB, sonst kein Cover. Dekodieren über ImageIO
  (`CGImageSourceCreateWithData`, ohne Zwischenspeicher), nur Typ JPEG/PNG/HEIC. **Vor** dem
  Dekodieren den Header lesen: je Seite ≤ 8192 px und ≤ 16 Mio. Pixel – ein winziges (z. B.
  interlaced) PNG kann 30000 × 30000 px deklarieren und beim Dekodieren hunderte MB und Sekunden
  kosten (Dekompressionsbombe). Dann `CGImageSourceCreateThumbnailAtIndex` mit max. 256 px,
  außerhalb des Hauptthreads (bis ~0,3 s). **Nie URLs aus dem Strom laden** (kein
  `artworkURL`-Abruf → kein SSRF, kein Tracking-Pixel).

### G7 – AppleScript fest im Code (vormals Seam E17f)
- **Entschieden:** Rückfall-Skripte sind Konstanten; einzige variable Größe ist die Spulposition
  als formatierte Zahl. Automation nur für Spotify und Musik, angefragt erst, wenn der Rückfall
  greift. Dafür trägt die App die Berechtigung `com.apple.security.automation.apple-events` und
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

### G10 – Insel stört nichts (vormals Seam E17i)
- **Entschieden:** `NSPanel` nicht aktivierend; im Zustand „unsichtbar“ `ignoresMouseEvents = true`,
  damit die Menüleiste darunter klickbar bleibt. (Umsetzung Plan Aufgabe 11.)
- **Entschieden (Fensterliste, 18.10.):** Für die Vollbild-Erkennung liest Gnotchi aus
  `CGWindowListCopyWindowInfo` nur Ebene, Lage und Eigentümer-PID – die PID ausschließlich, um
  normale Apps (`activationPolicy == .regular`) zu erkennen, nie Namen oder Titel (Lint-Regel
  `keine_fenstertitel`); keine Bildschirmaufnahme-Freigabe nötig.

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
- [ ] G5, G7, G10 umgesetzt (Plan Aufgaben 10, 11, 11a)
- [ ] Sichttest: Erbt der Perl-Prozess Gnotchis Freigaben? Mit Gnotchi selbst gemessen, nicht aus
      dem Terminal (G2)
- [ ] `codesign -d --entitlements - --xml` am signierten Build: App nur Apple Events, eingebetteter
      Code ohne
- [ ] `rafter-code-review` gegen G1–G14 und `rafter run` – braucht das Repo auf GitHub (noch lokal)
