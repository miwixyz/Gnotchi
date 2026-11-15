# Gnotchi – Meeting-Leiser und Lautstärkemixer je App

Stand 2026-11-15, **Vorschlag, noch nicht entschieden, nichts gebaut.** Anlass: Michael sah in den Screenshots von
Vorssaint den Lautstärkemixer je App und möchte ihn „schon gerne haben, gern in Gnotchi, optional wegen des
Datenschutzes“. Sein Hauptfall: „Ich nutze das relativ häufig in Meetings, dass zum Beispiel automatisch Spotify leiser
wird und das Meeting lauter.“ Michael: nicht eins zu eins kopieren, ruhig besser machen. Zum Ring der Tasten siehe
`2026-11-15-gnotchi-0.28.0-tasten-ring.md`.

## Was die Referenz dafür braucht (an der installierten App gemessen, 15.11.)

Nur Info.plist und Signatur-Berechtigungen von `/Applications/Vorssaint.app` (3.4.4) gelesen, kein Code:

- `NSAudioCaptureUsageDescription`: „uses each app's audio to adjust its volume in the mixer, to move Dynamic Island's
  music bars and to include the Mac's sound in the screen recordings“. Das ist die Freigabe für **Core-Audio-Prozess-
  Taps** (ab macOS 14.2): die App hört den Ton einer anderen App ab und gibt ihn selbst angepasst wieder aus.
- Die Treiber im Systemordner `/Library/Audio/Plug-Ins/HAL` gehören zu Teams und Parrot, **nicht** zu Vorssaint. Die
  Referenz bringt also **keinen eigenen virtuellen Audiotreiber** mit. Schluss mit mittlerer Sicherheit: Der Mixer
  beruht auf Taps und der Freigabe „Audio-Aufnahme“.
- Dieselbe App fragt außerdem nach Bluetooth, Kalender, Kamera, Mikrofon und Ordnern. Genau das will Gnotchi nicht
  (README: „Was Gnotchi nicht braucht“). Wir übernehmen die Funktion, nicht die Freigaben-Liste.

## Zwei Stufen, weil der Hauptfall keine neue Freigabe braucht

### Stufe 1 – Meeting-Leiser (Vorschlag für 0.29.0)

Gnotchi weiß schon, **welche App das Mikrofon nutzt** (Core Audio, ohne Freigabe, README „Mikrofon und Kamera“).

- Nutzt eine **gewählte Meeting-App** das Mikrofon, senkt Gnotchi die Lautstärke von **Spotify und Musik** per
  AppleScript (`sound volume`) auf einen Anteil des aktuellen Werts (Vorschlag 30 %, einstellbar) und blendet sie
  danach über etwa 1,5 s wieder auf den vorigen Wert. Die Automation-Freigabe für Spotify besteht schon (Spulen).
- **Meeting-Apps wählt Michael** aus einer Liste der Apps, die das Mikrofon zuletzt genutzt haben (Vorschlag: Teams,
  Zoom, FaceTime, Webex vorbelegt, wenn installiert). **Tippi gehört nicht dazu**: Diktat soll die Musik nicht leiser
  machen. Google Meet im Browser meldet „Edge“ bzw. „Helium“ als Mikrofon-App; wer sie wählt, ducked bei jeder
  Browser-Aufnahme (Offen 2).
- Ab Werk aus, eigener Schalter, eigene Zeile in den Einstellungen.
- **Nie leise hängen lassen.** Der vorige Wert wird gemerkt (in den Einstellungen, nicht nur im Speicher). Beendet sich
  Gnotchi oder stürzt es ab, stellt der nächste Start den Wert wieder her, wenn die Lautstärke noch auf dem
  Duck-Wert steht. Ändert Michael die Lautstärke selbst, während geduckt ist, wird sein neuer Wert **nicht**
  überschrieben.
- **Grenze, ehrlich:** Das macht Spotify/Musik leiser, das Meeting wird dadurch nicht lauter, sondern nur relativ lauter.
  Browser-Musik (YouTube, Safari) und andere Apps lassen sich damit nicht steuern, dafür ist Stufe 2 da.

### Stufe 2 – Voller Mixer je App (Prozess-Taps, optional)

