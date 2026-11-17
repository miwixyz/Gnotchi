# Gnotchi – Stream Deck Plus: Lautstärke, Lautsprecher und Wiedergabe je App

Stand 2026-11-17, **Entwurf mit Sicherheitsentwurf (`rafter-secure-design`), noch nicht gebaut.** Michael: „Ich möchte über das
Stream Deck Plus die verschiedenen Medien […] an können, also zum Beispiel Spotify, Apple Music, Browser und so weiter.“ Auf
Rückfrage alle drei Funktionen gewählt: **Lautstärke je App**, **Lautsprecher je App**, **Play/Pause je Quelle**.

Grundlage: Mixer Stufe 2 (`specs/2026-11-15-gnotchi-mixer-stufe2.md`, SECURE-DESIGN G55), Peer-Socket (`PeerSocketServer`,
G21), Ausgang setzen (G20). Neuer Sicherheitseintrag: **G59**.

## Umsetzung Stufe 1 (17.11., gebaut, am Gerät getestet, nicht committet, nicht released)

Michael am Stream Deck Plus: Drehen, Stumm, Play/Pause, Titelsprung, Lauftext – „Geht alles“. Abweichungen vom Entwurf unten:

- **Rahmen** wie alle Gnotchi-Sockets: 4 Byte Länge + JSON (`LiveText.frame`/`nextFrame`), nicht eine Zeile je Befehl.
  Befehle ≤ 512 Byte (`DeckWire.parse`), Rahmen ≤ 4096 (Rückmeldung mit Titeln).
- **„App-Lautstärke“ geht auf Regler und Taste** (`Controllers: Encoder, Keypad`). Gemessen: Aktionen nur für Regler zeigt
  Stream Deck 7.6.1 bei Michael gar nicht in der Liste (Test A/B/C: nur „Taste + Regler“ erschien; Bildgröße war es nicht).
  Auf einer Taste: drücken = stumm, Titel „App / Prozent“.
- **Stumm erst beim Loslassen;** **gedrückt drehen = nächster/vorheriger Titel** (ein Sprung je Druck, Michael 17.11.).
- **Lauftext als Bild** (`GnotchiDeck/TrackImage.swift`, Layout-Feld `track` = pixmap 176 × 30): zeichenweise wackelte es
  (Michael: „Scrollt wackelig“, Fall A). Jetzt 12 Bilder/s, 3 px je Bild, 1,5 s Halt, Schrift 17 pt („ruhig, Tempo passt“).
  Der Takt läuft nur, solange ein Regler scrollt. Plugin-CPU beim Scrollen ≈ 1 %.
- **Mixer-Abfrage für das Stream Deck langsam (4 s):** Das Plugin ist verbunden, solange Stream Deck läuft. Eigene Eingaben
  wirken sofort; öffnet jemand den Mixer, fragt er sofort ab und wieder alle 1,5 s.
- **Gemerkte Lautstärken:** Werte ≤ 5 % **nie** automatisch (nicht nur beim Neustart); nach Gerätewechsel (`.reset`) wieder
  angewendet. „Gemerkte Lautstärken vergessen“ in Einstellungen → Audio.
- **Nicht gebaut:** Hinweis „Plugin aktualisieren“ bei älterer Plugin-Version (Plugin meldet `hello` mit Version, Gnotchi wertet
  sie noch nicht aus). Stufe 2 (Lautsprecher je App) offen, M5 offen.
- **Offen beim Release:** `release.sh` prüft Plugin-Signatur und Manifest; der Weg über `make release` (Xcode-Export signiert
  das Programm in `Resources/…sdPlugin`) ist **noch nicht gemessen** – beim ersten Release `codesign -dv` am Artefakt prüfen.
  Ein heruntergeladenes Gnotchi mit Quarantäne: übernimmt das gepackte Plugin das Merkmal (`ShelfZip.copyQuarantine`)? M1 offen.

## Umsetzung Stufe 2 (17.11., gebaut, am Gerät getestet, nicht released)

Michael: „Ja, funktioniert.“ Spotify per Regler auf die Mac-mini-Lautsprecher, nach 20 s noch dort, Tippen → zurück.

