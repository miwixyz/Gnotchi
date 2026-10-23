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
| G17 | – (neu, 0.2.0) | Tippi-Meldung: nur Anzeige, Schema, Zeitlimit |
| G18 | – (neu, 0.2.0) | Mikrofon/Kamera: nur „ob“ und „wer“, nie ins Protokoll |
| G19 | – (neu, 0.2.0) | Kopfhörer-Hinweis: nur Standard-Ausgang beobachten |
| G20 | – (neu, 0.2.0) | Ausgang setzen nur auf Klick, gegen frische Liste |
| G21 | – (neu, 0.3.0) | Tippis Live-Text: eigener Socket, beidseitig geprüft, nie protokolliert |
| G22 | – (neu, 0.3.0) | Qotti-Kontingent: nur Zahlen, Schema, nur Anzeige |
| G23 | – (neu, 0.4.0) | Update-Meldung der App-Familie: nur Schema, feste Texte, nur Anzeige |
| G24 | – (neu, 0.4.0) | Klick öffnet nur die echte, signaturgeprüfte App |
| G25 | – (neu, 0.4.0) | Medienfilter speichert nur App-Kennungen |
| G26 | – (neu, 0.5.0) | Kallis nächster Termin: eigener Socket, beidseitig geprüft, nie protokolliert |
| G27 | – (neu, 0.5.0) | Spiegel: Kamera nur sichtbar, Bild nur in der Vorschau-Ebene |
| G28 | – (neu, 0.6.0) | Hilfsprogramm „Gnotchi Mitteilungen“: einzige Bedienungshilfen-Freigabe, kleinstmöglich |
| G29 | – (neu, 0.6.0) | Mitteilungs-Weg: beidseitig geprüft, nur ausgewählte Apps, nie protokolliert |
| G30 | – (neu, 0.6.0) | Knöpfe und Anrufe: nur echter Klick, nur gemeldete Aktion, nur dieses Banner |
| G31 | – (neu, 0.7.0) | Wetter: zwei feste Adressen, nur der gewählte Ort geht raus, Antwort als Fremddaten |
| G32 | – (neu, 0.8.0; ergänzt 0.9.1) | Dateiablage: Verweise, nichts ausführen, Ziehen ohne Beobachter, ZIP im Prozess; Dateiversprechen als eigene Kopie |

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

- **Keine Bedienungshilfen-Freigabe.** Gnotchi fragt sie nie an und prüft sie nie (G1). Ab 0.6.0 hält sie
  ausschließlich das eingebettete Hilfsprogramm „Gnotchi Mitteilungen“, ein eigener Prozess mit eigener
  Kennung, nur bei eingeschalteten Mitteilungen (G28).
- **Apple Events** (Berechtigung `com.apple.security.automation.apple-events`), tatsächlich
  benutzt nur für Spotify und Musik (Rückfall G7) und fürs Spulen in Spotify. Welche App Gnotchi steuern darf, erteilt der Nutzer je
  Ziel-App im macOS-Dialog (Automation).
- **Ein Kindprozess:** `/usr/bin/perl` mit dem Adapter-Skript und -Framework aus dem eigenen
  Bundle. Er liest systemweit, was gerade spielt, und sendet Steuerbefehle (Play/Pause, Weiter,
  Zurück, Spulen).