- Neue große Ansicht `.mixer` mit einem Regler je Programm, das gerade Ton ausgibt, erreichbar über eine Taste im Ring
  (`ringButtons`-Kennung `mixer`, ab Werk aus). Ducking lässt sich darauf auf **beliebige** Apps ausdehnen, auch auf
  Browser, und „Meeting lauter“ wird möglich.
- **Neue Freigabe „Audio-Aufnahme“**, erst beim Einschalten angefragt, ab Werk aus. Das Datenschutz-Versprechen bleibt
  nur, wenn das Audio **ausschließlich im Speicher** läuft, nie in eine Datei, nie ins Netz, nur solange der Mixer an
  ist, und Gnotchi das in README und `docs/SECURE-DESIGN.md` (neue G-Nummer) so festschreibt.
- **Risiken, vor dem Bau messen:** Latenz und Aussetzer beim Abhören und Wiedergeben, Klangqualität, geschützte Inhalte
  (kopiergeschütztes Audio kann stumm werden), Wechsel des Ausgabegeräts (AirPods an/aus), CPU und Akku, Verhalten beim
  Beenden (Ton muss sofort wieder normal sein).
- **Erst ein Spike, dann die Spec:** `tools/tap-probe.swift` (Muster der vorhandenen Messwerkzeuge in `tools/`): ein Tap
  an Spotify, Verstärkung 0,5, Latenz messen, Freigabe-Dialog beobachten, Ton nach Beenden prüfen. **Aber** ein Messprogramm
  im Terminal ist nicht die App (Regel D): Das Ergebnis gilt erst, wenn es in der Mess-Fassung der App wiederholt wird.

### Stand Spike (15.11.)

- `tools/tap-probe.swift` geschrieben, baut sauber (Swift 6.4.2, macOS 27.2). Drei Modi: `liste` (zeigt Audio-Prozesse,
  kein Tap, keine Freigabe), `lesen` (Tap nur lesend, Original bleibt hörbar: prüft Freigabe und Pegel), `regeln` (Tap
  schaltet das Original stumm, Wiedergabe mit Verstärkung 1,0 → 0,3 → 1,0).
- `liste` gelaufen: Spotify (`com.spotify.client`, pid 20008) erscheint als Audio-Prozess, gab zu dem Zeitpunkt aber
  keinen Ton aus (Wiedergabe pausiert), deshalb noch kein Tap-Lauf.
- **Messlauf 15.11. (MacBook Air M5, Lautsprecher, Spotify spielte, aus dem Terminal-Panel):**
  - `lesen` 12 s: 1123 Rückrufe, Ø Abstand 10,67 ms (Soll 10,67), größter 10,77 ms, **0 Aussetzer-Verdacht**, Pegel
    kam an (Spitze 0,60), Last 0,30 % eines Kerns. Tap-Format 48 kHz, 2 Kanäle, Float32.
  - `regeln` 15 s (Original stumm, Wiedergabe mit Verstärkung 1,0 → 0,3 → 1,0): 1404 Rückrufe, größter Abstand 10,80 ms,
    **0 Aussetzer-Verdacht**, Last 0,27 %. Rechnerische Latenz 12,9 ms (Puffer 512 + Gerät 60 + Sicherheit 48 Frames).
  - Nach dem Ende war der Tap weg (kein eigener `AudioTap`-Eintrag, Programm beendet).
  - **Technisch trägt der Tap-Weg.** **Hörurteil Michael 15.11.: „Sauber, wie Original“** (Klang, Übergang auf 0,3 und
    zurück ohne Knacken). Latenz zu Bild nicht geprüft; Musik braucht das nicht, Video (YouTube im Browser) schon.
  - **Ergebnis des Spikes: bestanden.** Stufe 2 ist machbar. Vor dem Bau bleiben die Fragen, die das Terminal-Programm
    nicht beantwortet (siehe Einschränkungen und Risiken oben).
  - **Einschränkungen:** Während der Läufe lief Vorssaints Mixer mit; schon vor meinem Start hielt ein fremder
    `AudioTap` eine Sperre. Es ist nicht sicher, dass er die Werte nicht beeinflusst hat. Beim ersten Lauf erschien für
    mich kein Freigabe-Dialog (Freigabe für das Terminal-Programm wohl schon vorhanden, nicht geprüft). Latenz nur
    gerechnet, nicht gegen Bild gemessen.