- Tap-Motor: `Target.outputUID` (Ausgabe) neben `deviceUID` (Abgriff); Tap bleibt auch bei 100 %, solange umgeleitet.
  `MixerModel.setAppRoute`, Ziel immer mit aktueller Umleitung (ein Lautstärke-Schritt verliert sie nicht).
- Mixer: Klick auf das Gerät einer App → Menü mit allen Ausgabegeräten. Stream Deck: Aktion „App-Lautsprecher“.
- Auswahl am Regler: **alle** Ausgabegeräte, Favoriten zuerst (nur Favoriten war zu eng – Michael: „Keine Lautsprecher
  können ausgewählt werden“; bei ihm waren nur Kopfhörer und CalDigit Favoriten).
- **M5 – bestanden.** Umleitung hält; nach `kill -9` von Gnotchi spielte Spotify von selbst wieder auf den Kopfhörern.
- **Fund unterwegs:** Die erste Umleitung sprang nach 1,5 s zurück (Protokoll: „Tap ohne Ton abgebaut“). Ursache: Gnotchi
  hatte am Mac mini nie die Freigabe für Systemaudio; macOS hat nie gefragt (Michael: kein Dialog, in „Aufnahme von
  Bildschirm & Systemaudio“ stand nur „Gnotchi Bild“). Von Hand eingetragen → funktioniert. Hinweise eingebaut.
  Messpunkt: jeder Abbruchgrund beim Umleiten steht im Protokoll.
- Hinweis „Plugin aktualisieren“: `hello`-Version gegen die eigene, nur in den Einstellungen.
- **Alle Stream Decks** (Michael 17.11.): „App-Lautstärke“ auf einer Taste mit Einstellung „Taste“ = Stumm / Lauter / Leiser
  (±5 % je Druck). Am Stream Deck Neo getestet: „funktioniert“. Bei Michael sind Stream Deck +, Neo und ein virtuelles
  Stream Deck angemeldet.

## Heute (Stand `fb2b915`, 0.34.1)

- **Keine Stream-Deck-Anbindung.** G13 verbietet jede Fremdsteuerung: kein URL-Schema, kein AppleScript-Empfang, keine
  Services, keine XPC-Schnittstelle. Alle Sockets (Live-Text G21, Kalli G26, Mitteilungen G29/G30) liefern **nur Anzeige**.
- Was schon da ist und genutzt werden kann:
  - `MixerModel.setAppGain` – Regler je App 0–200 % über Prozess-Taps (Einstellung „Lautstärke je App“, ab Werk aus,
    Freigabe „Audio-Aufnahme“). Spotify/Musik über AppleScript ohne Tap.
  - `MixerModel.selectOutput` / Favoritenliste der Ausgabegeräte (0.31.0).
  - Wiedergabe: `MediaAdapter` (MediaRemote, **nur die App, die macOS gerade als „spielt“ führt**) und `AppleScriptSource`
    (Spotify, Musik gezielt).
- Gemessen am Mac mini, 17.11.:
  - Stream Deck **7.6.1**, signiert `Developer ID Application: Corsair Memory, Inc. (Y93VXCB8Q5)`, Kennung `com.elgato.StreamDeck`.
  - Stream Deck startet Plugins als Kindprozesse (`ppid` = Stream-Deck-Prozess), mit `-port 28196 -pluginUUID … -registerEvent … -info …`.
    WebSocket auf `127.0.0.1`.
  - **Native Plugins laufen:** `com.fredemmott.audiooutputswitch` ist eine Mach-O-Universal-Datei, kein Node. Das Manifest-Schema
    von Elgato nennt als `CodePath`-Beispiel ausdrücklich eine Datei ohne Endung („Counter“).
  - Alle JavaScript-Plugins (über 20 installiert) laufen in **Elgatos gemeinsamer Node-Laufzeit** (`…/NodeJS/20.20.2/node`).

## Ziel

Am Stream Deck Plus (4 Drehregler mit Touch-Leiste, 8 Tasten):

| Element | Drehen | Drücken | Tippen auf Leiste | Anzeige auf der Leiste |
|---|---|---|---|---|
| **Regler „App-Lautstärke“** | ±2 % je Raste (0–200 %, rastet bei 100 % ein) | stumm / an | Play/Pause dieser App | App-Symbol, Titel (sonst Name), Prozent, Balken |
| **Regler „App-Lautsprecher“** | blättert durch die Ausgabe-Favoriten (nur Vorschau) | übernimmt das Gerät für diese App | zurück auf Systemausgang | App-Name, gewähltes Gerät |
| **Taste „Wiedergabe“** | – | Play/Pause / Weiter / Zurück (je Taste wählbar) | – | App-Symbol, ▶/❚❚ |