- **Netz:** die Update-Prüfung (Sparkle, G11); ab 0.7.0 bei eingeschaltetem Wetter Open-Meteo (G31).

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
[Gnotchi] ─(6) Einstellungen ─▶ [UserDefaults, nur dieser Mac] ─(6a) Schalter tippiRecording ─▶ [Tippi liest]
[Gnotchi] ─(7) Update-Prüfung ─▶ [GitHub: appcast.xml, Release-ZIP]
[Tippi / jeder lokale Prozess] ─(8) distnoted com.tippi.app.aufnahme ─▶ [Gnotchi: TippiLink → Insel]
[Core Audio / CoreMediaIO] ─(9) „nimmt auf“, Kamera läuft, Standard-Ausgang ─▶ [Gnotchi]
[Nutzer: Klick im Ausgabe-Menü] ─(10) Standard-Ausgabegerät setzen ─▶ [Core Audio]
[Tippi, geprüft] ─(11) Unix-Socket live.sock, Live-Vorschau-Text ─▶ [Gnotchi: LiveTextServer → Insel]
[Qotti / jeder lokale Prozess] ─(12) distnoted app.qotti.local.kontingent ─▶ [Gnotchi: QottiLink → Insel]
[Familien-App / jeder lokale Prozess] ─(13) distnoted app.mwlr.familie.update ─▶ [Gnotchi: FamilyUpdateLink → Insel]
[Nutzer: Klick auf Update] ─(13a) Signaturprüfung, App öffnen, distnoted …update.show ─▶ [echte Familien-App]
[Mitteilungszentrale] ─(14) AX: Banner lesen, Fenster verschieben, Aktion ─▶ [Gnotchi Mitteilungen (eigene Freigabe)]
[Gnotchi Mitteilungen, geprüft] ─(14a) Unix-Socket notify.sock: Mitteilungen ⇄ Filter/Befehle ─▶ [Gnotchi: NotifyLink → Insel]
[beliebige App: Ziehen] ─(16) Datei-URLs beim Loslassen auf der Insel ─▶ [Gnotchi: ShelfLink → ablage.json (Lesezeichen)]
[Gnotchi: Ablage] ─(16b) Rausziehen / Teilen / AirDrop / ZIP (libarchive) ─▶ [Ziel-App, Downloads]
[Gnotchi: WeatherLink] ─(15) HTTPS, gerundete Koordinaten / Ortsname ─▶ [api. / geocoding-api.open-meteo.com] ─(15a) JSON ─▶ [Insel]
```

Grenzen: (1)/(2) fremde Herkunft → Gnotchi – Titel, Interpret, Cover und Bundle-ID sind **nicht
vertrauenswürdig** (bei Browsern frei von jeder Website gesetzt) · (2)/(4) Gnotchi ↔ Kindprozess ·
(5) Gnotchi → andere Apps · (7) Gnotchi ↔ Netz · (8) jeder lokale Prozess → Gnotchi (G17) ·
(9) System → Gnotchi, App-Namen sind Fremddaten (G18, G19) · (10) Gnotchi → Systemeinstellung (G20) ·
(6a) Gnotchis Einstellungsdatei → Tippi (G17) · (11) Tippi ↔ Gnotchi über den Socket, Diktattext,
beidseitig signaturgeprüft (G21) · (12) jeder lokale Prozess → Gnotchi, nur Zahlen (G22) · (13) jeder lokale
Prozess → Gnotchi, nur Kürzel und Versionsnummer (G23) · (13a) Gnotchi → andere App, nur auf Klick, nur die
signaturgeprüfte (G24) · (14) Mitteilungszentrale → Hilfsprogramm, fremde Inhalte jeder App, das Hilfsprogramm
hält Bedienungshilfen (G28) · (14a) Hilfsprogramm ↔ Gnotchi über den Socket, beidseitig signaturgeprüft, Befehle
nur aus Klicks (G29, G30).

## Entscheidungen

### G1 – Keine Bedienungshilfen, keine Eingaben (neu, 2026-10-18)
- **Entschieden:** Kein `AXIsProcessTrusted`, keine Freigabe-Anfrage, keine AX-Elemente oder
  -Beobachter, keine Event-Taps, kein globaler Ereignis-Beobachter, keine künstlichen Eingaben.
  Maschinell: SwiftLint-Regel `keine_bedienungshilfen` (Fehler, auch in Tests; Gegenprobe
  18.10.: Regel schlägt bei `AXIsProcessTrusted()` an).
- **Warum:** Das ist der Grund für die Auslagerung aus Seam. Was Gnotchi nicht hat, kann der
  Perl-Prozess nicht erben.
- **Kein Widerspruch, gemessen 18.10.:** Im TCC-Protokoll steht Gnotchi als *anfragend* bei
  `kTCCServiceAccessibility`, mit `accessing` = Seam, Vorssaint o. Ä. Das ist der AX-Server von
  macOS in jeder App: Liest ein Bedienungshilfen-Programm Gnotchis Fenster, prüft er dessen
  Freigabe. Belegt mit `tools/ax-probe.swift`: 15 s Ruhe → 0 Einträge; Abfrage an Gnotchi →
  40 ms später „Gnotchi prüft ax-probe“; dieselbe Abfrage an Finder → „Finder prüft ax-probe“.
  Gnotchi fragt dabei nichts für sich selbst an und liest nichts.
- **Ergänzt 22.10. (0.6.0, G28):** Mitteilungen brauchen Bedienungshilfen. Sie liegen **nicht** bei Gnotchi, sondern
  beim eingebetteten Hilfsprogramm `Gnotchi Mitteilungen.app` (`dev.mwlr.gnotchi.mitteilungen`), gestartet über
  LaunchServices, also eigener verantwortlicher Prozess. Gemessen 22.10. mit `tools/responsible-pid.swift`:
  Hilfsprogramm → verantwortlich es selbst, Gnotchi → Gnotchi. Die Lint-Regel gilt weiter für Gnotchi und die
  Tests, nur `GnotchiMitteilungen/` ist ausgenommen. Verworfen: XPC-Dienst im Gnotchi-Paket (dort wäre Gnotchi
  verantwortlich und bekäme die Freigabe, samt Perl-Kind).

### G2 – Bundle-Signatur und Identität vor jedem Start (vormals Seam E17a, Kern)
- **Entschieden:** `/usr/bin/perl` prüft keine Signatur und lädt das Framework ohne
  Bibliotheksprüfung (belegt: die Homebrew-Fassung des Adapters ist nur ad hoc signiert und läuft
  trotzdem, 18.10.). Gnotchi ist für den Kindprozess „verantwortlich“; **gemessen 18.10.
  (Sichttest unten):** TCC rechnet dem Perl-Prozess Gnotchis Freigaben zu. Deshalb prüft Gnotchi vor
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
- **Gemessen im Sichttest 18.10. (v0.1.0 Build 45, notarisiert, per `open` aus /Applications
  gestartet): Ja, der Perl-Prozess erbt Gnotchis Freigaben.** Belege:
  1. `tools/responsible-pid.swift` (liest `responsibility_get_pid_responsible_for_pid`, nur lesend):
     Adapter `/usr/bin/perl` pid 49976 (Eltern-PID 49962) → verantwortlich **49962 =
     /Applications/Gnotchi.app**. Gegenprobe: ein Perl aus der Claude-Shell → verantwortlich
     Obsidian. Die Abfrage unterscheidet also wirklich.
  2. tccd entscheidet über den verantwortlichen Prozess: Im TCC-Protokoll stehen Anfragen von
     Hilfsprozessen als `attribution={responsible={… Music …}, accessing={… AUHostingService …}}`.
     Eine TCC-Anfrage des Adapters würde also gegen Gnotchis Freigaben (Automation Spotify/Musik)
     entschieden.
  3. Der Adapter selbst stellte seit dem Start keine TCC-Anfrage (0 Einträge zu pid 49976) –
     Now-Playing über MediaRemote ist nicht TCC-geschützt.
  Nicht ausgeübt: Ein Apple Event aus dem Adapter heraus ginge nur mit verändertem Skript, und genau
  das verhindert G2. **Folge:** G2 bleibt die tragende Sperre; der Schaden bei Umgehung ist auf
  Gnotchis eigene Freigaben begrenzt (siehe Angriffstabelle Zeile E), Bedienungshilfen hat Gnotchi
  nicht (G1). Die Seam-Messung steht weiter aus und folgt nicht aus dieser.

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
  (Adapter an/aus, Neustart, Rückfall, Signatur ungültig mit OSStatus, Zeilen verworfen,
  Selbsttest gescheitert mit Ursache/Exit-Code/Signal, Versuchsnummer und Pause; ab 0.2.0
  Tippi-Aufnahme angezeigt/beendet, Ausgabegerät gesetzt mit Übertragungsart oder OSStatus,
  Beobachter nicht angemeldet mit OSStatus) und die
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
- **Ergänzt 20.10. (0.1.1) – gescheiterter Selbsttest wird wiederholt:** Am 19.10. scheiterte der
  `test` 1,7 Min. nach dem Booten (Gnotchi als Anmeldeobjekt); der Rückfall blieb 20 Std. stehen,
  ein Neustart von Gnotchi behob es. Ursache unbekannt. Jetzt neuer Versuch nach 5 s, 30 s, 2 Min.,
  danach alle 5 Min. ohne Ende (`MediaAdapter.retestDelay`, Test) – jeder Versuch wieder mit
  Signaturprüfung (G2) und Waisensuche. Währenddessen bleibt der Zustand `unavailable`, der
  Rückfall (G7) läuft weiter; erst ein bestandener Test startet den Strom. `stop()` (Schalter aus)
  und ein Signaturfehler erhöhen die Generation und beenden die Kette – kein zweiter Strom.
  Das Protokoll unterscheidet die Ursache: Zeitlimit, Exit-Code, Signal, Start fehlgeschlagen
  (`MediaAdapter.testOutcome`, Test) – nur Codes, Versuchsnummer und Pause (G8).

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
- **Einziger Netzwerkzugriff** der App ist diese Update-Prüfung. **Ab 0.7.0 (G31):** dazu, nur bei eingeschaltetem
  „Wetter in der Notch“ (ab Werk aus), Open-Meteo an zwei festen Adressen.

### G12 – Gnotchi härten, Berechtigungen per Positivliste (vormals Seam E8)
- **Entschieden:** Hardened Runtime **ohne** Ausnahmen (keine `disable-library-validation`, keine
  `allow-dyld-environment-variables`, kein JIT), Developer ID, notarisiert, keine Sandbox (Perl als
  Kindprozess und MediaRemote gehen darin nicht). Berechtigungen: die App **genau**
  `com.apple.security.automation.apple-events` (ab 0.5.0 zusätzlich `com.apple.security.device.camera`
  für den Spiegel, G27); eingebetteter Code (Adapter-Framework,
  Test-Programm) **keine**. `release.sh` prüft das am exportierten Build als Positivliste
  (geduldet nur die von Xcode beim Export eingesetzten `com.apple.application-identifier`/
  `com.apple.developer.team-identifier`); Gegenprobe 18.10. an einer ad hoc signierten Kopie:
  Berechtigung am Test-Programm, `disable-library-validation` an der App und fehlende
  Apple-Events-Berechtigung brechen jeweils ab.
- **Ab 0.6.0:** Das Hilfsprogramm `Contents/Library/LoginItems/Gnotchi Mitteilungen.app` hat **keine**
  Berechtigungen (Bedienungshilfen sind keine, der Nutzer erteilt sie), Hardened Runtime, Developer ID. Es fällt
  unter die rekursive Positivliste (`entitlement-gate.sh`: alles nicht Genannte darf keine haben); `release.sh`
  prüft zusätzlich, dass es da und gültig signiert ist.
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
  XPC-Schnittstelle. Distributed Notifications nur **empfangend und nur zur Anzeige** (ab 0.2.0,
  G17: Tippi-Aufnahme) – eine Meldung löst nie einen Befehl, nie Apple Events, nie einen Prozess-
  start aus, nur Text und Pegel in der Insel. Ab 0.3.0 dazu der Live-Text-Socket (G21): ebenfalls nur
  Anzeige, nur von einem Developer-ID-signierten Tippi angenommen, keine Befehle. Ab 0.4.0 (G23/G24):
  Update-Meldungen der App-Familie ebenfalls nur Anzeige; erst ein **Klick des Nutzers** öffnet die
  gemeldete App – die fest im Code zugeordnete, signaturgeprüfte, nie einen Pfad aus der Meldung.
  Ab 0.6.0 (G29/G30): Über `notify.sock` kommen vom geprüften Hilfsprogramm nur Mitteilungen zur Anzeige; Befehle
  laufen in die **andere** Richtung (Gnotchi → Hilfsprogramm) und entstehen nur aus einem Klick in der Insel.
- **Warum:** Sonst könnten andere Programme Gnotchi als Werkzeug benutzen und über dessen
  Automation-Freigabe Spotify/Musik steuern, ohne selbst gefragt zu werden.

### G14 – Gespeicherte Daten (vormals Seam E10)
- **Entschieden:** Nur Schalter in UserDefaults (`notchMedia`, `expandDelay`; ab 0.2.0
  `headphoneNotice`, `micCamera`, `tippiRecording` – letzteren liest Tippi, G17; ab 0.3.0 `qottiQuota`; ab 0.4.0
  `liveRotation`, `headphoneActivity`, `familyUpdates` – liest jede Familien-App vor dem Senden, G23 – und
  `mediaExcluded`, eine Liste von Bundle-IDs, G25). Update-Meldungen (G23) und gesehene Wiedergabe-Apps leben nur
  im Speicher. Titel, Interpret, Cover und
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

### G17 – Tippi-Meldung: nur Anzeige, Schema, Zeitlimit (neu, 2026-10-20, 0.2.0)
- **Weg:** Tippi (nicht sandboxed, Team LTKJ6Z2VYB wie Gnotchi) sendet `com.tippi.app.aufnahme` über
  `DistributedNotificationCenter`, `userInfo = ["v": 1, "state": …, "level": …]`, beim Aufnehmen
  10 Hz, beim Umwandeln 1 Hz, `idle` am Ende. `TippiLink` empfängt.
- **Jeder lokale Prozess kann senden und mitlesen.** Antwort: Schema statt Vertrauen – `v` = 1,
  `state` ∈ {recording, transcribing, idle}, `level` endliche Zahl, kein Bool, auf 0…1 begrenzt;
  alles andere verworfen, unbekannte Schlüssel ignoriert (`TippiLink.parse`, Test). Die Insel zeigt
  nur feste Texte („nimmt auf“, „wandelt um“) und Gnotchis eigene Laufzeit; nichts aus der Nachricht
  wird als Text angezeigt. Pegel höchstens 30×/s an die Ansicht, Zustand und Pegel getrennt (die
  Insel-Steuerung liest keine 10-Hz-Werte). Ohne Meldung 3 s → beendet (Tippi-Absturz lässt die
  Insel nicht hängen). Gemessen 20.10. mit `tools/fake-tippi.swift`: Ablauf angezeigt/beendet
  sekundengenau, verstummt → nach 3 s weg, sechs kaputte Nachrichten → keine Insel, kein Protokoll.
- **Restrisiko (hingenommen):** Ein fremder Prozess kann eine Aufnahme vortäuschen (Anzeige fester
  Texte) und mitlesen, **dass** diktiert wird (nie was).
- **Tippi blendet seine Pille aus, wenn Gnotchi anzeigt:** Tippi prüft beim Start jedes Diktats, ob
  ein Prozess `dev.mwlr.gnotchi` läuft, mit Team LTKJ6Z2VYB signiert ist, Version ≥ 0.2.0 hat und
  der Schalter `tippiRecording` nicht aus ist (CFPreferences, fehlend = an). Restrisiko: Wer als
  derselbe Nutzer Gnotchis Einstellung schreiben kann, kann Tippis Pille ausblenden – macOS' oranger
  Mikrofon-Punkt bleibt immer (hingenommen; ein solcher Angreifer kann ohnehin mehr).
- **Vollbild:** Die Aufnahme zeigt Gnotchi auch über Apps im Vollbild – sonst wäre sie nirgends zu
  sehen, weil Tippi seine Pille ausblendet.

### G18 – Mikrofon/Kamera: nur „ob“ und „wer“, nie ins Protokoll (neu, 2026-10-20, 0.2.0)
- **Entschieden:** Core Audio `kAudioProcessPropertyIsRunningInput` je Prozess (PID, Bundle-ID) und
  CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` je Kamera, nur lesend, Beobachter plus
  2-s-Abfrage nur solange das Mikrofon an ist. Kein Ton, kein Bild. App-Name aus dem lokalen Bundle
  (äußerste `.app` im Pfad aus `proc_pidpath`, bereinigt wie Strom-Texte), WebKit → „Webseite“,
  sonst „Unbekannte App“; angezeigt nur per `Text(verbatim:)`, **nie protokolliert**.