- **Messlauf 2 (15.11., Geräte-Tap, neue Optionen `--geraetetap` und `--ziel=Gerätename`):**
  - **Geräte-Tap geht.** `CATapDescription(__processes:andDeviceUID:withStream:)` (Swift-Name mit `__`) auf
    `BuiltInSpeakerDevice`, Stream 0, an **Helium** (YouTube) und an **Apple Music**: Ton kam an, **0 Aussetzer-Verdacht**,
    Last unter 0,35 % eines Kerns.
  - **Echte Latenz aus den Zeitstempeln** (Eingang → Ausgabe, im Rückruf gemessen): **23,3 ms, konstant** (kleinste =
    größte, 1404 Rückrufe). Das ist die Verzögerung, die der Tap-Weg zum Original dazugibt. Zum Vergleich: Ein Ton, der
    bis etwa 125 ms *nach* dem Bild kommt, fällt bei Video üblicherweise nicht auf (Richtwert aus Normen zur
    Tonsynchronität, nicht von mir gemessen). **Hörurteil Michael 15.11. (Wiederholung, 20 s YouTube über den Tap,
    Verstärkung 1,0 → 0,3 → 1,0): Bild und Ton synchron.** Damit ist Offen 6 für das MacBook beantwortet.
  - **Wiedergabe auf anderem Gerät geht.** Apple Music wurde per Geräte-Tap abgegriffen und auf das **virtuelle
    Teams-Gerät** („Microsoft Teams Audio“) ausgegeben: Aggregat-Gerät mit dem virtuellen Treiber als Hauptgerät lief
    sauber (1120 Rückrufe, 0 Aussetzer, Latenz 23,3 ms). Damit ist die Mechanik „App-Ton auf ein anderes Ausgabegerät
    lenken“ belegt. **Hörurteil Michael 15.11. (Wiederholung mit YouTube in Helium, 15 s auf das Teams-Gerät):
    verstummte auf den Lautsprechern wie erwartet.** Damit ist das Umleiten auch am Ohr bestätigt (virtuelles Gerät,
    1 Kanal, 1402 Rückrufe, 0 Aussetzer).
  - **Apple Music über den Tap zurück auf die Lautsprecher** (20 s, Verstärkung 1,0 → 0,3 → 1,0, Geräte-Tap):
    1873 Rückrufe, größter Abstand 10,81 ms, **0 Aussetzer-Verdacht**, Latenz 23,3 ms, 0,27 % CPU. **Eingangsspitze
    1,037, also über Vollaussteuerung** (Float-Samples dürfen das). Folge: Jede Verstärkung über 1,0 („Meeting lauter“)
    braucht einen **Begrenzer**, sonst übersteuert der Ausgang. **Hörurteil Michael 15.11.: sauber.**
  - **Kanalzahl:** Das Teams-Gerät hat **1 Kanal** (mono), der Geräte-Tap lieferte 2 Puffer mit je 1 Kanal. Das Probe-
    Programm kopiert nur den ersten Puffer; eine App muss je nach Gerät mischen (stereo → mono, mono → stereo).
  - **Nicht gelöst:** Teams selbst (läuft auf dem MacBook nicht, nur das Widget) und **mehrere echte Lautsprecher**
    (Mac mini). Der Mac mini ließ sich nicht erreichen: Tailscale ist auf dem MacBook gestoppt (`ssh mac-mini` löst
    `mac-mini-mw` nicht auf). Ich habe es bewusst nicht eingeschaltet (Netzwerkeinstellung).
- **Ursprünglich offen: `lesen` und `regeln` mit laufender Wiedergabe.** Der erste Lauf löst den Dialog „Audio-Aufnahme“ für das
  Programm aus, aus dem er gestartet wird (Terminal bzw. Claude), nicht für Gnotchi. Das Ergebnis beantwortet nur, ob
  Taps technisch tragen; die Freigabe-Frage für Gnotchi selbst klärt erst die Mess-Fassung der App (Regel D).
- **Lesart des Ergebnisses:** Aussetzer-Verdacht > 0 oder größter Abstand deutlich über dem Soll → Latenz/Qualität
  problematisch. „Alles Stille“ → Freigabe fehlt (macOS liefert dann Nullen statt eines Fehlers). Hörtest bei `regeln`:
  Klingt Phase 1 wie das Original? Knackt der Übergang? Ist danach alles wieder normal?

## Nachträge beim Bau von Stufe 1 (15.11., Michael: „mach weiter“ nach 0.28.0)

