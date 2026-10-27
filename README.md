# Gnotchi

Eine Insel in der MacBook-Notch für macOS 27, gebaut im Stil des Systems. Läuft Musik oder ein
Video, zeigt Gnotchi in der Notch Cover und Pegel. Fährst du mit der Maus darüber, geht die Insel
auf und zeigt Titel, Interpret, App, Tasten und Fortschritt. Auf Bildschirmen ohne Notch erscheint
dieselbe Insel als Pille oben in der Mitte. Dazu zeigt sie dein Diktat in
[Tippi](https://github.com/miwixyz/Tippi), welche App Mikrofon oder Kamera nutzt und wenn du
Kopfhörer verbindest, und in der großen Insel wählst du den Audio-Ausgang. Läuft mehreres
gleichzeitig, etwa Musik, Kopfhörer und ein bereites Update, wechselt die kleine Insel zwischen ihnen.

**Stand:** Version 0.11.1, [Download unter Releases](https://github.com/miwixyz/Gnotchi/releases/latest).
Website gnotchi.mwlr.dev ist geplant. Kurzvorstellung: [docs/ONE-PAGER.md](docs/ONE-PAGER.md)

Voraussetzungen: macOS 27, Mac mit Apple-Chip. Kostenlos, Open Source (MIT).

| Klein in der Notch | Groß, Ton auf anderem Gerät |
|---|---|
| ![Kleine Insel in der Notch](docs/assets/render-insel-notch-klein.png) | ![Große Insel mit „Auf anderem Gerät“](docs/assets/render-insel-notch-gross-anderes-geraet.png) |

| Groß als Pille (ohne Notch) | Groß, Ton über AirPlay |
|---|---|
| ![Große Insel als Pille](docs/assets/render-insel-pille-gross.png) | ![Große Insel mit AirPlay-Gerät](docs/assets/render-insel-pille-gross-airplay.png) |

Die Bilder rendern die Tests (`IslandViewRenderTests`) mit Platzhalter-Cover und erfundenem Titel
vor grauem Grund. Die rote Linie markiert die Hardware-Notch. Die beiden Bilder mit App-Symbol sind
etwas dunkler, das ist eine Eigenheit des Renderers, nicht der App.

Entstanden im Repo von [Seam](https://github.com/miwixyz/Seam) und am 18.10.2026 ausgelagert:
Seam hält die Bedienungshilfen-Freigabe, und ein Kindprozess könnte sie erben. Gnotchi hat diese
Freigabe nicht und fragt nie danach.

## Funktionen

- **Medien aus jeder Quelle**, die macOS als laufende Wiedergabe meldet: Spotify, Musik und
  Browser wie Safari, Edge oder Helium (auch Videos).
- **Auf dem Schreibtisch (0.15, ab Werk aus):** Cover, Titel und Interpret hinter allen Fenstern, frei verschiebbar,
  Knöpfe beim Drüberfahren, nach 10 Minuten Pause weg. Gleiche Daten wie die Insel, keine Freigabe
  ([G44](docs/SECURE-DESIGN.md)).
- **Plattenspieler (0.17, ab Werk aus):** dieselbe Anzeige als drehender Plattenspieler mittig auf einem wählbaren
  Bildschirm, Tonarm wandert mit dem Titel, Farbverlauf aus dem Cover unter den Schreibtisch-Symbolen, optional
  Neonschrift „Now Playing“ und Start/Pause über den Start/Stopp-Knopf am Gerät. Gezeichnet aus KI-Fotos (Ebenen, gemessene Perspektive).
- **Shuffle (0.17):** bei Spotify und Musik in der großen Insel und am Plattenspieler, per AppleScript nur auf Klick
  ([G7](docs/SECURE-DESIGN.md)). Ein Favoriten-Herz fehlt noch (Musik ignoriert den Befehl bei Apple-Music-Titeln,
  Spotify erlaubt ihn nicht).
- **Klein und groß:** Klein zeigt die Insel Cover und Pegel neben der Notch. Groß zeigt sie Cover,
  App, Titel, Interpret, die Tasten Zurück, Wiedergabe/Pause und Weiter sowie einen dünnen
  Fortschrittsbalken mit Zeiten wie im Kontrollzentrum.
- **Eine Sache groß (0.5):** Groß steht immer nur eine Sache, 460 pt breit. Oben eine Leiste mit
  Symbolen für alles, was läuft; ein Klick zeigt diese Sache groß. Dazu Timer, Spiegel und eine
  **Stecknadel**, die die Insel offen hält (dann durchscheinend). Auf Wunsch: **Wiedergabe immer
  groß** (andere Sachen als Glas-Karte über dem Player), **Wiedergabe-Knöpfe in der kleinen Insel**
  und **Aufklappen als Band** (seitlich breit in Menüleisten-Höhe statt nach unten).
- **Zwischenablage (0.11, ab Werk aus):** Verlauf mit Suche in einer Seitenansicht am Rand (⌃<, Kürzel wählbar, rechts/links/unten), Kacheln in der großen Insel, Sammlungen, Angeheftetes, Titel. Dazu ein **Tresor** mit Touch ID und ein Import aus PastePal. ⇧ nimmt reinen Text. **Ab 0.12** fügen Doppelklick, ↵ und ⌘1–9 direkt in die vordere App ein. Das ⌘V drückt das Hilfsprogramm „Gnotchi Mitteilungen“ (nur mit eingeschalteten Mitteilungen), Gnotchi selbst bleibt ohne Bedienungshilfen. Ohne Hilfsprogramm wird nur kopiert. **Ab 0.13** erkennt Gnotchi kopierte API-Schlüssel und Tokens (rund 40 Dienste) und zeigt sie nur verdeckt. Lose Einträge sind 5 Minuten nach der letzten Nutzung weg, in Sammlungen wird nichts gelöscht. **Ab 0.14** klappt die Zwischenablage aus der Notch herunter (⌃<, nochmal ⌃< für die große Ansicht am Rand), mit Karten je Inhalt: Farbcodes als Farbfläche, Bilder randlos, Links mit Domain, Stern und Papierkorb beim Drüberfahren. **Ab 0.15** zeigt die Leertaste eine große Vorschau der markierten Karte.
- **Nächster Termin aus [Kalli](https://github.com/miwixyz/Kalli) (0.5):** 15 Minuten vor Beginn
  mit Uhrzeit und Restzeit, ein Klick öffnet den Apple Kalender (ab Kalli 0.12.0).
- **Timer (0.5):** 5, 10, 15, 25 Minuten oder eigene Zeit, mit Pause und Stopp. Bei Ablauf pulsiert
  die Insel orange bis zum Klick, der Ton (wählbar) wiederholt sich höchstens eine Minute.
- **Spiegel (0.5):** dein Kamerabild gespiegelt in der großen Insel, etwa vor einem Anruf. Die
  Kamera läuft nur, solange der Spiegel zu sehen ist.
- **Mitteilungen und Anrufe (0.6):** Mitteilungen ausgewählter Apps erscheinen in der Notch statt oben rechts,
  mit ihren Knöpfen (z. B. „Erledigt“); Klick öffnet die App. Anrufe mit Annehmen, Ablehnen und im Gespräch
  Auflegen. Ein eigenes Hilfsprogramm mit Bedienungshilfen-Freigabe liest Apples Banner; Gnotchi selbst bleibt
  ohne. Ab Werk aus.
- **Claude Code in der Notch (0.9):** laufende Claude-Code-Sitzungen mit „arbeitet“, „wartet auf Erlaubnis“
  (Werkzeug + Befehl) und „fertig“ (Anfang der Antwort); Klick holt das Programm der Sitzung nach vorn. Nur
  Anzeige, keine Entscheidung. Eigene Hooks in `~/.claude/settings.json`, byte-genau ein- und austragbar. Ab Werk aus.
- **Anrufe ohne Apples Fenster (0.9):** Rot lehnt ab und Apples Anruf-Fenster ist weg, **Mitlesen** schickt auf die
  Mailbox mit Abschrift. Beim Klingeln ist Apples Fenster versteckt.
- **Ungelesen-Zahlen (0.9):** Dock-Abzeichen der ausgewählten Apps im Band und in der großen Insel, Klick öffnet die
  App; ohne Musik auch als Summe in der kleinen Insel. Nur Ziffern, nie Text. Ab Werk aus.
- **Dateiablage (0.8):** Datei zur Notch ziehen → „Hier ablegen“ → später woanders herausziehen. Reihe unter der
  großen Insel bzw. direkt im Band; volle Ablage mit Im Finder zeigen, Teilen, AirDrop und ZIP (optional AES-256 mit
  Passwort). Verweise statt Kopien, ohne Freigabe. Ab 0.9.1 auch Fotos direkt aus der Fotos-App, ab 0.9.2
  Anhänge aus Outlook und aus Gmail im Browser (jeweils als Kopie, die beim Entfernen gelöscht wird).
  Ab 0.10 kopiert das Rausziehen immer (das Original bleibt).
- **Bildschirmfotos in die Ablage (0.10):** Jedes neue Bildschirmfoto von macOS oder CleanShot (auch in iCloud Drive)
  landet von selbst in der Ablage und lässt sich gleich in Chat, Mail oder Dokument ziehen. Ab Werk aus; Fotos auf dem
  Schreibtisch brauchen einmal macOS' Zugriffsfreigabe, iCloud-Fotos erscheinen bis zu einer Minute verzögert.
  **Ab 0.16** verschwinden sie nach 5, 15, 30 oder 60 Minuten wieder aus der Ablage (oder nie, ab Werk 30); die Datei
  bleibt liegen.
- **Ruhe-Insel (0.8):** Läuft nichts, bleibt die kleine Insel bei Wetter/Ablage mit Temperatur bzw. Anzahl.
  **Ab 0.16** sieht sie ohne Notch dann aus wie die Menüleiste (Glas statt Schwarz) und wird erst bei Musik, Timer,
  Termin, Anruf, Diktat, Mitteilung, Mikrofon oder Kamera schwarz. Abschaltbar, ab Werk an.
- **Wetter (0.7):** Wetter-Symbol in der großen Insel → Temperatur, Zustand, 8 Stunden, 7 Tage, Feuchte, Wind,
  UV, Druck, Sonnenauf-/-untergang auf einem Himmel-Farbverlauf. Ort in den Einstellungen suchen, °C/°F. Daten:
  [Open-Meteo.com](https://open-meteo.com) (CC BY 4.0). Ab Werk aus.
- **Spulen:** im Balken klicken oder ziehen, gespult wird beim Loslassen. In Spotify auch dann,
  wenn die Musik über Spotify Connect auf einem anderen Gerät läuft. Ohne Dauer (Livestream) ist
  der Balken gesperrt.
- **Welche App spielt:** Symbol und Name der Quell-App über dem Titel, klein ein Abzeichen am
  Cover. Der Name kommt aus der installierten App, nie von einer Website.
- **Wo die Musik spielt:** „Auf anderem Gerät“ (etwa Spotify Connect), bei AirPlay oder Bluetooth
  der Name des Geräts. Bei anderem Gerät und AirPlay zeigt die kleine Insel einen Lautsprecher
  statt des Pegels.
- **Aufklappen nach** einer wählbaren Verzögerung (Sofort, 0,3 s, 0,6 s, 1 s; ab Werk 0,6 s).
  Mit gedrückter Maustaste geht die Insel nicht auf, etwa wenn du ein Fenster an den oberen Rand
  ziehst.
- **Rechtsklick** (oder Ctrl-Klick) auf die Insel öffnet ein Menü mit „Einstellungen …“ und
  „Hilfe …“.
- **Zweite Notch-App:** Zeichnet eine andere App ebenfalls über die Notch (z. B. NotchNook), steht
  oben im Menü und in den Einstellungen ein Hinweis mit ihrem Namen.
- **Unaufdringlich:** Die Insel verschwindet 5 Sekunden nach dem Pausieren, und sie blendet sich
  auf einem Bildschirm aus, solange dort eine App im Vollbild läuft. Jeder Bildschirm hat seine
  eigene Insel.
- **Audio-Ausgang wählen:** Oben rechts in der großen Insel sitzt das Ausgabe-Symbol. Ein Klick
  zeigt alle Ausgabegeräte; die Auswahl setzt den Ausgang von macOS (wie Systemeinstellungen → Ton).
- **Kopfhörer-Hinweis:** Wechselt der Ton auf Bluetooth-Kopfhörer oder zurück, zeigt die Insel
  3 Sekunden Gerät und „Verbunden“ bzw. „Kopfhörer getrennt“.
- **Mikrofon und Kamera:** Solange eine App sie nutzt, sitzt ein oranger bzw. grüner Punkt an der
  Insel. Groß steht dort, welche App das Mikrofon nutzt (bei der Kamera nennt macOS keine App).
- **Tippi-Diktat:** Rotes Mikrofon mit dem echten Pegel, danach „wandelt um“. Tippi blendet seine
  eigene Anzeige aus, solange Gnotchi das zeigt. Vorrang vor Musik, auch über Vollbild-Apps.
- **Tippis Live-Vorschau:** Ist sie in Tippi an, klappt die Insel auf und zeigt die letzten zwei Zeilen
  des Diktats. Ohne Verbindung zu Gnotchi zeigt Tippi seine eigene Anzeige.
- **Qotti-Kontingent:** Kurze Warnung, wenn das 5-Stunden-Limit von Claude oder Codex 80 % und 95 %
  erreicht oder Claude drosselt; in der großen Insel „Claude 42 % · Codex 17 %“ über der Musik, im Band daneben
  (ab Qotti 1.5.0).
- **Live-Aktivitäten:** Läuft mehr als eine Sache gleichzeitig, wechselt die kleine Insel alle
  4 Sekunden zwischen Musik, Kopfhörern, Claude und Updates. Mit der Maus darauf bleibt sie stehen.
  Tippi-Aufnahme und kurze Hinweise haben Vorrang.
- **Kopfhörer-Aktivität:** Solange der Ton über Bluetooth läuft, zeigt die Insel ein
  Kopfhörer-Symbol, ohne Notch auch den Namen.
- **Updates der App-Familie:** Meldet Tippi, Kalli, Qotti oder Seam ein bereites Update, steht es
  in der Insel, bis es installiert ist. Ein Klick öffnet die App bei ihrem Update-Fenster.
  Gnotchis eigenes Update erscheint dort auch. Die Apps brauchen dafür eine Version, die das
  unterstützt, Kalli kommt zuerst.
- **Neuer Titel:** Beginnt ein neuer Titel, wird die Insel 3 Sekunden breiter und zeigt Titel und
  Interpret.
- **Medienfilter:** Jede Wiedergabe-App hat einen eigenen Schalter, zum Beispiel Spotify an und
  Safari aus.
- **Nicht hängen bleiben:** Scheitert die Prüfung des Medien-Adapters beim Start (etwa direkt
  nach dem Einschalten), versucht Gnotchi es nach 5 s, 30 s, 2 Minuten und dann alle 5 Minuten
  erneut und schaltet von selbst zurück.
- Menüleisten-Symbol mit Timer, Einstellungen, Hilfe, Update-Suche und Beenden. Einstellungen: „Musik in
  der Notch“, „Kopfhörer-Hinweis“, „Mikrofon & Kamera anzeigen“, „Tippi-Aufnahme anzeigen“,
  „Qotti-Kontingent anzeigen“ (alle ab Werk an), „Aufklappen nach“, „Bei Anmeldung starten“.
  Bereich „Live-Aktivitäten“: „Rotation“, „Kopfhörer-Aktivität“, „Updates der App-Familie“ (alle
  ab Werk an) und der Medienfilter.

## Installieren

[Neueste Version laden](https://github.com/miwixyz/Gnotchi/releases/latest): ein ZIP mit
Developer-ID-Signatur, von Apple notarisiert. Auspacken und nach *Programme* ziehen, kein Xcode nötig.

Wer im Terminal installiert, nimmt `ditto`, nicht `unzip`. `unzip` zerstört die Metadaten des
signierten Programms, macOS hält es dann für beschädigt:

```bash
ditto -x -k Gnotchi-0.1.0.zip . && mv Gnotchi.app /Applications/ && open /Applications/Gnotchi.app
```

## Aktualisieren

Gnotchi aktualisiert sich über [Sparkle](https://sparkle-project.org). Es fragt einmal, ob es
selbst nach Updates suchen darf. Ein gefundenes Update steht oben im Menü, ohne Mitteilung.
Gnotchi installiert nur Updates, die mit Michaels Schlüssel signiert sind. Auch die Update-Liste
(Appcast) selbst muss signiert sein.

## Berechtigungen und warum

| Was macOS fragt | Wann | Wozu |
|---|---|---|
| **Automation für Spotify** | beim ersten Spulen in Spotify | Spotify spult per AppleScript. Über Spotify Connect springt die Zeit sonst zurück (gemessen 18.10.2026). |
| **Automation für Musik** | nur, wenn der Rückfall greift (siehe unten) | Steuern und Titel lesen ohne den systemweiten Weg |
| **Kamera** | beim ersten Klick auf den Spiegel (0.5) | Nur der Spiegel. Das Bild geht direkt auf den Bildschirm, nie in eine Datei ([G27](docs/SECURE-DESIGN.md)) |
| **Bedienungshilfen für „Gnotchi Mitteilungen“** | wenn du „Mitteilungen in der Notch“ einschaltest (0.6) | Nur das Hilfsprogramm liest Apples Mitteilungsbanner, versteckt sie und löst auf deinen Klick deren Knöpfe aus. Ab 0.12 drückt es auf deinen Doppelklick in der Zwischenablage ⌘V, keine andere Taste. Gnotchi selbst bekommt keine Freigabe ([G28](docs/SECURE-DESIGN.md), [G42](docs/SECURE-DESIGN.md)) |
| **Touch ID bzw. Mac-Passwort** | beim Öffnen des Tresors in der Zwischenablage (0.11) | Gibt den Tresor-Schlüssel im Schlüsselbund für fünf Minuten frei ([G39](docs/SECURE-DESIGN.md)) |
| **„Aus anderen Apps einfügen“** | nur, falls macOS beim Mitlesen der Zwischenablage nachfragt (0.11; auf macOS 27.0.1 fragte es nicht, gemessen 24.10.2026) | Verlauf der Zwischenablage ([G37](docs/SECURE-DESIGN.md)) |
| **Anmeldeobjekt** | wenn du „Bei Anmeldung starten“ einschaltest und macOS eine Freigabe verlangt | Start nach dem Anmelden. Die Einstellungen zeigen dann „macOS wartet auf deine Freigabe“ mit einem Knopf dorthin. |

Was Gnotchi **nicht** braucht: keine Bedienungshilfen (die bekommt nur das Hilfsprogramm, siehe oben), keine Bildschirmaufnahme, kein Mikrofon,
kein Bluetooth (die Kamera nur für den Spiegel, siehe oben). Ob eine App Mikrofon oder Kamera nutzt, liest es über Core Audio und
CoreMediaIO ohne Freigabe (gemessen 20.10.2026: Kamera ohne Anfrage, beim Mikrofon nur eine stille
Vorabprüfung von macOS, kein Dialog).
Fürs Vollbild und für die Erkennung einer zweiten Notch-App liest es aus der Fensterliste nur
Ebene, Lage und Prozessnummer, keine Fenstertitel.

Widerrufen: Systemeinstellungen → Datenschutz & Sicherheit → Automation bzw. Kamera → Gnotchi.

## Datenschutz

- **Nichts verlässt den Mac** außer der Update-Prüfung (Sparkle, bei GitHub) und – nur bei eingeschaltetem
  Wetter – der Abfrage bei Open-Meteo: dorthin gehen nur der gewählte Ort (gerundete Koordinaten) und bei der
  Ortssuche der eingetippte Name, nie dein Standort ([G31](docs/SECURE-DESIGN.md)).
- Titel, Interpret und Cover bleiben im Arbeitsspeicher. Gnotchi speichert sie nicht, schreibt sie
  nicht ins Protokoll und lädt keine Cover-Adressen aus dem Netz. Ins Protokoll kommen nur
  Zustandswechsel und die Kennung der Quell-App.
- Gespeichert werden nur die Einstellungen, auf diesem Mac.
- Für „Wo die Musik spielt“ liest Gnotchi über Core Audio nur, **ob** eine App gerade Ton ausgibt,
  und vom Ausgabegerät Art und Namen. Es nimmt nichts auf und hört nichts mit. Der Pegel bei
  Musik ist eine Animation, kein Messwert; beim Tippi-Diktat kommt er von Tippi.
- **Mikrofon/Kamera:** Gnotchi fragt nur ab, **ob** aufgenommen wird und welcher Prozess es ist.
  Den App-Namen nimmt es aus dem installierten Programm; er steht nur in der Insel, nie im Protokoll.
- **Tippi:** Gnotchi empfängt über die Systemmeldungen von macOS nur „nimmt auf“, „wandelt um“ und
  den Pegel, nie Text. Jedes Programm auf dem Mac kann diese Meldung mitlesen; sie verrät nur, dass
  gerade diktiert wird. Nachrichten mit anderem Aufbau verwirft Gnotchi
  ([G17](docs/SECURE-DESIGN.md)).
- **Live-Vorschau-Text:** kommt nie über diese Systemmeldung, sondern über einen lokalen Socket in
  `~/Library/Application Support/Gnotchi`, nur für dich lesbar. Beide Apps prüfen vorher die
  Developer-ID-Signatur der anderen; andere Programme werden abgewiesen. Der Text wird weder
  gespeichert noch protokolliert ([G21](docs/SECURE-DESIGN.md)).
- **Qotti:** nur Prozente, Zeitpunkt der Zurücksetzung und Zustand über die Systemmeldungen, nie
  Konto, E-Mail oder Plan; Qotti sendet nur, solange ein signiertes Gnotchi läuft ([G22](docs/SECURE-DESIGN.md)).
- **Updates der App-Familie:** Die Meldung enthält nur das Kürzel der App und die Versionsnummer
  ([G23](docs/SECURE-DESIGN.md)). Auf deinen Klick öffnet Gnotchi nur die echte App, nachdem es ihre
  Signatur geprüft hat ([G24](docs/SECURE-DESIGN.md)).
- **Medienfilter:** gespeichert werden nur die Kennungen der ausgeschalteten Apps, keine Titel und
  keine Zeitpunkte ([G25](docs/SECURE-DESIGN.md)).
- **Termine aus Kalli:** über einen eigenen lokalen Socket (`kalli.sock`), beide Apps prüfen vorher
  die Developer-ID-Signatur der anderen. Nur Titel, Beginn und Kalenderfarbe des nächsten Termins;
  nie gespeichert, nie protokolliert, bei Beginn vergessen ([G26](docs/SECURE-DESIGN.md)).
- **Spiegel:** Das Kamerabild geht nur in die Vorschau auf dem Bildschirm, nie in Gnotchis eigenen
  Code, eine Datei oder das Netz. Die Kamera läuft nur, solange der Spiegel sichtbar ist
  ([G27](docs/SECURE-DESIGN.md)).
- **Dateiablage:** gespeichert werden nur Lesezeichen (Ort der Datei) in `~/Library/Application Support/Gnotchi/ablage.json`
  (nur für dich lesbar). Nichts wird geöffnet oder ausgeführt, entfernen löscht nie etwas – außer Gnotchis eigener
  Kopie eines Fotos oder Mail-Anhangs, den die liefernde App erst beim Ablegen schreibt (`Ablage-Kopien/`, nur für
  dich lesbar, ab 0.9.1/0.9.2). ZIP im Programm
  (libarchive), Passwort nie gespeichert ([G32](docs/SECURE-DESIGN.md)).
- **Bildschirmfotos (ab 0.10, ab Werk aus):** Gnotchi fragt Spotlight nur nach dem Merkmal „Bildschirmfoto“, liest
  nie den Bildinhalt und legt nur einen Verweis ab; im Protokoll stehen nur Zahlen, nie Dateinamen
  ([G36](docs/SECURE-DESIGN.md)).
- **Zwischenablage (ab 0.11, ab Werk aus):** Gnotchi liest die Zwischenablage nur, wenn sich ihr Zähler ändert, und nur eine feste Liste von Formaten. Vertraulich markierte Kopien und ausgeschlossene Apps bleiben draußen. Jedes Feld ist mit AES-256-GCM verschlüsselt, der Schlüssel liegt im Schutzklassen-Schlüsselbund in Gnotchis eigener Gruppe. Der Tresor-Schlüssel ist an Touch ID gebunden. HTML und RTF werden nie dargestellt. Kein Netz, keine Inhalte im Protokoll ([G37–G41](docs/SECURE-DESIGN.md)). Einfügen (ab 0.12): Gnotchi schickt dem geprüften Hilfsprogramm nur „einfügen“, ohne Inhalt; es drückt darauf genau ⌘V, sonst nichts ([G42](docs/SECURE-DESIGN.md)). Geheimnisse (ab 0.13): feste Muster, nur die ganze Kopie, verdeckt; automatisch gelöscht werden nur lose, erkannte Einträge nach 5 Minuten, die Art steht nie im Protokoll ([G43](docs/SECURE-DESIGN.md)).
- **Mitteilungen und Anrufe:** Das Hilfsprogramm liest nur Apples Mitteilungszentrale und gibt nur Mitteilungen
  der ausgewählten Apps an Gnotchi weiter, über einen eigenen lokalen Socket (`notify.sock`), nachdem beide die
  Developer-ID-Signatur des anderen geprüft haben. Texte nie gespeichert, nie protokolliert; gespeichert wird
  nur die App-Liste. Knöpfe wirken nur auf deinen Klick ([G28–G30](docs/SECURE-DESIGN.md)).
- **Claude Code:** Das Hook-Programm „Gnotchi Claude“ schickt nur Projektname, Status, Werkzeug, gekürzten Befehl und
  gekürzte Antwort über `claude.sock`, nachdem es Gnotchis Signatur geprüft hat (Gnotchi prüft umgekehrt genauso). Nie
  Eingabe, Verlauf oder Dateiinhalte, nie gespeichert oder protokolliert, nie eine Entscheidung an Claude Code
  ([G34](docs/SECURE-DESIGN.md)). `~/.claude/settings.json` ändert Gnotchi nur byte-genau, mit Sicherung
  ([G35](docs/SECURE-DESIGN.md)).
- **Ungelesen-Zahlen:** Das Hilfsprogramm liest im Dock nur die Zahl am Symbol der ausgewählten Apps
  ([G33](docs/SECURE-DESIGN.md)).
- Keine echten Hördaten im Quellcode: ein Gate prüft das bei jedem Commit und Release
  ([G16](docs/SECURE-DESIGN.md)).

## So funktioniert es

Apple bietet keine öffentliche Schnittstelle für „was spielt gerade“ quer über alle Apps. Gnotchi
nutzt wie Boring Notch oder Cyclop den Medien-Adapter
[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter): Der systemeigene
`/usr/bin/perl` lädt ein kleines Framework aus Gnotchis Programmpaket, das an Apples
`MediaRemote.framework` kommt und die Wiedergabe als Zeilenstrom meldet.

- Vor **jedem** Start prüft Gnotchi die Signatur des eigenen Programmpakets, samt Kennung und
  Team. Ist sie ungültig, startet der Adapter nicht.
- Perl startet ohne Shell, mit festen Argumenten und fester Umgebung.
- Der Strom gilt als nicht vertrauenswürdig, denn jede Website kann Titel setzen: Zeilen und Texte
  sind begrenzt, Steuer- und Richtungszeichen fliegen raus, Cover werden begrenzt dekodiert.
- **Rückfall:** Startet der Adapter nicht (Signatur, macOS sperrt den Zugriff, wiederholter
  Absturz), liest und steuert Gnotchi Spotify und Musik direkt per AppleScript. Andere Quellen
  zeigt es dann nicht.

Alle Entscheidungen mit Begründung: [docs/SECURE-DESIGN.md](docs/SECURE-DESIGN.md).

## Grenzen

- **Eine Quelle:** Gnotchi zeigt, was macOS gerade als aktuelle Wiedergabe führt. Spielen zwei
  Apps gleichzeitig, entscheidet macOS, welche es ist.
- **Apple kann den Perl-Weg schließen.** Dann bleibt der Rückfall für Spotify und Musik.
- **Nur eine Notch-App:** Zwei Apps über der Notch überdecken sich. Gnotchi meldet das, beenden
  musst du eine davon selbst.
- **Kamera ohne App-Namen:** macOS meldet nur, dass eine Kamera läuft, nicht für wen.
- **Ausgabegeräte:** Die Liste zeigt, was macOS als Audiogerät führt. AirPlay-Lautsprecher, die erst
  im Kontrollzentrum auftauchen, sind nicht getestet.
- **Tippi-Diktat** braucht eine Tippi-Version, die die Meldung sendet. Ältere zeigen weiter ihre
  eigene Anzeige.
- Ein maximiertes Fenster bei ausgeblendetem Dock hat auf Notch-Bildschirmen dieselbe Lage wie
  Vollbild. Die Insel blendet sich dann ebenfalls aus.

## Bauen und testen

```bash
make gen       # Projekt erzeugen (xcodegen), CHANGELOG ins Bundle spiegeln, Package.resolved einspielen
make build     # bauen, unsigniert
make test      # Tests (signiert, der Test-Host ist die App)
make render    # nur die Insel-Bilder nach build/render/ (Sichtprüfung ohne App-Start)
make lint      # Datenschutz-Gate + SwiftLint strikt (inkl. „keine Bedienungshilfen“, „Kindprozess nur im Adapter“)
make hooks     # einmal je Klon: Datenschutz-Gate vor jedem Commit
make profile   # einmal je Mac: Developer-ID-Profil anlegen lassen (Schlüsselbund-Gruppe ab 0.11)
make dev       # Testversion mit Developer ID signiert unter /tmp starten (scripts/dev-signed.sh)
make install   # signierte Testfassung nach /Applications
make release   # notarisiertes ZIP, GitHub-Release, signierter Appcast
```

Voraussetzungen: macOS 27, Xcode, `xcodegen`, `swiftlint`. Der Adapter startet nur aus einem mit
Michaels Team signierten Programmpaket (`make dev`, `make install`). Ein unsignierter `make build`
zeigt deshalb höchstens Spotify und Musik über den Rückfall.

Bilder der Insel ohne App-Start: `make render` (nach `build/render/`, alte Bilder werden ersetzt).
Erfundene Titel, Platzhalter-Cover, rote Linie = Hardware-Notch.

## Aufbau

| Pfad | Was |
|---|---|
| `Gnotchi/App/GnotchiApp.swift` | Einstieg, Menüleiste, Fenster, Start und Stopp der Notch |
| `Gnotchi/Island/` | Insel: Panels je Bildschirm, Lage, Ansicht, Rechtsklick-Menü, zweite Notch-App |
| `Gnotchi/Media/MediaAdapter.swift` | Kindprozess `/usr/bin/perl` + Adapter, Neustart, Waisen |
| `Gnotchi/Media/NowPlayingInfo.swift` | Adapter-Zeile → bereinigter Wiedergabe-Zustand |
| `Gnotchi/Media/NowPlayingModel.swift` | Was die Insel zeigt, Steuerbefehle, Rückfall, Wiedergabeweg |
| `Gnotchi/Media/AppleScriptSource.swift` | Rückfall und Spotify-Spulen per AppleScript (feste Skripte) |
| `Gnotchi/Media/AudioRoute.swift` | Wiedergabeweg aus Core Audio, nur lesen |
| `Gnotchi/Media/BundleIntegrity.swift` | Signatur + Team des eigenen Programmpakets vor jedem Start |
| `Gnotchi/UI/` | Einstellungen, Menü, Hilfe-Fenster, Markdown-Darstellung |
| `Gnotchi/Resources/` | `HILFE.md`, `CHANGELOG.md` (Spiegel), Lizenzen, Schrift, Info.plist |
| `Vendor/mediaremote-adapter/` | eingespielter Adapter (BSD-3), siehe `VENDOR.md` |
| `scripts/` | Signieren, Release, Doku-Gate, Berechtigungs-Gate, Datenschutz-Gate |
| `.githooks/` | Pre-Commit-Hook (Datenschutz-Gate), eingeschaltet per `make hooks` |
| `docs/` | Sicherheitsentwurf, One-Pager, Bilder |
| `specs/` | Spezifikation und Umsetzungsplan |
| `spike/` | erfundenes Beispiel des Adapter-Stroms, Regeln in [spike/README.md](spike/README.md) |

## Sicherheit

Bedrohungsmodell, Entscheidungen G1 bis G16 und offene Punkte vor dem ersten Release:
[docs/SECURE-DESIGN.md](docs/SECURE-DESIGN.md).

## Fremdcode

| Komponente | Wofür | Lizenz |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0 | Updates | MIT |
| [Plus Jakarta Sans](https://github.com/tokotype/PlusJakartaSans) | Schrift der Einstellungen | SIL OFL 1.1 |
| [Neonderthaw](https://github.com/googlefonts/neonderthaw) 1.010 | Neonschrift am Plattenspieler (ab 0.17) | SIL OFL 1.1 |
| [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), Commit `0e82bf1` | Wiedergabe-Daten | BSD-3-Clause |

Lizenztexte: [THIRD-PARTY-LICENSES](Gnotchi/Resources/THIRD-PARTY-LICENSES.md), in der App unter
„Hilfe …“ → „Fremdcode“.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