- **Gemessen 20.10. am echten Gnotchi (Testkopie, PID 45250):** Kamera keine TCC-Anfrage; Mikrofon
  nur `kTCCServiceMicrophone` mit `preflight=yes` (stille Vorabprüfung, kein Dialog). Keine neue
  Berechtigung, Positivliste G12 unverändert.

### G19 – Kopfhörer-Hinweis: nur Standard-Ausgang beobachten (neu, 2026-10-20, 0.2.0)
- **Entschieden:** Beobachter auf `kAudioHardwarePropertyDefaultOutputDevice`; Hinweis nur beim
  Wechsel auf bzw. von Bluetooth, nicht beim Start, nicht nach eigener Auswahl (2-s-Fenster).
  Kein IOBluetooth (bräuchte die Bluetooth-Freigabe). Gerätenamen bereinigt, nicht protokolliert.

### G20 – Ausgang setzen nur auf Klick, gegen frische Liste (neu, 2026-10-20, 0.2.0)
- **Entschieden:** `kAudioHardwarePropertyDefaultOutputDevice` setzt Gnotchi nur aus dem Menü des
  Ausgabe-Knopfs. Vor dem Setzen wird die Geräteliste neu gelesen; ein inzwischen verschwundenes
  Gerät wird nicht gesetzt (`OutputDevices.canSelect`, Test). Protokoll nur Übertragungsart bzw.
  OSStatus. Keine Automatik, kein Merken „Lieblingsgerät“.

### G21 – Tippis Live-Text: eigener Socket, beidseitig geprüft, nie protokolliert (neu, 2026-10-20, 0.3.0)
- **Warum ein eigener Weg:** Diktattext ist so privat wie das Mikrofon selbst. distnoted (G17) kann
  jeder lokale Prozess mitlesen, deshalb dort nie Text. Leitsatz: Ein Prozess ohne Mikrofon-Freigabe
  kommt über diesen Weg nicht an Gesprochenes.
- **Weg:** Unix-Stream-Socket `~/Library/Application Support/Gnotchi/live.sock` (`LiveTextServer`,
  `LiveTextLink`), läuft mit dem Schalter „Tippi-Aufnahme anzeigen“. Ordner 0700 (angelegt bzw.
  nachgeschärft, muss echter Ordner des Nutzers sein, kein Link), Socket 0600. Eine fremde Datei oder
  ein Link am Pfad wird **nicht** gelöscht – dann bleibt die Funktion aus. Lokal, kein Netz, keine
  Berechtigung (Positivliste G12 unverändert).
- **Gnotchi prüft Tippi** vor dem ersten gelesenen Byte: `LOCAL_PEERTOKEN` → Audit-Token →
  `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)` → `SecCodeCheckValidity` gegen
  `LiveText.tippiRequirement`: **Developer ID** (Zwischenzertifikat `1.2.840.113635.100.6.2.6`),
  Kennung `com.tippi.app`, Team LTKJ6Z2VYB. Nicht nur `anchor apple generic`: Apple-Development-Builds
  tragen `get-task-allow` und ließen sich vom gleichen Nutzer anhängen. Audit-Token statt PID: kein
  Wettlauf mit wiederverwendeten Prozessnummern. Bestanden → Antwort `{"v":1,"ok":true}`, sonst zu.
- **Tippi prüft Gnotchi** genauso (Server-Seite des Sockets, Kennung `dev.mwlr.gnotchi`) und schickt erst
  nach Gnotchis `ok` Text; sonst zeigt Tippi seine eigene Pille. Ein Prozess, der den Pfad vor Gnotchi
  belegt, bekommt also nichts.
- **Schema statt Vertrauen, auch nach der Prüfung:** 4 Byte Länge + JSON ≤ 4 KB, `v` = 1 (Zahl, kein
  Bool), `text` String; sonst Verbindung zu. Steuer-, Format- und Richtungszeichen raus (außer
  Emoji-Verbinder), Leerraum zusammengefasst, höchstens 400 Zeichen behalten, angezeigt das Ende
  (≈ 85 Zeichen, zwei Zeilen), nur `Text(verbatim:)`. Höchstens 4 Stände/s an die Ansicht.
- **Lebensdauer:** Text nur, solange Tippi über distnoted „nimmt auf/wandelt um“ meldet (G17, eigenes
  3-s-Zeitlimit) und die Verbindung offen ist; danach sofort verworfen. Kein eigenes Zeitlimit, weil
  Tippis Vorschau-Takt keine Obergrenze hat (`nextInterval = max(1, Dauer × 2)`). Nie gespeichert,
  nie protokolliert – Protokoll nur „bereit/verbunden/abgelehnt (OSStatus)/getrennt“.
- **Gemessen 20.10.:** Spike beidseitiges `LOCAL_PEERTOKEN` (PIDs korrekt); Anforderung nimmt
  `/Applications/Tippi.app` und `Gnotchi.app` an, lehnt vertauschte Kennung und TextEdit ab (-67050);
  Gegenprobe je Repo: ohne Prüfung wird der Ablehnungs-Test rot; echtes System: ad-hoc-signierter
  Client → „abgelehnt (-67050)“, kein ok; Michaels Diktat mit Live-Vorschau → Text in der Insel,
  Protokoll beider Apps ohne Diktattext.
- **Restrisiko (hingenommen):** Root; Apps mit Bildschirmaufnahme-/Bedienungshilfen-Freigabe sehen
  den Text wie zuvor in Tippis Pille; ein Prozess des gleichen Nutzers kann den Socket löschen und
  die Funktion stören (Ausfall auf Tippis Pille), aber nicht mitlesen.

### G22 – Qotti-Kontingent: nur Zahlen, Schema, nur Anzeige (neu, 2026-10-20, 0.3.0)
- **Weg:** Qotti (`app.qotti.local`, SwiftPM, keine Sandbox, Team LTKJ6Z2VYB) sendet
  `app.qotti.local.kontingent` über distnoted: `v` = 1, je Anbieter `claude…`/`codex…` 5-h-Prozent,
  Zurücksetzung (Unix-Sekunden), Zustand ok/stale/throttled. Bei Änderung + Herzschlag 60 s, und nur,
  wenn ein Developer-ID-signiertes Gnotchi ≥ 0.3.0 läuft und `qottiQuota` nicht aus ist. **Nie** Konto,
  E-Mail, Plan, Fehlertexte (Qotti-Test prüft die Schlüsselmenge).
- **Gnotchi** (`QottiLink`): Schema wie G17 – Zahlen ohne Bool, endlich, auf 0…100 begrenzt, Zeitpunkt
  nur plausibel (−1 Tag … +8 Tage), Zustand aus Positivliste, sonst Anbieter verworfen. Höchstens
  1 Auswertung/s, nach 5 Min. ohne Meldung verworfen. Anzeige nur feste Texte + Zahlen; keine Befehle.
  Werte nie im Protokoll (nur „empfangen/verworfen“).
- **Gemessen 20.10.:** Qotti-Testbuild (Developer ID, gleiche Anforderung wie installiert, kein
  Schlüsselbund-Dialog) → Mithörer sah nur `v`, `*5h`, `*Reset5h`, `*State`; Gnotchi „empfangen“;
  Michael sah die Zeile mit Qottis Werten und beide Warnungen (`tools/fake-qotti.swift warnung`).
- **Restrisiko (hingenommen):** Jeder lokale Prozess kann die Prozente mitlesen und ein Kontingent
  vortäuschen (feste Texte, kurzer Hinweis).

### G23 – Update-Meldung der App-Familie: nur Schema, feste Texte, nur Anzeige (neu, 2026-10-21, 0.4.0)
- **Weg:** distnoted, Name `app.mwlr.familie.update`. Jeder lokale Prozess kann senden und mitlesen (wie
  G17/G22) → nur öffentliche Angaben: `{"v":1, "app":"kalli", "version":"0.11.0", "ready":true}`.
- **Gnotchi** (`FamilyUpdates.parse`, `FamilyUpdateLink`): `v` Zahl 1 (kein Bool), `app` aus der festen
  Positivliste `tippi · kalli · qotti · seam` (Gnotchi selbst nie über diesen Weg), `version` passt auf
  `^[0-9]{1,3}(\.[0-9]{1,3}){1,2}$` (nur ASCII-Ziffern), `ready` echter Wahrheitswert. Alles andere verworfen,
  **bevor** irgendetwas gespeichert wird; unbekannte Schlüssel ignoriert. Je App ein Eintrag (höchstens 4),
  je App höchstens 1 Meldung/s (schnellere verworfen).
- **Anzeige** nur „<Name aus der Positivliste> <geprüfte Version> bereit“, nie Text aus der Meldung.
- **Erledigt-Regel:** `ready:false` entfernt; nicht angezeigt bzw. entfernt, sobald die installierte App
  (Info.plist der App, die LaunchServices zur festen Bundle-ID kennt) mindestens diese Version hat – geprüft bei
  jeder Meldung, bei jedem Start einer Familien-App und stündlich; nach 14 Tagen ohne neue Meldung weg.