Gebaut: **Meeting-Leiser** für Spotify und Musik (`MeetingDucker`, `DuckLogic`, G53), 18 neue Tests. Abweichungen vom Entwurf:

- **Ohne Geräte-Regel.** Der Entwurf wollte ab Werk „nur leiser bei gleichem Ausgabegerät“. Das braucht das Ausgabegerät der
  Meeting-App, und wie Teams über „Microsoft Teams Audio“ meldet, ist am MacBook nicht messbar. Eine ungeprüfte Regel würde
  im Zweifel nie leiser machen. Stufe 1 senkt deshalb **immer**; die Geräte-Regel folgt nach der Messung am **Mac mini**.
- **Kein Hinweis in der kleinen Insel** („Musik leiser, Meeting läuft“): nicht gebaut. Sichtbar ist es nur an der Musik und in den
  Einstellungen.
- **Auslöser sind Anzeige-Namen** (so meldet sie `PrivacyMonitor`), nicht Bundle-IDs. Ab Werk Teams, Zoom, FaceTime, Webex, Slack;
  weitere aus den Apps, die in diesem Lauf das Mikrofon genutzt haben. **Tippi zählt nie**, weil sie nicht in der Liste steht.
- **Keine Automation-Dialoge im Meeting:** Gnotchi steuert nur, wo macOS es schon erlaubt hat; sonst steht es in den
  Einstellungen. Für Musik kommt die Erlaubnis beim ersten Shuffle-Klick, für Spotify beim ersten Spulen.
- **Nicht gemessen:** der echte Ablauf mit Teams/Zoom, Spotify Connect (Ton auf anderem Gerät), Apple Music.
  Die Skripte sind getestet (feste IDs, Begrenzung), der Ablauf mit einem Attrappen-Player.
- **Noch offen:** Stufe 2 (Mixer), Geräte-Regel, Popover.

## Anforderungen aus Michaels Setup (15.11., nach dem Spike)

Michael: Der Mixer muss **Browser, Apple Music und YouTube** abdecken. Am **Mac mini hängen mehrere Lautsprecher**:
Teams läuft nur über einen, die anderen sind für Musik. Das muss unterscheidbar sein.

**Gemessen (MacBook, `liste`, ohne Tap und ohne Freigabe):**
- Welches Ausgabegerät ein Prozess nutzt, ist lesbar: `kAudioProcessPropertyDevices` meldete für Spotify
  „MacBook Air-Lautsprecher“. Die Geräteliste enthält auch „Microsoft Teams Audio“, ein **virtueller** Treiber von Teams
  (liegt in `/Library/Audio/Plug-Ins/HAL`).
- Browser-Ton kommt aus **Helfer-Prozessen**, nicht aus der App selbst: Helium meldet zwei Audio-Prozesse
  (`net.imput.helium.helper`, pid 6843/6844), ihr Programmpfad führt zu `Helium.app`. Beide gaben beim Messen keinen Ton aus.
  **Bei laufendem YouTube (Messung 15.11.):** Genau **einer** der beiden Helfer (pid 6843) gibt Ton aus und nennt
  „MacBook Air-Lautsprecher“, der andere (6844) nicht. Der Ton kommt also aus einem gemeinsamen Audio-Prozess des Browsers,
  nicht aus dem Tab; das bestätigt die Grenze „ein Browser = eine Zeile“ (Folgen 1).

**Folgen für den Entwurf:**

1. **Eine Zeile je App, nicht je Prozess.** Prozesse werden über das äußerste `.app` im Programmpfad zusammengefasst; der
   Regler wirkt auf alle Helfer dieser App (ein Tap mit mehreren Prozessen). Grenze: Ein Browser ist **eine** Zeile.
   Ein einzelner Tab (YouTube neben anderen Tabs) lässt sich so nicht getrennt regeln (Konfidenz mittel, nicht probiert).
2. **Gerät bleibt, wie es ist.** Die Zeile zeigt das Ausgabegerät der App. Der Tap muss auf **dem Gerät** wieder
   ausgeben, auf dem die App ursprünglich spielt, sonst landet Teams plötzlich bei den Musik-Lautsprechern. Dafür gibt es
   einen gerätespezifischen Tap (`CATapDescription` mit Geräte-UID und Stream), im Spike **noch nicht erprobt**. Mehrere
   Aggregat-Geräte gleichzeitig, eins je App und Gerät.