Je Element wählt Michael in den Stream-Deck-Einstellungen die App: **Spotify, Musik, Podcasts, Safari, Helium, Edge** oder
**„gerade spielend“** (folgt der Quelle, die Gnotchi in der Insel zeigt). Entschieden 17.11.

**Lautstärke je App wird gemerkt** (Michael, 17.11.): Ein Regler, der nicht auf 100 % steht, bleibt für diese App gespeichert,
über Pause, Beenden der App und Neustart von Gnotchi hinweg. Gibt die App wieder Ton aus, setzt Gnotchi den Tap mit dem
gemerkten Wert neu auf. Gilt für Stream Deck **und** den Mixer in Insel und Popover (eine Funktion). Spotify und Musik merken
ihre Lautstärke selbst, dort speichert Gnotchi nichts. Zurücksetzen: Regler auf 100 % (wird dann gelöscht) oder „Alle auf
100 %“ im Mixer.

## Lösungsweg

**Ein eigenes, natives Stream-Deck-Plugin in Swift** (`GnotchiDeck`), mit Michaels Developer ID signiert und als Teil von
Gnotchi notarisiert. Es spricht zwei Seiten:

```
[Stream Deck App] ⇄ WebSocket 127.0.0.1 ⇄ [GnotchiDeck, Kindprozess]  ⇄ Unix-Socket deck.sock ⇄ [Gnotchi]
  Elgato-signiert         Stream-Deck-Protokoll    LTKJ6Z2VYB-signiert       feste JSON-Befehle            prüft beides
```

- **Warum nicht JavaScript:** Ein Node-Plugin läuft in Elgatos gemeinsamer Node-Laufzeit. Gnotchi könnte am Socket nur „Elgatos
  Node“ prüfen, also würde jedes der über 20 installierten Plugins (und jedes künftige) zugelassen. Ein eigenes signiertes
  Programm lässt sich eindeutig prüfen, genau wie Tippi am Live-Text-Socket.
- **Warum Gnotchi die Logik behält:** Taps, Freigaben, AppleScript-Ziele und Geräteliste leben schon in Gnotchi. Das Plugin
  übersetzt nur Drehen, Drücken und Tippen in Befehle und zeigt Gnotchis Antwort an. Es hat keine Freigaben und keine eigene
  Audio-Logik.
- **Auslieferung:** Das Plugin liegt in `Gnotchi.app/Contents/Resources/dev.mwlr.gnotchi.streamDeckPlugin`. In den
  Einstellungen gibt es „Stream Deck“ (ab Werk aus) mit der Taste „Plugin installieren“. Sie öffnet die Datei, Stream Deck
  übernimmt die Installation mit eigenem Dialog. Gnotchi installiert nie selbst in Elgatos Ordner.
- **Updates:** Das Plugin meldet beim Verbinden seine Version. Ist sie älter als die in Gnotchi, zeigt die Leiste
  „Plugin aktualisieren“ und die Einstellungen bieten die Taste erneut an.

## Stufen

### Stufe 1 – Lautstärke und Wiedergabe (0.35.0)

1. Plugin `GnotchiDeck` (Swift, eigenes Xcode-Ziel, keine Fremdbibliothek: WebSocket über `URLSessionWebSocketTask`).
   Aktionen „App-Lautstärke“ (Regler) und „Wiedergabe“ (Taste). Layout für die Leiste 200 × 100 px.
2. `DeckLink` in Gnotchi: Socket `deck.sock` im selben Ordner wie `live.sock`, auf Basis `PeerSocketServer`, aber mit
   Befehlen (G59).
3. Solange ein Plugin verbunden ist, zählt es als „Betrachter“ des Mixers (`MixerModel` fragt dann ab, sonst nur bei
   sichtbarem Mixer). Abfrage-Takt dafür langsamer als im Popover (Vorschlag 1 s), Änderungen werden sofort geschickt.