- **Gnotchis eigenes Update** kommt aus Sparkle im eigenen Prozess (G11), Version ebenfalls nur in geprüfter Form.
- **Sender** (je App eigenes Release): sendet nur, wenn ein Developer-ID-signiertes Gnotchi ≥ 0.4.0 läuft und
  `familyUpdates` nicht aus ist (wie G22); sendet erneut, wenn Gnotchi startet (Gnotchi speichert keine Meldungen).
- **Restrisiko (hingenommen):** Ein fremder Prozess kann „Kalli 9.9 bereit“ vortäuschen → falsche Anzeige, Klick
  öffnet das echte Kalli (G24). Die installierte Version wird ohne Signaturprüfung gelesen: Eine Attrappe mit hoher
  Versionsnummer kann höchstens eine Anzeige unterdrücken.

### G24 – Klick öffnet nur die echte App (neu, 2026-10-21, 0.4.0)
- **Entschieden:** Kürzel → Bundle-ID **fest im Code** (`FamilyApp.bundleID`, gemessen 21.10. an den installierten
  Apps: `com.tippi.app`, `com.kalli.app`, `app.qotti.local`, `dev.mwlr.seam`, alle Team LTKJ6Z2VYB). Alle Fundorte über
  `NSWorkspace.urlsForApplications(withBundleIdentifier:)`, geöffnet wird der erste mit gültiger **statischer Signaturprüfung** (`SecStaticCode`,
  alle Architekturen, mit Ressourcen) gegen dieselbe Anforderung wie G21: Developer ID + Team + Kennung. Scheitert
  sie → nichts starten, Hinweis „App nicht gefunden“. Prüfung außerhalb des Hauptthreads.
- **Danach** `app.mwlr.familie.update.show` mit `{"v":1,"app":"kalli"}` (1,5 s nach dem Öffnen, damit eine frisch
  gestartete App lauscht). Die App reagiert nur, wenn sie selbst ein Update bereit hat, und zeigt ihr eigenes
  Sparkle-Fenster. Eine Fälschung durch Dritte kann höchstens das echte Update-Fenster öffnen.
- **Gemessen (Test):** Attrappe mit Kennung `com.kalli.app`, ad hoc signiert → abgelehnt; Gegenprobe: nur mit der
  Kennung als Anforderung ginge sie durch; ohne die Prüfung im Code werden zwei Tests rot. Das installierte Kalli
  besteht.
- **Restrisiko (hingenommen):** Zwischen Prüfung und Start könnte ein Prozess mit Nutzerrechten das Bundle
  austauschen. Wer das kann, kann die App ohnehin ersetzen.

### G25 – Medienfilter speichert nur App-Kennungen (neu, 2026-10-21, 0.4.0)
- **Entschieden:** UserDefaults `mediaExcluded`: Liste von Bundle-IDs, nur `[A-Za-z0-9.-]`, je 1…255 Zeichen,
  ohne Doppelte, höchstens 64 – beim Lesen und Schreiben geprüft, Ungültiges fällt weg. Keine Titel, keine
  Zeitpunkte (G14). Die Liste „seit Start gesehene Apps“ (höchstens 64) lebt nur im Speicher.
- **Wirkung:** Wiedergabe einer ausgeschlossenen App wird vor jeder Verarbeitung verworfen (kein Cover-Dekodieren,
  keine Wiedergabeweg-Abfrage).

### G26 – Kallis nächster Termin: eigener Socket, beidseitig geprüft, nie protokolliert (neu, 2026-10-21, 0.5.0)
- **Warum ein eigener Weg:** Termintitel sind privat, distnoted (G13/G17) kann jeder Prozess mitlesen.
  Weg wie G21: Unix-Socket `~/Library/Application Support/Gnotchi/kalli.sock`, Gnotchi ist Server
  (`PeerSocketServer`, seit 0.5.0 allgemein; Tippis Live-Text läuft unverändert darüber), Ordner 0700,
  Socket 0600, fremde Datei am Pfad → Funktion aus. Läuft mit „Termine aus Kalli anzeigen“.
- **Beidseitige Prüfung:** Gnotchi prüft Kalli vor dem ersten Byte über das Audit-Token gegen
  Developer ID + `com.kalli.app` + Team LTKJ6Z2VYB; Kalli prüft Gnotchi genauso und sendet erst nach
  dem `ok` (0,5 s). Kein Rückkanal nach dem `ok` (Klick öffnet Apple Kalender in Gnotchi selbst).
- **Schema:** `v` Zahl 1, `event` null oder `{title, start, color?}`; Titel bereinigt (wie G21), ≤ 120
  Zeichen, nur `Text(verbatim:)`; Beginn außerhalb −1 Tag … +400 Tage → verworfen; Farbe nur `#RRGGBB`;
  alles andere → Verbindung zu. Kalli kürzt den Titel schon auf 200 Zeichen (Review 21.10.).
- **Lebensdauer:** nur Arbeitsspeicher; sichtbar 15 Min. vor bis Beginn, verworfen bei Beginn,
  Trennung, Ausschalten. Protokoll ohne Titel.
- **Wiederverbindung:** Kalli erkennt Gnotchis Start über `NSWorkspace.runningApplications` (KVO).
  `didLaunchApplicationNotification` kommt für Apps ohne Dock-Symbol nicht (gemessen 21.10.: 0×, KVO 1×).
- **Gemessen 21.10.:** beidseitig verbunden; nachgebauter Client → „abgelehnt (OSStatus -67050)“, kein
  `ok`, echte Verbindung blieb; Testtermin in der Insel sichtbar (Michael); Protokoll beider Apps ohne Titel.

### G27 – Spiegel: Kamera nur sichtbar, Bild nur in der Vorschau-Ebene (neu, 2026-10-21, 0.5.0)
- **Berechtigung:** `com.apple.security.device.camera` + `NSCameraUsageDescription`; Freigabe-Dialog erst
  beim Klick auf den Spiegel. G12 ändert sich: App genau Apple Events **und** Kamera.
- **Bild:** `AVCaptureSession` → nur `AVCaptureVideoPreviewLayer`; kein Video-/Foto-Ausgang, kein Puffer
  im eigenen Code, keine Datei, kein Netz. Protokoll nur „an/aus/nicht erlaubt/keine Kamera“.
- **Laufzeit:** Kamera nur, solange der Spiegel groß sichtbar ist (`onDisappear`, Einklappen, anderes
  Symbol, Schalter aus). Review 21.10.: Wurde die Insel während des Freigabe-Dialogs geschlossen, startete
  die Kamera danach trotzdem – behoben (`wanted` auf der Kamera-Warteschlange, `run` prüft es).
- **Kindprozess:** `/usr/bin/perl` (Medien-Adapter) wird Gnotchi zugerechnet und könnte dessen
  Kamera-Freigabe nutzen. Antwort: G2 (Skript und Framework vor jedem Start auf Unversehrtheit geprüft),
  der Adapter hat keinen Kamera-Code. Restrisiko hingenommen.
- **Gemessen 21.10.:** Testkopie mit genau zwei Berechtigungen; Michael: Bild gespiegelt, LED aus nach
  Einklappen (Protokoll an 19:26:49, aus 19:27:06).

### G28 – Hilfsprogramm: einzige Bedienungshilfen-Freigabe, kleinstmöglich (neu, 2026-10-22, 0.6.0)
- **Entschieden:** `Gnotchi Mitteilungen.app` beobachtet **nur** den Prozess `com.apple.notificationcenterui`
  (AXObserver + Abfrage im Sekundentakt). Es schreibt genau zwei Dinge: `AXPosition` von Banner-Fenstern dieses
  Prozesses (verstecken/zurück) und `AXPerformAction` an einem gemeldeten Banner bzw. dessen Anruf-Knopf. Kein
  `AXValue` setzen (kein Tippen), keine Event-Taps, keine künstlichen Eingaben, keine Prozesse, kein AppleScript,
  kein Netz. Maschinell: Lint-Regeln `keine_eingaben_im_helfer` und `kindprozess_nur_im_adapter` (gilt auch hier).
- **Fail-open:** Ein Fenster wird nur versteckt, wenn **alle** seine Banner gerade in Gnotchi zu sehen sind
  (sonst verschwände eine nicht ausgewählte Mitteilung mit). Ohne Banner, bei geöffneter Mitteilungszentrale, beim
  Beenden (auch SIGTERM/SIGINT/SIGHUP) → alles zurück. Ohne Verbindung zu Gnotchi wird nichts versteckt.
- **Lebensdauer:** Gnotchi startet es (nur signaturgeprüft, nur aus dem eigenen Paket) bei eingeschaltetem
  Schalter; es beendet sich, wenn Gnotchi trennt oder 10 s nicht erreichbar ist.
- **Gemessen 22.10.:** eigener verantwortlicher Prozess (G1); Banner-Fenster per `AXPosition` weg und zurück
  (`tools/nc-park.swift`); Gnotchi beendet → Hilfsprogramm „Ende: Gnotchi getrennt“ nach < 1 s.
- **Anrufe:** Apples Anruf-Banner wird in 0.6.0 **nicht** versteckt, solange „Ablehnen aus der Notch“ nicht am
  echten Anruf gemessen ist – sonst ließe sich ein Anruf bei einem Fehler gar nicht mehr wegdrücken.