3. **Virtuelles Gerät von Teams.** Ob ein Tap an Teams funktioniert und auf dem richtigen Gerät landet, wenn Teams über
   „Microsoft Teams Audio“ ausgibt, ist offen und **am Mac mini zu messen**. Das MacBook kann diese Frage nicht
   beantworten.
4. **Apple Music:** gemessen 15.11. – eigener Prozess `com.apple.Music` (pid 23938, Programmpfad `Music.app`) mit
   Ausgabe auf „MacBook Air-Lautsprecher“, also derselbe Weg wie Spotify. Kein Sonderfall.
5. **Video (YouTube):** Der Tap fügt rechnerisch etwa 13 ms zu. Ob Bild und Ton dadurch merkbar auseinanderlaufen, ist
   ungemessen (Offen 6).
6. **Meeting-Leiser mit mehreren Lautsprechern (Stufe 1):** Gnotchi liest je Prozess das Ausgabegerät **ohne Freigabe**.
   Vorschlag: Ab Werk wird nur leiser, wenn Meeting-App und Musik **dasselbe Ausgabegerät** nutzen. Spielt Teams über einen
   eigenen Lautsprecher, bleibt die Musik laut. Schalter „Immer leiser, egal auf welchem Gerät“ für andere Fälle (Offen 7).
7. **Später, nicht jetzt:** Ausgabegerät je App umstellen. Der Tap-Weg könnte es nebenbei können (Wiedergabe auf anderes
   Gerät), ist aber ein eigenes Produktverhalten.

**Spike-Erweiterung:** `tools/tap-probe.swift liste` zeigt jetzt Ausgabegeräte und App-Namen je Audio-Prozess. Als
Nächstes: `regeln` mit gerätespezifischem Tap und Wahl des Ausgabegeräts, gemessen **am Mac mini** mit Teams plus
Musik auf getrennten Lautsprechern.

## Darstellung des Mixers und Menüleisten-Menü (Michael 15.11., mit Screenshot des Vorbilds)

Michael zeigte das Mixer-Fenster des Vorbilds (Menüleisten-Popover) und will „so eine Darstellung, nur schöner und
moderner“, **auch über das Menü-Symbol**. Dazu: **AirPlay- und Bluetooth-Wiedergabe** der gerade wiedergebenden
Medien-Programme sichtbar, und im Menü des Menü-Symbols ein **übersichtliches Menü aller Funktionen**.

Aus dem Screenshot gelesen (nur Aufbau, nicht Optik oder Branding): oben Ausgabegerät mit Lautstärkeregler und Prozent,
Gerät für Systemtöne, Mikrofon mit Gerät und Pegel; darunter eine Zeile je App (Symbol, Name, Menü „…“, Geräteauswahl
„Standard“, Regler, Prozent, Stumm-Symbol); unten aufklappbar „Optionen“; oben eine Reiterleiste mit Symbolen für die
Funktionsgruppen.

**Entwurf, Gnotchi-eigen:**

1. **Zwei Orte, eine Ansicht.** Der Mixer erscheint (a) groß in der Insel (Ring-Taste `mixer`) und (b) im
   Menüleisten-Popover. Beide teilen sich dieselbe SwiftUI-Ansicht und dieselben Daten.
2. **Kopf:** Ausgabegerät (Auswahl, Lautstärke, Prozent), Systemtöne-Gerät, Mikrofon (Gerät, Pegel, Stumm). Das ist
   alles Standard-Core-Audio ohne Tap und ohne Freigabe.
3. **Zeile je laufende App, nicht je Prozess** (Folgen 1 oben): Symbol, Name, **Gerät** (Auswahl, „Standard“ = bleibt
   wie es ist; ein anderes Gerät nutzt die gemessene Umleitung), Regler, Prozent, Stumm. Nur Apps, die gerade Ton
   ausgeben, kommen dazu.
4. **AirPlay und Bluetooth sichtbar:** Je Zeile steht das Ausgabegerät mit Symbol nach Übertragungsart
   (`kAudioDevicePropertyTransportType`: eingebaut, Bluetooth, AirPlay, USB). Das Gerät je Prozess ist ohne Freigabe
   lesbar (gemessen 15.11.: Spotify, Apple Music, Helium → „MacBook Air-Lautsprecher“). Gnotchi kennt schon den
   Wiedergabeweg des Players („Auf anderem Gerät“, AirPlay, Bluetooth, README). **Nicht gemessen:** AirPlay und Bluetooth
   auf diesem MacBook; Spotify Connect ist **kein** Core-Audio-Gerät und erscheint nur als „Auf anderem Gerät“.