4. Spotify/Musik: Lautstärke und Wiedergabe gezielt per AppleScript (vorhandener Weg, Automation-Freigabe je App).
   Alle anderen: Lautstärke über Tap (braucht „Lautstärke je App“ an), Wiedergabe über MediaRemote **nur wenn die App gerade
   die aktive Quelle ist**, sonst zeigt die Leiste „nicht aktiv“ (siehe Messpunkt M3).

### Stufe 2 – Lautsprecher je App (0.36.0)

1. Tap-Motor erweitern: Ziel-Gerät des Aggregats frei wählbar statt „das Gerät, auf dem die App spielt“. Im Spike vom 15.11.
   aus dem Terminal belegt („Umleiten auf anderes Gerät“), **in Gnotchi selbst noch nicht gemessen** (Regel D).
2. Aktion „App-Lautsprecher“ im Plugin, dieselbe Zuordnung auch im Mixer der Insel (eine Funktion, zwei Bedienwege).
3. Umleitung hält, solange die App Ton ausgibt und Gnotchi läuft; beim Beenden, beim Abschalten der Einstellung und wenn das
   Ziel-Gerät verschwindet: zurück auf direkt (wie `releaseAll`).

## Befehle (Plugin → Gnotchi)

Eine Zeile JSON je Befehl, höchstens 512 Byte, UTF-8. Unbekannte Felder oder Werte → Zeile verworfen, Zähler im Protokoll
(nie der Inhalt).

```json
{"v":1,"hello":"0.35.0"}
{"v":1,"cmd":"gain","app":"com.spotify.client","delta":-2}
{"v":1,"cmd":"mute","app":"com.spotify.client"}
{"v":1,"cmd":"play","app":"current","what":"toggle"}
{"v":1,"cmd":"route","app":"com.apple.Music","device":"<UID>"}
{"v":1,"cmd":"route","app":"com.apple.Music","device":null}
{"v":1,"watch":["com.spotify.client","current"]}
```

- `app`: Bundle-ID oder `"current"`. Nur Werte nach Muster `^[A-Za-z0-9.-]{1,128}$`.
- `delta`: ganze Zahl −20…20 (Prozentpunkte). Gnotchi rechnet selbst und begrenzt auf 0–200.
- `what`: `toggle | next | previous`. Kein Spulen, kein Öffnen, kein Starten.
- `device`: nur eine UID aus der **frischen** Ausgabeliste und aus den Favoriten (G20), sonst abgelehnt.

## Rückmeldung (Gnotchi → Plugin)

Nur für die per `watch` angemeldeten Apps, gedrosselt auf höchstens 10 Meldungen/s:

```json
{"v":1,"app":"com.spotify.client","name":"Spotify","title":"…","artist":"…","percent":64,"muted":false,"playing":true,"device":"MacBook-Lautsprecher","state":"ok"}
```

`title`/`artist` nur, wenn die App gerade die Quelle in der Insel ist (MediaRemote kennt nur die aktive Quelle) oder Spotify/Musik
per AppleScript; sonst fehlen beide Felder und die Leiste zeigt den App-Namen. Beide höchstens 200 Zeichen, Steuerzeichen entfernt.

**Lauftext für lange Titel** (Michael, 17.11.: „Der Titel muss aber scrollen, damit man den ganzen Titel sieht und nicht nur
Punkt Punkt Punkt“). Stream Deck schneidet zu langen Text auf der Leiste mit „…“ ab und scrollt nicht selbst. Deshalb scrollt
das Plugin: Passt „Titel – Interpret“ nicht in die Zeile, schiebt es den Ausschnitt per `setFeedback` weiter, etwa 4 Schritte
je Sekunde, mit 1,5 s Halt am Anfang. Danach eine Lücke und der Text beginnt von vorn wie ein Laufband. Passt der Text, steht er
still. Neuer Titel → Lauftext beginnt von vorn. Läuft nur, solange die Aktion sichtbar ist (`willAppear`/`willDisappear`).
Gnotchi schickt den Titel nur bei Änderung, das Scrollen macht allein das Plugin (kein Verkehr auf `deck.sock`).
Bei 4 Reglern höchstens 16 `setFeedback` je Sekunde an Stream Deck. Ob das flüssig aussieht und wie viele Zeichen in eine
Zeile passen, misst M7.