- **Erweitert 0.9.0 (22.10.):** Ablehnen ist gemessen → Apples Anruf-Banner wird **nur beim Klingeln** versteckt,
  sobald eine Insel den Anruf zeigt. Zurück beim Mitlesen (Abschrift nur bei Apple), im Gespräch (Apples Leiste hat
  Stumm, Ziffernblock …), bei unbekanntem Zustand und 3 s nach der Folgeaktion (fail-open). Während eines Anrufs
  dürfen Banner mit weg, die Gnotchi **früher schon gezeigt** hat (stehengebliebene Erinnerung, Michael „B“) – nie
  solche, die Gnotchi nie gezeigt hat (`NotifyWire.mayHideWindow`, getestet).
- **Zweiter beobachteter Prozess (0.9.0): Dock, nur lesen.** `com.apple.dock`, nur `AXURL` + `AXStatusLabel` von
  `AXApplicationDockItem`; kein Schreiben, keine Aktion. Nur bei eingeschalteten „Ungelesen-Zahlen“ (ab Werk aus) und
  erteilter Freigabe, alle 5 s, ≤ 300 Knoten (G33).

### G29 – Mitteilungs-Weg: beidseitig geprüft, nur ausgewählte Apps, nie protokolliert (neu, 2026-10-22, 0.6.0)
- **Weg:** Unix-Socket `~/Library/Application Support/Gnotchi/notify.sock`, Gnotchi ist Server (derselbe
  `PeerSocketServer` wie G21/G26, hier ungedrosselt: jede Nachricht zählt, höchstens 10/s, Rahmen ≤ 8 KB).
- **Hilfsprogramm prüft Gnotchi** vor dem ersten Inhalt (Audit-Token, Developer ID, `dev.mwlr.gnotchi`, Team
  LTKJ6Z2VYB, `ok` binnen 0,5 s). Wichtigste Prüfung: Ein falscher „Gnotchi“ bekäme sonst alle Mitteilungen.
  **Gegenprobe 22.10.:** Python-Server am Pfad, sendet `ok` → 21 Versuche „kein echtes Gnotchi (OSStatus -67050)“,
  **0 Bytes** empfangen, Hilfsprogramm nach 10 s beendet.
- **Gnotchi prüft das Hilfsprogramm** genauso (`dev.mwlr.gnotchi.mitteilungen`). Test
  `testNotifyRequirementRejectsOtherProcess`: Testlauf ist nicht das Hilfsprogramm → kein `ok`, nichts angezeigt.
- **Filter im Hilfsprogramm:** Inhalte nicht ausgewählter Apps verlassen es nie; vor dem ersten Filter von Gnotchi
  wird nichts gemeldet. Zuordnung App-Name → Kennung nur eindeutig (laufende Apps, sonst installierte nach
  angezeigtem Namen); zwei Apps gleichen Namens → keine Kennung → nicht gezeigt. Gemessen 22.10.: leere Liste →
  Apples Banner blieb auf (0,0), Gnotchi klein.
- **Schema statt Vertrauen, beide Seiten** (`NotifyWire`, dieselbe Datei in beiden Zielen): unbekannte Schlüssel →
  ungültig, `v` Zahl 1, Kennungen nur `[A-Za-z0-9_-]` ≤ 64, Bundle-IDs `[A-Za-z0-9.-]`, Texte bereinigt wie G21
  und gekürzt (App 40, Titel/Untertitel 120, Text 500), ≤ 6 Aktionen à ≤ 40 Zeichen, Eingabe-Aktionen
  („Antworten“, „Mit Nachricht ablehnen“, „Details einblenden“, Live-Voicemail) werden auf beiden Seiten entfernt.
  Anzeige nur `Text(verbatim:)`. Warteschlange ≤ 20.
- **Nur im Arbeitsspeicher**, nie gespeichert, nie protokolliert. Protokoll: verbunden/abgelehnt (OSStatus)/
  Beobachtung/„Gemeldet: note|call, n Knöpfe, nach x ms“/„Aktion „<Beschriftung>“ ausgeführt (AXError)“. Die
  Beschriftung ist ein macOS-Text („Annehmen“), kein Inhalt. Gemessen 22.10.: Protokoll nach Testmitteilung
  0 Treffer auf Titel/Text/App. Die App-Liste speichert nur Kennungen (wie G25).

### G30 – Knöpfe und Anrufe: nur echter Klick, nur gemeldete Aktion, nur dieses Banner (neu, 2026-10-22, 0.6.0)
- Gnotchi schickt `act` nur aus einem SwiftUI-Knopf/Tipp in der Insel (G13), nie zeitgesteuert. Anruf-Knöpfe erst
  0,5 s nach dem Erscheinen klickbar; nach einem Klick grau, bis macOS neue Knöpfe meldet.
- Das Hilfsprogramm führt `act` nur an einem **gerade sichtbaren, gemeldeten** Banner aus, und nur eine Aktion, die
  macOS **jetzt** dafür meldet; Anrufe nur Annehmen/Ablehnen/Beenden (de/en) an einem frisch gesuchten `AXButton`.
- **Gemessen 22.10. (iPhone-Anruf über Continuity):** Banner `FACETIME_NOTIFICATION` ist in der ersten Zehntelsekunde
  leer (Knöpfe nach 245–1496 ms) → Hilfsprogramm liest bis 3 s alle 0,2 s nach. Nach „Annehmen“ wird dasselbe Banner
  nach ~5 s zur Gesprächsleiste (Beenden, Weitere, Ziffernblock, Stumm, FaceTime-Video); angeboten wird nur
  Beenden. Michael 11:09: „Annehmen“ und „Beenden“ aus der Notch wirken (Protokoll AXError 0). **Nicht gemessen:**
  Ablehnen aus der Notch, FaceTime-Audio/-Video.
- **Erweitert 0.9.0 – Folgeaktion nur als Teil eines Klicks.** Gemessen 22.10.: „Ablehnen“ schickt den Anrufer bei
  eingeschalteter Live-Voicemail auf die Mailbox mit Mitlesen; das Banner bleibt mit „Live-Voicemail stoppen“ +
  „Annehmen“. „Stoppen“ beendet nur das Mitlesen. Rot = `act` „Ablehnen“ mit `then:"stopVoicemail"`; das Schema lässt
  `then` nur mit Ablehnen am Anruf zu. Das Hilfsprogramm drückt „Live-Voicemail stoppen“ **einmal**, nur am selben
  Banner, nur wenn „Ablehnen“ dort verschwunden ist, nur binnen 2 s (`NotifyWire.followUp`, getestet, Gegenprobe ohne
  Bannerbindung rot). Schlimmster Fehlgriff: Mitlesen endet – kein Annehmen, kein Mikrofon. Sichttest 15:13/15:56:
  Folgeaktion 0,12 s nach Ablehnen, Apples Fenster blieb versteckt.

### G33 – Ungelesen-Zahlen: Zahl, nicht Inhalt (neu, 2026-10-22, 0.9.0)
- **Quelle:** Dock-Abzeichen (G28 erweitert). Abzeichen-Texte setzt jede App selbst (`NSDockTile.badgeLabel`,
  beliebig) → **unvertraut**: nur ASCII-Ziffern zählen (höchstens 9999), jedes andere Abzeichen = 1, Text verlässt das
  Hilfsprogramm nie (`NotifyWire.badgeCount`, getestet).
- **Weg:** `{"v":1,"badges":[{"bundle","count"}]}`, Schema streng (ganze Zahl 1…9999, kein Wahrheitswert, keine
  Doppelten, ≤ 100, keine Zusatzschlüssel). Filter im Hilfsprogramm **und** in Gnotchi (nur ausgewählte Apps – Review
  22.10.: sonst könnte ein falsches Hilfsprogramm per Klick beliebige installierte Apps öffnen lassen).
- **Klick** öffnet die installierte App mit genau dieser Kennung über LaunchServices – wie ein Klick aufs Dock-Symbol.
- **Nie gespeichert, nie protokolliert** (Protokoll nur „Ungelesen: n App(s)“).

### G31 – Wetter: zwei feste Adressen, nur der gewählte Ort geht raus (neu, 2026-10-22, 0.7.0)
- **Ziele:** nur `https://api.open-meteo.com/v1/forecast` und `https://geocoding-api.open-meteo.com/v1/search`,
  gebaut mit `URLComponents`; Nutzereingabe nur als Query-Wert `name` (bereinigt, ≤ 100 Zeichen), Koordinaten nur
  als Zahlen. Keine Weiterleitungen (Delegate gibt `nil`), Host der Antwort muss der angefragte sein. Test
  `testSearchURLOnlyQueryValueEncodedAndCapped`: „…?x=1&host=evil.example“ bleibt Wert, Host unverändert.
- **Sitzung:** `ephemeral`, keine Cookies, kein Cache, 10 s/15 s Zeitlimit, User-Agent „Gnotchi/<Version>“, kein
  Schlüssel, keine Kennung.
- **Antwort = Fremddaten:** Status 200, ≤ 64 KB **beim Lesen** abgebrochen, Schema streng (Zahlen endlich und im
  Bereich, Arrays gleich lang ≤ 200, Zeiten lesbar – auch Sonnenauf-/-untergang, Fund im Test 22.10.; unbekannter
  WMO-Code → verworfen). Ortsnamen bereinigt wie G21, ≤ 60 Zeichen, `Text(verbatim:)`.
- **Datensparsamkeit:** nur der in den Einstellungen gewählte Ort, Koordinaten auf 2 Stellen gerundet; keine
  Standort-Berechtigung. Ortssuche nur auf Klick. Open-Meteo protokolliert IP und Koordinaten bis 90 Tage
  (Bedingungen, 22.10.) – Hinweis in Einstellungen, Hilfe, README.
- **Gespeichert:** Ort (Name, Region, Land, gerundete Koordinaten), Einheit; beim Lesen geprüft
  (`Preferences.validPlace`). Vorhersage nur im Arbeitsspeicher. Protokoll: „Wetter aktualisiert“ /
  „Wetter-Fehler (status(n)|network|invalid|…)“ – kein Ort, keine Werte.