5. **Optik: moderner statt Nachbau.** Gnotchi-Glas (`glassEffect`, Tönung `glassTint`), größere Regler mit Cover der
   laufenden Musik an der Musik-Zeile, die Bewegung der App-Familie (federnde Regler, Schatten unter der Maus). Keine
   Saturn-Marke, keine 1:1-Anordnung.
6. **Menüleisten-Menü als Übersicht aller Funktionen.** Heute ist das Menü des Symbols eine einfache Liste (Timer,
   Einstellungen, Hilfe, Update, Beenden). Entwurf: ein **Popover** (`MenuBarExtra` mit Fenster-Stil) mit Reiterleiste
   nach Funktionsgruppen – **Jetzt läuft** (Musik-Karte), **Mixer**, **Timer und Wach bleiben**, **Ablage und
   Zwischenablage**, **Wetter und Spiegel**, **Tasten** (Ring) – und unten Einstellungen, Hilfe, Beenden. Jede Funktion
   aus der Insel ist von dort erreichbar, auch ohne die Insel aufzuklappen.

**Folge für die Reihenfolge:** Das Menüleisten-Popover und die gemeinsame Mixer-Ansicht sind eigene Arbeit neben dem
Ring und dem Meeting-Leiser. Vorschlag: 0.28.0 Ring, 0.29.0 Meeting-Leiser (Stufe 1), 0.30.0 Menüleisten-Popover als
Übersicht, dann Mixer (Stufe 2) darin und in der Insel. **Offen für Michael:** Reihenfolge so recht? Soll das
Popover vor dem Mixer kommen (es ist die Hülle, in die der Mixer passt)?

## Wohin damit? (Michael: „kann auch in einem anderen Programm sein, wo es am besten passt“)

**Empfehlung: Gnotchi.** Mikrofon-Erkennung, Medien-Apps, die große Insel und der Ring sind schon da. Seam bleibt
bewusst ganz ohne Freigaben, Tippi braucht ohnehin das Mikrofon und ist das Diktat-Werkzeug, nicht die
Audio-Steuerung, Qotti und Kalli sind zu klein für eine Audio-Ebene.

## Reihenfolge

1. **0.28.0** Tasten-Ring (eigene Spec).
2. **0.29.0** Meeting-Leiser Stufe 1. Trifft Michaels Hauptfall ohne neue Freigabe.
3. Spike Stufe 2. Entscheidung nach der Messung, ob der volle Mixer in 0.30.0 kommt.

## Sicherheit

- **Stufe 1:** keine neue Freigabe. Neu ist, dass Gnotchi automatisch die Lautstärke einer anderen App ändert. Das ist
  ein Eingriff in Michaels Systemzustand, deshalb: Duck-Wert gemerkt, Wiederherstellung beim Start und Beenden,
  Hinweis in der kleinen Insel, solange geduckt ist („Musik leiser, Meeting läuft“).
- **Stufe 2:** neue Freigabe, siehe oben. `rafter-secure-design` vor dem Coden, `/code-audit` auf den Diff.

## Offen (Entscheidung beim Go)

1. Stufe 1 zuerst (0.29.0), dann Spike für Stufe 2: so recht?
2. Meeting-Apps: nur eine feste Liste, oder auch Browser wählbar (Meet)?
3. Duck-Anteil ab Werk 30 %, Rückblende 1,5 s: passt das?
4. Soll das Ducking auch bei **Tippi-Diktat** wählbar sein, ab Werk aus?
5. ~~Messlauf `liste` mit YouTube in Helium und Apple Music~~ **erledigt 15.11.** (siehe oben): Helium ein Helfer-Prozess,
   Music ein eigener Prozess, beide mit Geräteauskunft.
6. ~~Bild-Ton-Versatz bei YouTube mit Tap und 0,3-Verstärkung: merkbar?~~ **Nein** (Michael 15.11., MacBook,
   Lautsprecher, Latenz 23,3 ms). Am Mac mini mit anderen Geräten (Bluetooth, USB) noch nicht geprüft.
7. Meeting-Leiser nur bei **gleichem** Ausgabegerät (Vorschlag) oder immer?