`state`: `ok | silent` (App gibt keinen Ton aus) `| needsSetting` („Lautstärke je App“ aus) `| needsPermission`
(Freigabe fehlt) `| notActive` (Wiedergabe nur für die aktive Quelle möglich).
**Titel und Interpret ja, Cover nein** (G59 Punkt 6).

## Sicherheitsentwurf (G59, Vorschlag)

### Was neu ist

G13 wird gelockert: **ein einziger, geprüfter Absender** darf Befehle schicken. Das ist die größte Änderung am
Vertrauensmodell seit 0.1. Bisher konnte nur ein Klick des Nutzers etwas auslösen. Jetzt kann es auch ein Prozess, der
beweist, dass er (a) unser Plugin ist und (b) von Elgatos Stream-Deck-App gestartet wurde.

### Entscheidungen

1. **Peer-Prüfung vor dem ersten Byte** (wie G21), Anforderung:
   `anchor apple generic and identifier "dev.mwlr.gnotchi.deck" and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "LTKJ6Z2VYB"`.
2. **Eltern-Prüfung:** Der Elternprozess des Peers (aus dem Audit-Token → PID → `ppid`, dann `SecCodeCopyGuestWithAttributes`)
   muss `identifier "com.elgato.StreamDeck"` mit `certificate leaf[subject.OU] = "Y93VXCB8Q5"` erfüllen. Sonst Verbindung zu.
   **Grund:** Ohne diese Prüfung könnte jedes Programm unser signiertes Plugin selbst starten, ihm einen eigenen „Stream
   Deck“-Port geben und es fernsteuern (Confused Deputy). Das Plugin prüft dasselbe zusätzlich selbst beim Start.
   Restrisiko: PID-Wiederverwendung zwischen Abfrage und Prüfung. Wir prüfen das Audit-Token des Peers und danach die
   Elternkennung; ein Angreifer bräuchte dafür ohnehin Code-Ausführung als Michael (siehe Restrisiken).
3. **Feste Befehlsliste, keine Pfade, keine Skripte.** Kein Befehl startet eine App, öffnet eine URL, spult oder schickt Apple
   Events an andere Ziele als die fest verdrahteten Spotify und Musik. AppleScript-Texte bleiben fest im Code (G7).
4. **Grenzen:** Zeile ≤ 512 Byte, Puffer ≤ 4 KB, höchstens 50 Befehle/s (darüber verworfen), höchstens eine Verbindung
   gleichzeitig. Gain-Aufrufe je App weiter über die vorhandene „höchstens ein Aufruf gleichzeitig, neuester Wert“-Bremse.
5. **Einstellung „Stream Deck“ ab Werk aus.** Aus = Socket gar nicht offen. Die Einstellung erweitert keine Freigabe:
   Ohne „Lautstärke je App“ und „Audio-Aufnahme“ gibt es für Browser keinen Regler, das Plugin zeigt nur „Einstellung fehlt“.
6. **Rückkanal mit Titel, bewusst entschieden** (Michael, 17.11.: „Titel anzeigen“). Gesendet werden App-Name, Titel, Interpret,
   Prozent, stumm, spielt, Gerätename, Zustand. **Damit erfährt Elgatos Stream-Deck-App, was Michael hört.** Das ist die erste
   Stelle, an der Hördaten Gnotchis Prozess verlassen (bisher nur Anzeige in der eigenen Insel). Begrenzung: kein Cover, keine
   Wiedergabezeit, Text höchstens 200 Zeichen; Titel nur an ein geprüftes Plugin (1, 2); unser Plugin gibt Titel nur per
   `setFeedback` an die Leiste. Gemessen (M6): Stream Deck schreibt `setFeedback`- und `setTitle`-Inhalte **nicht** in seine
   Protokolle. **Aber:** Stream Deck legt je Plugin eine eigene Protokolldatei an
   (`~/Library/Logs/ElgatoStreamDeck/dev.mwlr.gnotchi.deck*.log`, beim Probe-Plugin: „Process started“), vermutlich die
   Konsolenausgabe des Plugins. Deshalb: **Das Plugin schreibt nie etwas auf stdout/stderr**, das Titel, Interpret, Bundle-IDs
   oder Gerätenamen enthält. Nur feste Zustandstexte (gestartet, verbunden, abgelehnt).