- **Last/Lizenz:** ≤ 1 Abruf je 5 Min, normal 30 Min (Bedingung < 10 000/Tag); nicht-kommerziell (Gnotchi kostenlos,
  quelloffen); Quellenangabe CC BY 4.0 in der Insel, Hilfe, README, `THIRD-PARTY-LICENSES.md`.
- **Berechtigungen:** keine neue (keine Sandbox). **Gemessen 22.10.:** Parser gegen echte Antworten (°C, °F,
  Ortssuche mit 5 Treffern, kein Treffer = Schlüssel `results` fehlt); Testkopie „Wetter aktualisiert“ Sekunden
  nach dem Start, danach keine offene Verbindung.

### G32 – Dateiablage: Verweise, nichts ausführen, ZIP im Prozess (neu, 2026-10-22, 0.8.0)
- **Ziehen erkennen ohne Beobachter (G1 bleibt):** alle 0,1 s `NSEvent.pressedMouseButtons` und Zähler/Typen der
  Zieh-Zwischenablage, Inhalte erst beim Loslassen auf der Insel. Gemessen 22.10. (`tools/drag-probe.swift`): drei
  Finder-Ziehvorgänge → Zähler +1 ~200 ms nach dem Drücken, Typ `public.file-url`; ~40 Klicks → unverändert.
- **Nur Datei-URLs**, gespeichert als Lesezeichen in `ablage.json` (Ordner 0700, Datei 0600, ≤ 50, Schema beim Lesen).
  Nichts wird geöffnet/ausgeführt (kein `NSWorkspace.open`), Entfernen/Leeren löscht nie eine Datei. Rausziehen über
  eine AppKit-Ziehquelle, die nur die URL übergibt; „angekommen“ (Operation ≠ keine) → aus der Ablage.
- **ZIP ohne Kindprozess (G3 bleibt):** libarchive (SDK `libarchive.tbd`, `-larchive`, eigene Deklarationen), nur
  relative Pfade, Links übersprungen und beim Öffnen per `O_NOFOLLOW` abgelehnt (Review 22.10.), ≤ 10 000 Dateien /
  4 GB, Ziel `~/Downloads`, nie überschreiben, halbes ZIP wird gelöscht, Quarantäne-Merkmal übernommen. AES-256 mit
  Passwort (≥ 8 Zeichen, doppelt); Passwort nur im Speicher, nie Argument/Protokoll/Datei. Gemessen 22.10.: richtiges
  Passwort entpackt, falsches nicht; macOS `ditto`/`unzip` öffnen AES-ZIPs nicht (Hinweis im Dialog).
- **Protokoll:** nur Zahlen. **Berechtigungen:** keine neue.
- **Restrisiko (hingenommen):** Eine App kann beim Ziehen eine präparierte Datei (z. B. `.app`) anbieten – sie liegt
  dann als Verweis in der Ablage und wird nur weitergereicht, nie gestartet.
- **Ergänzung 0.9.1 (23.10., specs/2026-10-23-gnotchi-0.9.1-fotos-ablage.md): Dateiversprechen → eigene Kopie.**
  Gemessen 23.10.: Fotos bietet beim Ziehen Versprechen + `public.file-url`, der Verweis zeigt aber auf eine Vorschau
  in der Mediathek (`resources/derivatives/…`); Gnotchi verwarf sie still („0 abgelegt“). Jetzt: Element mit
  Versprechen → `NSFilePromiseReceiver` schreibt nach `Ablage-Kopien/<UUID>/` (je Versprechen frischer Ordner 0700 über
  `prepareDirectory`), angenommen nur, wenn das Ergebnis **direkt** in diesem Ordner liegt, kein Link ist und uns
  gehört. Höchstens so viele Versprechen wie Plätze frei, Zeitlimit 120 s. **Löschen** nur UUID-Ordner direkt im
  Kopien-Ordner, auf die kein Eintrag mehr zeigt (Prüfung zum Löschzeitpunkt am aufgelösten Lesezeichen → eine
  rausgeschobene Kopie liegt draußen und bleibt); beim Start und nach Entfernen/Leeren. Verweise (Finder) unverändert:
  nie gelöscht. Keine neue Berechtigung, Protokoll nur Zahlen. Größe ungedeckelt (eigene App des Nutzers, Videos) –
  hingenommen. Sichttest 23.10.: Foto → „1 abgelegt“ (Original 5 MB statt Vorschau), Entfernen → „1 Kopien gelöscht“,
  Ordner leer; erster Lauf stürzte ab (Rückruf erbte die Hauptthread-Bindung, Swift-6-Laufzeitprüfung) → Rückruf
  außerhalb gebaut, Test vom Hintergrund aus.
  **Review 0.9.1 (`rafter-code-review`, 23.10.):** kein Weg gefunden, außerhalb von `Ablage-Kopien/` oder die Datei
  hinter einem Verweis zu löschen. Behoben: (1, mittel) Rausziehen löschte die Kopie sofort, auch wenn die Ziel-App
  (Browser-Upload, Mail) sie erst später liest → Eintrag weg, Kopie erst beim nächsten Start; (2) Aufräumen nur, wenn
  Gnotchi- und Kopien-Ordner echte eigene Ordner sind (`lstat`, kein Link); (3) `ablage.json` unvollständig gelesen →
  nichts aufräumen; (5) Aufräumen beim Start auch bei ausgeschalteter Ablage. Gegenprobe: ohne (2)/(3) zwei Tests rot.
  Hingenommen: (4) schreibt eine App nach dem 120-s-Zeitlimit noch, liegt die Datei bis zum nächsten Aufräumen.

### G34 – Claude-Hook-Weg: nur Status und gekürzter Text, beidseitig geprüft (neu, 2026-10-22, 0.9.0)
- **Hook-Programm „Gnotchi Claude“** (`dev.mwlr.gnotchi.claude`, `Contents/Helpers/`, Developer ID, keine
  Berechtigungen) wird von Claude Code je Ereignis gestartet (`async: true`), liest stdin (≤ 4 MB), prüft Gnotchi über
  das Audit-Token **bevor** es sendet (Claudes Antwort kann Vault-Inhalte enthalten), endet. Gnotchi prüft den
  Absender genauso (`claude.sock`). Gibt **nie** etwas auf stdout aus → nie eine Entscheidung an Claude Code.
- **Datensparsam:** Sitzungs-Kennung, Ereignis, Projektname (letzter Pfadteil), App-Kennung + PID, Werkzeugname,
  Kurzfassung (Bash-Befehl ≤ 120 Zeichen, sonst nur Dateiname), Antwort ≤ 300 Zeichen. Nie `transcript_path`, Prompt,
  Dateiinhalte (`ClaudeWire`, getestet). Protokoll nur Ereignis-Art, App-Kennung, Zahl der Sitzungen.
- **Klick** holt nur das laufende Programm mit genau dieser PID **und** Kennung über LaunchServices nach vorn
  (`activate()` ignoriert macOS, wenn Gnotchi nicht vorn ist – Sichttest 22.10.).
- **Hingenommen:** Der Socket nimmt eine Verbindung zur Zeit; gleichzeitige Ereignisse mehrerer Sitzungen können
  selten eines verlieren, der 30-Minuten-Ablauf räumt auf.

### G35 – `~/.claude/settings.json`: nur eigene Einträge, byte-genau oder gar nicht (neu, 2026-10-22, 0.9.0)
- Reihenfolgetreuer Leser/Schreiber (Format `json.dumps(indent=2, ensure_ascii=False)`); geschrieben wird nur, wenn
  Lesen + Zurückschreiben das Original **byte-gleich** ergibt (Gegenprobe ohne diese Sperre → Test rot). Gemessen an
  Michaels Datei 22.10.: Rundlauf byte-gleich, Eintragen + Entfernen = Original, zweite Implementierung (Python)
  bestätigt seine 20 Hooks unverändert.
- Nur Einträge mit `Gnotchi Claude.app` im Befehl; Pfad in `'…'`, ein `'` im Pfad wird verweigert.
- Sicherung `settings.json.gnotchi-backup` (0600), dann temporäre Datei **mit den Zielrechten** + `rename` (Review:
  `.atomic` legte sie kurz mit Standardrechten an); unmittelbar davor erneut gelesen – geändert → nichts schreiben
  (Review: sonst ginge eine gleichzeitige Änderung von Claude Code verloren). Link, > 1 MB, kein JSON → nichts.
- Schalter aus entfernt die Einträge; Start mit „aus“ entfernt übrig gebliebene (gemessen 22.10.: 5 → 0, Datei wieder
  byte-gleich). Beenden von Gnotchi lässt sie stehen (Hook endet dann still).