6a. **Gemerkte Lautstärken** (Erweiterung G14): UserDefaults-Schlüssel `appGains`, Wörterbuch Bundle-ID → Prozent (0–200,
   ohne 100), höchstens 50 Einträge (älteste fallen raus). Nur Bundle-IDs nach Muster aus „Befehle“, sonst beim Lesen
   verworfen. Ein gemerkter Wert setzt einen Tap ohne neuen Klick auf – nur bei eingeschalteter „Lautstärke je App“ und
   erteilter Freigabe; ist die Einstellung aus, bleibt der Wert gespeichert, wirkt aber nicht. Nie leise hängen (G53): Wert
   ≤ 5 % wird beim Neustart von Gnotchi nicht automatisch angewendet, sondern der Regler zeigt ihn nur an.
7. **Protokoll ohne Inhalte** (G8): Verbindung auf/zu, abgelehnte Peers mit Grund, Zähler verworfener Zeilen. Nie Bundle-IDs
   aus Befehlen, nie Geräte-UIDs.
8. **Kein Audio verlässt Gnotchi.** Befehle setzen nur Verstärkung und Ziel-Gerät. Es gibt keinen Befehl, der Pegel, Puffer oder
   Tap-Daten zurückgibt (G55 bleibt unverändert).
9. **Umleitung nie hängen lassen** (Stufe 2, wie G53): Verschwindet das Ziel-Gerät, stürzt das Plugin ab oder wird die
   Einstellung abgeschaltet → App spielt wieder direkt. Stürzt Gnotchi ab, enden die Taps mit dem Prozess (macOS räumt private
   Aggregate auf, im Spike beobachtet, in Gnotchi zu messen: M5).

### Vertrauensgrenzen und Datenfluss

```
Drehregler ┆ Stream Deck App ┆ GnotchiDeck ┆ Gnotchi (Peer + Eltern geprüft) → Mixer/Taps/AppleScript ┆ Core Audio / Spotify / Musik
 Raste        WebSocket JSON    Befehl-JSON      Schema, Grenzen, frische Gerätelisten                       Verstärkung, Gerät, Play/Pause
```

Grenzen: (1) Stream Deck → Plugin (Elgatos Protokoll, lokaler WebSocket), (2) Plugin → Gnotchi (`deck.sock`, beidseitig
signaturgeprüft), (3) Gnotchi → Core Audio / Apple Events (bestehende Freigaben).

### STRIDE

| | Bedrohung | Antwort |
|---|---|---|
| **S** | Fremder Prozess gibt sich als Plugin aus | Signaturprüfung vor dem ersten Byte (1) |
| **S** | Fremder Prozess startet echtes Plugin mit eigenem Port | Eltern-Prüfung auf Elgatos Signatur (2) |
| **S** | Anderes Stream-Deck-Plugin steuert unsere Aktionen | Stream Deck stellt Ereignisse nur an das Plugin der Aktion zu; unser Plugin hat keine Property-Inspector-Seite mit Befehlswegen, nur Auswahl-Felder |
| **T** | Plugin-Datei in Elgatos Ordner verändert | Signatur bricht → (1) lehnt ab |
| **T** | Manipulierte Befehle (Pfade, Skripte) | Es gibt keine solchen Felder; Schema (3) |
| **R** | Wer hat leiser gemacht? | Lokale Einzelperson; Zähler im Protokoll reichen |
| **I** | Hördaten über Rückkanal an Elgato | Bewusst angenommen: Titel und Interpret gehen an Elgatos Prozess, kein Cover, begrenzt, nur an geprüftes Plugin (6); nicht in Elgatos Protokollen (M6); nie auf stdout/stderr des Plugins (6) |
| **I** | Geräte-UIDs/Bundle-IDs im Protokoll | Nie protokolliert (7) |
| **D** | Befehlsflut friert Audio oder Hauptthread ein | 50/s-Grenze, eine Verbindung, Gain-Bremse (4); Mixer-Abfrage abseits des Hauptthreads (wie 0.33.1) |
| **D** | App bleibt stumm/umgeleitet hängen | Rückfall auf direkt (9) |
| **E** | Plugin nutzt Gnotchis Automation-/Audio-Freigabe als Hebel | Nur feste Befehle auf feste Ziele (3); keine neue Freigabe (5); kein Audio zurück (8) |

### Restrisiken (bewusst angenommen)

- Wer schon Code als Michael ausführt, kann Spotify per Stream-Deck-Weg lauter/leiser machen und pausieren. Das konnte er
  vorher über eigenes AppleScript auch (mit eigenem Freigabe-Dialog). Neu ist nur, dass dieser Dialog entfällt – begrenzt auf
  Lautstärke, stumm, Play/Pause, Weiter/Zurück und Ausgabegerät aus Michaels Favoriten. Kein Zugriff auf Ton-Inhalte.
- Titel und Interpret liegen im Arbeitsspeicher von Elgatos Stream-Deck-App (Michaels Entscheidung, G59 Punkt 6).
- Elgatos Stream-Deck-App ist Teil der Vertrauenskette. Wird sie kompromittiert, kann sie unser Plugin fernsteuern (im selben
  engen Befehlsumfang).

## Messpunkte vor dem Bauen

- **M1 – bestanden (17.11., Mac mini, Stream Deck 7.6.1, Stream Deck Plus).** Wegwerf-Plugin `tools/deck-probe/`
  (Swift, `swiftc -O`, Kennung `dev.mwlr.gnotchi.deck`, Developer ID + Hardened Runtime, notarisiert „Accepted“, Gatekeeper
  „Notarized Developer ID“), gepackt per `ditto -c -k --norsrc --noextattr --keepParent` als `.streamDeckPlugin`, per `open`
  installiert (Stream-Deck-Dialog). Ergebnis:
  - Stream Deck startet die Mach-O-Datei direkt als Kindprozess (`ppid` = Stream Deck), mit `-port -pluginUUID -registerEvent -info`.
    Anmeldung über `URLSessionWebSocketTask` klappt, keine Fremdbibliothek nötig.
  - Installierte Kopie: **kein Quarantäne-Attribut**, Signatur unverändert gültig (`satisfies its Designated Requirement`).
  - Ereignisse kamen an: `willAppear`, `keyDown/keyUp` (Taste), `dialDown/dialUp`, `dialRotate`, `touchTap` (Regler, Leiste),
    `deviceDidConnect`. `setTitle` und `showOk` liefen ohne Sendefehler.
  - Nebenbefund M2 (nur Plugin-Seite): `SecCodeCopyGuestWithAttributes(ppid)` gegen
    `identifier "com.elgato.StreamDeck" and certificate leaf[subject.OU] = "Y93VXCB8Q5"` → `0` (bestanden).
    Die Gnotchi-Seite (Audit-Token des Socket-Peers → Eltern) ist weiter offen.
  - Nebenbefund M4: beim normalen Drehen bis 9 `dialRotate`-Ereignisse je Sekunde; `ticks` je Ereignis nicht protokolliert.
    Die Grenze von 50 Befehlen/s hat damit reichlich Luft.
  - Offen: Ob ein **heruntergeladenes** Paket (mit Quarantäne) genauso startet, ist nicht gemessen. Im geplanten Weg kommt das
    Plugin aus der notarisierten `Gnotchi.app`, deshalb unkritisch.
  - Aufgeräumt 17.11.: Probe-Plugin, Protokolle und Programmdatei im Papierkorb, Stream Deck läuft ohne Probe.
- **M2 – bestanden (17.11.).** Prüf-Server `tools/deck-probe/m2-server.swift` (dieselbe Peer-Prüfung wie
  `PeerSocketServer.checkPeer`: `LOCAL_PEERTOKEN` → `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAudit)`; dazu PID aus dem
  Audit-Token → `proc_pidinfo(PROC_PIDTBSDINFO).pbi_ppid` → Elgato-Anforderung). Ergebnisse:

  | Absender | Peer-Prüfung | Eltern-Prüfung | Ergebnis |
  |---|---|---|---|
  | Probe-Plugin, von Stream Deck gestartet | 0 | 0 (Stream Deck) | angenommen |
  | **dasselbe signierte Plugin, aus der Shell gestartet** | 0 | −67050 (`/bin/zsh`) | **abgelehnt** |
  | Python ohne unsere Signatur | −67050 | −67050 | abgelehnt |
  | Verbindung, die vor der Prüfung schließt | −67063 (kein Audit-Token) | – | abgelehnt (schließt sicher) |

  Die zweite Zeile ist der Grund für die Eltern-Prüfung: Ohne sie wäre das selbst gestartete echte Plugin durchgekommen.
  Für den Bau: Elterncode per PID statt Audit-Token (für den Elternprozess gibt es kein Token). Restrisiko PID-Wiederverwendung
  bleibt wie in G59 Punkt 2 beschrieben.