- **Prüfung 0.9.0 (22.10.):** `rafter-code-review` beider Stufen (Rest Mitteilungen: 3 Funde, Code & KI: 2 Funde,
  alle behoben); `rafter run` Scan `86131b95` auf `b35371d`: keine Befunde.

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
| **E** | Perl als Kind | fremder Code mit Gnotchis Freigaben | G2, G3. **Neu bewertet:** Ohne Bedienungshilfen (G1) schrumpft der Schaden auf das, was Gnotchi selbst darf – Apple Events an Spotify/Musik, sofern der Nutzer sie erteilt hat, und Now-Playing lesen, was der Adapter ohnehin tut. Er erbt – gemessen 18.10. (G2, Sichttest) |
| **E** | Gnotchi → Spotify/Musik | AppleScript-Einschleusung | G7 |
| **E** | andere Programme → Gnotchi | Gnotchi als Werkzeug missbrauchen | G13 (Meldungen nur zur Anzeige) |
| **S** | lokaler Prozess → Gnotchi (8) | vorgetäuschte Tippi-Aufnahme | G17: feste Texte, hingenommen |
| **T** | lokaler Prozess → Gnotchi (8) | kaputte/übergroße `userInfo` | G17: Schema, Begrenzung |
| **D** | lokaler Prozess → Gnotchi (8) | Nachrichtenflut, hängende Anzeige | G17: 30 Hz, 3-s-Zeitlimit |
| **I** | Gnotchi/Tippi → distnoted (8) | „diktiert gerade“ mitlesbar | G17: nur Zustand + Pegel, hingenommen |
| **I** | Gnotchi → Protokoll (9) | App-Namen der Mikrofon-Nutzer, Gerätenamen | G18, G19: nie protokolliert |
| **S** | lokaler Prozess → Tippi (6a) | Tippis Pille ausblenden | G17: Signaturprüfung; Schreiben in die Einstellung hingenommen (macOS-Punkt bleibt) |
| **T** | Gnotchi → Core Audio (10) | Ausgang auf falsches/verschwundenes Gerät | G20 |
| **S** | lokaler Prozess → Gnotchi (12) | vorgetäuschtes Kontingent | G22: feste Texte, hingenommen |
| **I** | Qotti → distnoted (12) | Prozente mitlesbar | G22: nur Zahlen, nur bei laufendem Gnotchi, hingenommen |
| **S** | lokaler Prozess → Tippi (11) | belegt den Socket-Pfad, gibt sich als Gnotchi aus, will Diktattext | G21: Tippi prüft den Server (Developer ID), Text erst nach `ok` |
| **S** | lokaler Prozess → Gnotchi (11) | schiebt Text in die Notch (Phishing) | G21: Gnotchi prüft den Client, sonst zu |
| **T** | lokaler Prozess → Gnotchi (11) | kaputte/übergroße Rahmen, Steuer-/Richtungszeichen | G21: Rahmen ≤ 4 KB, Schema, Bereinigung |
| **I** | Gnotchi/Tippi → Protokoll (11) | Diktattext im Log | G21: nie protokolliert |
| **D** | lokaler Prozess → Gnotchi (11) | fremde Datei am Pfad, Socket gelöscht, Flut | G21: Funktion aus bzw. Rückfall auf Tippis Pille, 4/s |
| **S** | lokaler Prozess → Gnotchi (13) | vorgetäuschtes Update einer Familien-App | G23: feste Texte, Positivliste; Klick öffnet nur die echte App (G24) |
| **T** | lokaler Prozess → Gnotchi (13) | überlange Version, Steuer-/Richtungszeichen, fremde App | G23: Schema vor jeder Verarbeitung, nur geprüfte Version angezeigt |
| **I** | Familien-App → distnoted (13) | installierte Apps und Versionen mitlesbar | G23: öffentliche Angaben, hingenommen (wie G22) |
| **D** | lokaler Prozess → Gnotchi (13) | Meldungsflut | G23: Schema-Abbruch, 1/s je App, höchstens 4 Einträge, Takt 4 s fest |
| **E** | Gnotchi → andere App (13a) | Klick startet eine Attrappe gleicher Kennung | G24: Signaturprüfung vor dem Öffnen |
| **S** | lokaler Prozess → Hilfsprogramm (14a) | gibt sich als Gnotchi aus, liest alle Mitteilungen | G29: Hilfsprogramm prüft den Server vor dem ersten Inhalt (Gegenprobe 22.10.) |
| **S** | lokaler Prozess → Gnotchi (14a) | falscher Anruf/Phishing-Text in der Notch | G29: Gnotchi prüft den Client |
| **S** | fremde App (14) | nennt sich „WhatsApp“, erscheint mit dessen Symbol | G29: nur eindeutige Zuordnung; Rest hingenommen (Apples Banner zeigt dasselbe) |
| **T** | lokaler Prozess → Hilfsprogramm (14a) | beliebige Aktion auslösen | G30: nur geprüfte Gegenseite, nur gemeldete Aktion am sichtbaren Banner |
| **I** | Hilfsprogramm/Gnotchi → Protokoll (14) | Mitteilungstexte im Log | G29: nie protokolliert |
| **I** | Hilfsprogramm → Gnotchi (14a) | Inhalte nicht ausgewählter Apps | G29: Filter im Hilfsprogramm |
| **D** | Mitteilungszentrale → Hilfsprogramm (14) | Flut, Gnotchi hängt → Mitteilungen weg | G28/G29: verstecken erst nach `shown`, 10/s, ≤ 20, alles zurück beim Beenden |
| **E** | Hilfsprogramm (14) | Bedienungshilfen als Hebel | G28: nur Mitteilungszentrale, nur Position + Aktion, keine Eingaben/Prozesse/Netz |
| **E** | Gnotchi/Perl (14) | erben die Freigabe | G1/G28: eigenes Paket, eigener verantwortlicher Prozess (gemessen) |
| **T** | Netz → Gnotchi (15a) | Riesen-JSON, NaN, Steuerzeichen im Ortsnamen | G31: 64 KB beim Lesen, Schema, Bereiche, Bereinigung |
| **I** | Gnotchi → Open-Meteo (15) | Ort und IP beim Anbieter | G31: nur gewählter Ort, gerundet, ab Werk aus, Hinweis |
| **S** | App → Ablage (16) | präparierte Datei/`.app` | G32: nichts wird geöffnet, nur weitergereicht |
| **T** | Ablage → ZIP (16b) | Link/`..` im ZIP, Austausch gegen Link | G32: relative Pfade, Links übersprungen, `O_NOFOLLOW` |
| **I** | Ablage → Platte/Protokoll | Dateinamen, Passwort | G32: `ablage.json` 0600, Protokoll nur Zahlen, Passwort nie gespeichert |
| **E** | Eingabe → Anfrage (15b) | Ortsname als URL/Host | G31: nur Query-Wert, feste Hosts, keine Weiterleitungen |

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

## Ausstiegskriterien 0.5.0 (Termine, Timer, Spiegel, große Insel)

- [x] Tests: 420 (Schema G26, Anzeigefenster, Rotation, Spiegel-Zustand, Timer/Alarm/Töne, Band, Größen),
      Gegenprobe Server lehnt fremde Kennung ab
- [x] Echtes System: G26 und G27 wie oben gemessen; Timer-Alarm, Stecknadel, Band (Michael)
- [x] `rafter-code-review` 21.10. (CWE Top 25, beide Diffs Gnotchi/Kalli): keine Shell, nur feste URLs/Pfade,
      Schema-Prüfung, keine Titel im Protokoll; zwei Funde behoben (Kamera nach Freigabe-Dialog, lange Titel)
- [x] `rafter run` 21.10. am gepushten Stand `9d185cb`: Scan `0eaad162`, keine Befunde (Kalli `87c8493`: Scan
      `fee0de22`, keine Befunde)
- [x] Positivliste `release.sh` mit `device.camera` am exportierten Build; am heruntergeladenen 0.5.0 (Build 106)
      gemessen: genau `automation.apple-events` + `device.camera`, `Notarized Developer ID`

## Ausstiegskriterien 0.4.0 (Live-Aktivitäten)

Spezifikation: `specs/2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md`.

- [x] Tests 21.10.: Schema G23 (gültig/ungültig, Bool statt Zahl, fremde App, Versionsform), Erledigt-Regel,
      Drossel je App, Rotationsfolge + Pause beim Überfahren, Trackwechsel nur bei anderem Titel, Medienfilter
      (G25), G24 (Zuordnung fest, ad-hoc-signierte Attrappe abgelehnt, Gegenprobe ohne Prüfung rot, echtes Kalli
      besteht). 365 Tests grün.
- [x] Sichttest 21.10. Mac mini (zwei Bildschirme ohne Notch, Testkopie Developer ID): Meldung → Pille auf beiden
      Bildschirmen, Protokoll „Update gemeldet: kalli“; 6 kaputte Meldungen (`fake-update kaputt`) → nichts;
      `ready:false` → weg; „Kalli 0.10.0“ bei installierter 0.10.0 → nicht angezeigt. Klick (echtes CGEvent, Helium
      vorn) auf „Öffnen“ in der großen Insel → „kalli geöffnet“, Kalli aktiv, 1,5 s später `…update.show`
      `{"v":1,"app":"kalli"}` beim Lauscher; Klick auf die kleine Insel nach 0,3 s Verweilen ebenso. Medienfilter per
      Bedienungshilfen umgeschaltet → `mediaExcluded = ("com.apple.Safari")`, zurück → leer.
- [x] Sichttest Michael 21.10. 14:05 (Mac mini, Pille): Rotation Musik ↔ Kopfhörer ↔ Update, Pause beim Überfahren, große Insel mit Update-Zeile, Trackwechsel breit, Pause ohne Aufblitzen – „Alles getestet und funktioniert“
- [ ] Sichttest mit Notch (MacBook)
- [x] `rafter-code-review` 21.10. (CWE-Top-25, lokale IPC + App-Start) für `3bd4a5b..ebf2cb6`: **kein kritischer/
      hoher Fund.** App-Start nur aus Klick (`IslandView` → `IslandController` → `AppModel.openUpdate`), nie aus einer
      Meldung (G13); aus der Meldung fließen nur Positivlisten-Kürzel und geprüfte Version weiter
      (`FamilyUpdates.parse`); Protokoll nur feste Kürzel; Berechtigungen, Info.plist, Abhängigkeiten unverändert;
      `rafter secrets .` nichts. **Niedrig, behoben:** LaunchServices' bevorzugter Fundort konnte eine Attrappe sein →
      Klick blockiert („App nicht gefunden“) statt das echte Kalli zu öffnen; jetzt alle Fundorte, der erste
      signaturgültige (Test). Hingenommen: kein Widerrufs-Check (wie G21), Rennen Prüfung/Start (G24).