- **M3 – teilweise (17.11.).** `MediaRemote.framework` exportiert `MRMediaRemoteSendCommandToApp`, `…ToPlayer`, `…ToClient`
  (per `dlsym` geprüft). Der eingebaute `mediaremote-adapter` kennt aber nur `send` an die aktive Quelle, die Signatur der
  gezielten Funktion steht in keinem seiner Header. Gezielt senden hieße: Adapter (BSD-3, in `Vendor/`) um eine Funktion mit
  unbekannter Signatur erweitern und neu bauen. Ein Aufruf mit geratener Signatur wurde **bewusst nicht gemacht** (Absturz-
  und Fehlmessungsgefahr). **Für Stufe 1:** Browser nur, wenn sie die aktive Quelle sind (Leiste zeigt sonst „nicht aktiv“);
  Spotify und Musik gezielt per AppleScript. Gezielte Browser-Steuerung = eigener späterer Spike.
- **M4 – bestanden (17.11.).** Normal gedreht bis 9 `dialRotate`/s, `ticks` meist ±1, bei schnellem Drehen −2 (28 Ereignisse:
  13 × +1, 13 × −1, 2 × −2). Deshalb `delta = ticks × 2 %`. Die 50/s-Grenze hat reichlich Luft.
- **M5** – Stufe 2: Umleiten auf ein anderes Gerät **aus Gnotchi selbst** (nicht Terminal), inklusive Absturz von Gnotchi
  während der Umleitung: spielt die App danach wieder direkt?
- **M6 – bestanden (17.11.).** Testtexte über `setTitle` und `setFeedback` (Layout `$B1`, Felder `title`, `value`,
  `indicator`) erschienen auf der Leiste (Michael: „Ja, der Text steht auf der Leiste“). Danach stehen sie in **keiner** Datei
  unter `~/Library/Logs/ElgatoStreamDeck/` und nicht in `ProfilesV3`. Nebenbefund: Stream Deck legt je Plugin eine eigene
  Protokolldatei an (`dev.mwlr.gnotchi.deckprobe0.log`: „Process started“) → G59 Punkt 6: nie Inhalte auf stdout/stderr.
- **M7 – bestanden (17.11.).** Zeichenweise (250 ms) wackelte es, rund 20 Zeichen passten in die Zeile. Als Bild pixelweise
  (12 Bilder/s, 3 px) läuft es ruhig; Schrift 14 → 17 pt (Michael: „Schrift etwas klein“ → „gut lesbar“). Fund unterwegs:
  Die Anfangspause wurde nie heruntergezählt (Zustand nicht zurückgeschrieben) – per Zähler-Messpunkt gefunden („0 Schritte
  gesendet“), behoben. Plugin-CPU ≈ 1 %.

## Entschieden (Michael, 17.11.)

1. **Lautstärke je App merken:** ja → „Ziel“ und G59 Punkt 6a.
2. **Titel auf der Leiste:** ja → G59 Punkt 6, Prüfung M6.
3. **App-Auswahl:** Spotify, Musik, Podcasts, Safari, Helium, Edge, „gerade spielend“.
4. **Lange Titel scrollen** statt „…“ → „Rückmeldung“, Messpunkt M7.

## Nicht Teil dieser Spezifikation

- Systemlautstärke und Mikrofon am Stream Deck (kann Elgatos Volume-Controller-Plugin oder später ein eigener Regler).
- Stream Deck ohne Plus (nur Tasten): die Taste „Wiedergabe“ funktioniert dort mit, Regler nicht.
- Veröffentlichung im Elgato Marketplace.

## Quellen

- Elgato Manifest-Schema (`CodePath` mit nativem Beispiel): https://schemas.elgato.com/streamdeck/plugins/manifest.json
- Elgato Plugin-Umgebung: https://docs.elgato.com/sdk/plugins/architecture
- Regler und Touch-Leiste (Layouts 200 × 100 px, `dialRotate`, `dialDown`, `touchTap`, `setFeedback`): https://docs.elgato.com/sdk/plugins/layouts-sd+