- [x] `rafter run` 21.10. auf `4bd3555`: Scan `603c9415`, keine Befunde.
- [ ] Positivliste der Berechtigungen unverändert (`entitlement-gate.sh` beim Release; im Diff unverändert)

## Ausstiegskriterien 0.3.0 (Live-Text)

Liste und Stand: `specs/2026-10-20-gnotchi-0.3.0-live-text.md`. Erfüllt 20.10.: Tests + Gegenproben,
echtes System (fremder Client abgelehnt), Protokoll ohne Diktattext, Sichttest Mac mini.

- [ ] Sichttest mit Notch (MacBook) und über Vollbild
- [x] `rafter-code-review` 21.10. (CWE-Top-25-Liste, lokaler IPC) für Gnotchi `v0.2.0..HEAD`, Tippi
      `64b2cd9^..ecf8613`, Qotti `7c39ede..fd1f316`: **kein kritischer/hoher Fund.** G21: Peer-Prüfung per
      Audit-Token vor dem ersten Byte auf beiden Seiten (`LiveTextServer.checkPeer`, Tippi
      `GnotchiLiveLink.serverPasses`), Developer-ID + Team + Kennung; abgelehnter Client verdrängt die
      bestehende Verbindung nicht (Prüfung vor `closeClient`); Ordner 0700/Socket 0600, `lstat` statt
      Link-Folgen; Rahmen ≤ 4 KB, Länge 0/zu groß → Trennung; Text nur `Text(verbatim:)`. G22: Schema mit
      Positivliste, Zahlen begrenzt (0…100, Reset-Fenster), Qotti sendet nur endliche Werte
      (`Usage.swift` `init?`). Bekannt und hingenommen (niedrig, nur lokal mit Nutzerrechten): Fremdprozess
      kann Qotti-Hinweise vortäuschen (wie G17) und den Socket mit Verbindungen fluten (Prüfung kostet je
      Verbindung, Tippi fällt dann auf die eigene Pille zurück); Qottis Gnotchi-Prüfung läuft über die PID
      (nur Sendesperre für ohnehin öffentliche Zahlen). `rafter secrets .`: Gnotchi/Qotti nichts, Tippi nur
      Testdateien fremder Pakete in ungetrackten `build*/`-Ordnern.
- [x] `rafter run` nur Gnotchi + Tippi (Qotti ist privat, geht nicht an Rafter – Michael 10.10.): Gnotchi 21.10.
      Scan `ad9c49ba`, keine Befunde; Tippi 21.10. am gepushten Stand `ecf8613` (Code von 2.30.0), Scan `1c6a5bd3`,
      kein Fund im App-Code (6 Hinweise nur in `scripts/autocomplete-messung/`, nicht ausgeliefert).
- [x] **Ressourcenfund 21.10. behoben (kein Sicherheitsfund):** Testkopie nach 15 Std. 120 % CPU, 800 MB,
      ohne Menüleisten-Symbol. Ursache (`/diagnose`, Messschleife `tools/listener-probe.swift`): `PrivacyMonitor.
      devicesChanged` meldete die System-Beobachter („Geräteliste geändert“, Audio + Kamera) im eigenen Rückruf ab und
      neu an; Core Audio rief die alten trotz `noErr` weiter auf → Meldungen je Geräteänderung ×4 (3, 12, 48, 192, 768).
      Widerlegt: Abmelden scheitert (200/200 ok); nur verschieben reicht nicht (weiter +6 je Runde). Fix: System-
      Beobachter nur in `start()`/`stop()`, je Gerät verschoben + gebündelt tauschen. Regressionstest
      `PrivacyMonitorListenerTests` (echte Geräteänderung über Aggregat-Gerät): vorher 1023, nachher ≤ 30.
      Gegenprobe echte App: alt nach 5 Änderungen 89 % CPU/292 MB, neu nach 10 Änderungen 0 Stichproben in
      Beobachterlisten. **Betrifft auch die veröffentlichte 0.2.0.** Kamera-Seite nur über denselben Code abgedeckt
      (keine CMIO-Geräte im Test erzeugbar).

## Ausstiegskriterien 0.2.1 (Hotfix, veröffentlicht 21.10. vom Zweig `release/0.2.1`)

- [x] Nur der `PrivacyMonitor`-Fix aus `d184f3c` (Ressourcenfund, siehe 0.3.0), Regressionstest, Messwerkzeug.
- [x] `rafter run` am `main` mit demselben Fix: Scan `ad9c49ba`, keine Befunde.
- [x] Veröffentlicht mit `HOTFIX=1 make release` (neu in `release.sh`), Appcast danach von Hand auf `main`.

## Ausstiegskriterien 0.2.0

- [x] Sicherheitsentwurf (rafter-secure-design) vor dem Code: `specs/2026-10-20-gnotchi-0.2.0.md`
- [x] Tests G17 (Schema, Begrenzung, Zeitlimit-Logik), G18 (Namen, Pfad), G19 (Hinweis-Regeln,
      eigenes Umschalten), G20 (nur gelistete Geräte) grün
- [x] TCC am echten Gnotchi gemessen (G18): keine Kamera-Anfrage, Mikrofon nur Vorabprüfung
- [x] Tippi-Weg mit `tools/fake-tippi.swift` am echten Gnotchi gemessen (G17)
- [x] Sichttest Michael 20.10. (Mac mini, Testkopie Build 58): Kamera (FaceTime-Vorschau, nur grün –
      richtig, kein Ton), Mikrofon (orange beim Tippi-Diktat), kein Berechtigungsdialog, Ausgabe-Menü
      wechselt den Ton, Kopfhörer-Hinweis, echtes Tippi-Diktat (Testbuild `64b2cd9`, Live-Vorschau aus):
      Tippis Pille weg, Insel zeigt Aufnahme, Ende per `idle`. Mit Live-Vorschau bleibt Tippis Pille (gewollt)
- [x] Aufnahme über eine App im Vollbild – 20.10., 16:35, am veröffentlichten 0.2.0: Obsidian im
      Vollbild (Ebene 0, 3440×1440, keine Menüleiste), Gnotchi-Pille Ebene 27 eingeblendet, Michael sah
      sie. Erst nach dem Release gemessen → Aussage stand nicht im 0.2.0-CHANGELOG, README/HILFE ergänzt.
      Messfalle: Seam hält ein bildschirmgroßes Fenster auf Ebene 0 – nicht als Vollbild zählen
- [x] `rafter-code-review` 20.10. gegen G13, G17–G20 am Diff `v0.1.0..HEAD`: kein kritischer/hoher Fund.
      Fremde Namen nur `Text(verbatim:)`, keine neuen Prozesse/URLs/Skripte, Protokoll nur Statuscodes,
      Ausgang nur aus frischer Geräteliste. Bekannt (G17): jeder lokale Prozess kann eine Aufnahme-Anzeige
      vortäuschen – feste Texte, 3 s Zeitlimit. `rafter secrets .`: nichts gefunden
- [x] `rafter run` am 0.2.0-Stand – 20.10. nicht gelaufen: Kontingent Schnell-Scans erschöpft (16/16),
      Plus nicht im Tarif (0/0). Michael: ohne Scan veröffentlichen, Scan nachholen (Vault-Task). Nachgeholt
      21.10. am `main` (enthält den 0.2.0-Code): Scan `ad9c49ba`, keine Befunde.
- [ ] Positivliste der Berechtigungen am ausgelieferten 0.2.0 unverändert (`release.sh`)

## Ausstiegskriterien vor dem ersten Release

- [x] Lint-Regeln für G1 und G3, Gegenprobe 18.10.: beide schlagen an
- [x] Tests für G2, G3, G4, G6, G9 (`GnotchiTests/`, aus Seam übernommen) grün
- [x] Berechtigungs-Gate in `release.sh` (G12), Gegenprobe 18.10. an ad hoc signierter Kopie
- [x] G5, G7, G10 umgesetzt (Plan Aufgaben 10, 11, 11a), am Code geprüft 18.10.: Inhalte nur
      `Text(verbatim:)`, kein `AttributedString(markdown:)`; Rückfall `AppleScriptSource.swift`;
      Panel `.nonactivatingPanel` + `ignoresMouseEvents` im unsichtbaren Zustand
- [x] Sichttest: Erbt der Perl-Prozess Gnotchis Freigaben? Mit Gnotchi selbst gemessen, nicht aus
      dem Terminal (G2) – 18.10. an v0.1.0: **ja** (verantwortlicher Prozess = Gnotchi, Gegenprobe
      Shell-Perl = Obsidian), siehe G2
- [x] `codesign -d --entitlements - --xml` am signierten Build: App nur Apple Events, eingebetteter
      Code ohne – gemessen 18.10. am heruntergeladenen v0.1.0-ZIP (Build 45): App nur
      `automation.apple-events`; Test-Programm und Sparkle-Autoupdate tragen nur den von Xcode
      eingesetzten `com.apple.application-identifier`, alle anderen Teile nichts
- [x] Datenschutz-Gate (G16) in `make lint`, `release.sh` und Pre-Commit-Hook, Gegenprobe 18.10.
- [x] `rafter-code-review` gegen G1–G16 (18.10., kein kritischer/hoher Fund, Härtungen B1–B12
      umgesetzt) und `rafter run` (18.10., Scan `c4fa8f06`, Standardmodus): 1 Warnung R-33E2F
      `release.sh` „curl in Interpreter“ – Fehlalarm (Feed wurde nur als Daten geparst), trotzdem
      umgestellt auf Datei laden, dann parsen
