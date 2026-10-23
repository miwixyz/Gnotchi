# Gnotchi – Hilfe

## Was ist Gnotchi

Gnotchi macht aus der Notch deines MacBook eine kleine Insel für Musik und Videos. Du siehst, was
gerade läuft, und steuerst es, ohne die App zu suchen. Auf Bildschirmen ohne Notch erscheint
dieselbe Insel als schwarze Pille oben in der Mitte. Jeder Bildschirm hat seine eigene.

Gnotchi zeigt alles, was macOS als laufende Wiedergabe meldet: Spotify, Musik und Browser wie
Safari, Edge oder Helium, auch Videos.

Außerdem zeigt die Insel, wenn du mit Tippi diktierst, wenn eine App Mikrofon oder Kamera nutzt,
wenn Kopfhörer verbunden sind und wenn für eine App der Familie (Tippi, Kalli, Qotti, Seam, Gnotchi)
ein Update bereitliegt. In der großen Insel wählst du, wo der Ton herauskommt.

## Die Insel

**Klein:** Läuft etwas, zeigt die Insel links neben der Notch das Cover und rechts einen kleinen
Pegel. Der Pegel ist nur eine Animation, Gnotchi misst dafür keinen Ton.

**Groß:** Bleib mit der Maus auf der kleinen Insel, dann geht sie auf. Du siehst Cover, App, Titel,
Interpret, die Tasten und den Fortschritt. Fährst du wieder weg, wird sie klein.

Wie lange du darauf bleiben musst, stellst du unter „Aufklappen nach“ ein. Ab Werk sind es
0,6 Sekunden, damit ein flüchtiges Überfahren nichts auslöst. Hältst du die Maustaste gedrückt,
etwa beim Ziehen eines Fensters an den oberen Rand, geht die Insel nicht auf.

Die Insel verschwindet, wenn nichts mehr läuft, und 5 Sekunden nach dem Pausieren. Läuft auf einem
Bildschirm eine App im Vollbild, blendet sie sich dort aus.

## Live-Aktivitäten

Läuft mehr als eine Sache gleichzeitig, etwa Musik und Kopfhörer, wechselt die kleine Insel alle
4 Sekunden zwischen ihnen. Die Reihenfolge ist immer gleich: Musik, Kopfhörer, Claude, Updates. Bleibst du mit
der Maus auf der Insel, wechselt sie nicht weiter. Gibt es nur eine Aktivität, bleibt sie stehen.

- **Musik:** Cover und Pegel wie gewohnt. Beginnt ein neuer Titel, wird die Insel 3 Sekunden breiter und zeigt Titel und Interpret. Pausieren und Weiterspielen lösen das nicht aus.
- **Kopfhörer:** Solange der Ton über Bluetooth läuft, zeigt die Insel ein Kopfhörer-Symbol, ohne Notch auch den Namen.
- **Claude:** Arbeitet eine Claude-Code-Sitzung oder wartet sie auf deine Erlaubnis, zeigt die Insel ✦ mit einem Punkt (orange arbeitet, gelb wartet), ohne Notch auch den Projektnamen. Siehe „Claude Code“.
- **Updates:** Meldet eine App der Familie ein bereites Update, zeigt die Insel ihr Symbol, ohne Notch auch „Kalli 0.11.0 bereit“. Das bleibt so, bis das Update installiert ist. Ein Klick öffnet die App bei ihrem Update-Fenster. Gnotchi öffnet dabei nur die echte, von Michael signierte App.

In der großen Insel stehen alle Aktivitäten untereinander, Updates mit „Öffnen“. Mit Notch passt neben
ihr kein Text, deshalb siehst du Namen und Versionen dort erst in der großen Insel.

Tippi-Aufnahme und kurze Hinweise wechseln nicht mit, sie haben Vorrang. Die Rotation lässt sich
ausschalten, dann zeigt die Insel immer die erste Aktivität.

**Medienfilter:** In den Einstellungen unter „Live-Aktivitäten“ steht jede Wiedergabe-App mit eigenem
Schalter, zum Beispiel Spotify an und Safari aus. Ist eine App aus, erscheint ihre Wiedergabe nie in der
Insel. Die Liste zeigt bekannte Apps, die auf deinem Mac installiert sind, und jede App, die seit dem
Start von Gnotchi etwas abgespielt hat.

## Steuern und Spulen

In der großen Insel stehen rechts die Tasten **Zurück**, **Wiedergabe/Pause** und **Weiter**.

Darunter liegt der Fortschrittsbalken mit der gespielten Zeit links und der Gesamtzeit rechts.
Klick an eine Stelle oder zieh den Punkt, gespult wird beim Loslassen. In Spotify klappt das auch,
wenn die Musik über Spotify Connect auf einem Lautsprecher läuft. Hat ein Titel keine Gesamtzeit,
etwa ein Livestream, ist der Balken gesperrt.

## Welche App spielt

Über dem Titel stehen Symbol und Name der App, zum Beispiel „Spotify“, „Musik“ oder „Safari“. In
der kleinen Insel sitzt das Symbol als winziges Abzeichen am Cover. Den Namen nimmt Gnotchi aus der
installierten App, nie von einer Website.

## Auf anderem Gerät, AirPlay, Bluetooth

Oben rechts in der großen Insel steht, wo der Ton herauskommt:

- **Auf anderem Gerät:** Die App spielt, aber nicht auf diesem Mac, zum Beispiel Spotify Connect auf einem externen Lautsprecher.
- **AirPlay:** der Name des AirPlay-Lautsprechers.
- **Bluetooth:** der Name der Kopfhörer oder Box.

Spielt der Mac selbst, steht dort nur das Ausgabe-Symbol. Bei anderem Gerät und AirPlay zeigt die
kleine Insel einen Lautsprecher statt des Pegels. Gnotchi fragt dafür nur ab, ob eine App gerade Ton
ausgibt. Es hört nichts mit.

## Ausgabe wählen

Klick in der großen Insel oben rechts auf das Ausgabe-Symbol (bzw. auf den Gerätenamen). Es öffnet
sich eine Liste aller Ausgabegeräte, das aktuelle mit Häkchen. Wählst du eines, spielt der Mac ab
sofort darüber, genau wie unter Systemeinstellungen → Ton. Gnotchi ändert den Ausgang nur, wenn du
klickst.

## Kopfhörer

Wechselt der Ton auf Bluetooth-Kopfhörer, etwa weil du AirPods verbindest, zeigt die Insel 3 Sekunden
lang ihren Namen und „Verbunden“. Wechselt er zurück, steht dort das neue Gerät und „Kopfhörer
getrennt“. Schaltest du selbst über die Insel um, kommt kein Hinweis. Abschalten: Einstellung
„Kopfhörer-Hinweis“.

Solange der Ton über Bluetooth läuft, bleibt außerdem die Kopfhörer-Aktivität in der Insel (siehe
„Live-Aktivitäten“). Abschalten: Einstellung „Kopfhörer-Aktivität“. Den Akkustand zeigt Gnotchi nicht,
denn macOS gibt ihn nur mit einer eigenen Freigabe heraus.

## Mikrofon und Kamera

Nutzt eine App das Mikrofon, sitzt ein **oranger** Punkt an der Insel, bei der Kamera ein **grüner**,
dieselben Farben wie in der Menüleiste von macOS. Mit Notch stehen die Punkte neben ihr, ohne Notch
steht in der Pille „Mikrofon“ oder „Kamera“. Läuft gleichzeitig Musik, ersetzen die Punkte den Pegel.

Fährst du darüber, steht da, **welche App** das Mikrofon nutzt. Bei der Kamera sagt macOS nicht,
welche App es ist, deshalb steht dort nur „Kamera“. Nimmt eine Webseite in Safari auf, steht
„Webseite“. Gnotchi hört und sieht dabei nichts: Es fragt nur ab, ob aufgenommen wird.

## Tippi-Diktat

Diktierst du mit Tippi, zeigt die Insel ein rotes Mikrofon und den Pegel deiner Stimme, ohne Notch
auch „nimmt auf“ und die Laufzeit. Danach steht „wandelt um“, bis der Text eingefügt ist. Tippi
blendet seine eigene Anzeige dann aus. Die Aufnahme hat Vorrang vor Musik und Hinweisen, klappt
nicht auf und ist auch über Apps im Vollbild zu sehen.

Ist in Tippi die Live-Vorschau eingeschaltet, klappt die Insel beim Diktat auf und zeigt die letzten
zwei Zeilen deines Texts, während du sprichst. Ältere Wörter laufen vorne raus. Klappt die Verbindung
zu Tippi nicht, zeigt Tippi wie gewohnt seine eigene Anzeige mit dem Text.

Das klappt mit Tippi ab der Version, die Gnotchi unterstützt (steht in Tippis Änderungen). Schaltest du
„Tippi-Aufnahme anzeigen“ aus, zeigt Tippi wieder seine eigene Anzeige.

## Qotti-Kontingent

Läuft Qotti, warnt die Insel kurz, wenn das 5-Stunden-Limit von Claude oder Codex 80 % und 95 %
erreicht, und wenn Claude drosselt. Darunter steht, wann das Limit zurückgesetzt wird. Jede Stufe
warnt einmal und erst wieder, nachdem der Wert darunter gefallen ist. Hast du die große Insel gerade
offen, bleibt sie offen und die Warnung entfällt. In der großen Insel steht über der Musik
„Claude 42 % · Codex 17 %“, im Band rechts daneben. Hört Qotti 5 Minuten lang auf zu melden, verschwinden die Werte.

Das klappt ab Qotti 1.5.0.

## Große Insel

Fährst du mit der Maus auf die kleine Insel, klappt sie auf. Groß zeigt sie **eine Sache**: dieselbe, die
gerade klein zu sehen ist. Oben steht eine Leiste mit kleinen Symbolen für alles, was gerade läuft (Musik,
Termin, Timer, Kopfhörer, Updates). Ein Klick auf ein Symbol zeigt diese Sache groß. Rechts in der Leiste
stehen das Timer-Symbol, der Spiegel, die Stecknadel und die Punkte für Mikrofon und Kamera.

- **Stecknadel:** Die Insel bleibt offen, auch wenn die Maus weggeht, und wird durchscheinend. Ein zweiter Klick löst sie wieder.
- **Wiedergabe immer groß** (Einstellungen): Die Musik bleibt immer die große Ansicht. Ein Klick auf Termin, Timer oder Update legt diese Sache als Glas-Karte über Cover und Titel, die Knöpfe rechts bleiben frei.
- **Wiedergabe-Knöpfe in der kleinen Insel** (Einstellungen): Pause/Wiedergabe und Weiter stehen dauerhaft in der kleinen Insel.
- **Aufklappen als Band** (Einstellungen): Die Insel wird nicht nach unten groß, sondern seitlich zu einem Band in Menüleisten-Höhe. Links die Musik, rechts im Wechsel Wiedergabe, Termin und Timer. Ein Klick links öffnet die große Insel.

## Termine aus Kalli

Läuft [Kalli](https://github.com/miwixyz/Kalli) ab Version 0.12.0, zeigt die Insel deinen nächsten Termin
ab 15 Minuten vor Beginn: Uhrzeit, Titel und wie lange es noch dauert. Bei Beginn verschwindet er. Ein
Klick öffnet den Apple Kalender. Ganztägige Termine und Erinnerungen erscheinen nicht. Schalter: „Termine
aus Kalli anzeigen“.

## Timer

Menüleisten-Symbol → **Timer** → 5, 10, 15 oder 25 Minuten oder **Eigene Zeit …** (1 bis 180 Minuten).
Oder in der großen Insel auf das Timer-Symbol klicken: Dort stehen dieselben Zeiten und **− 30 +** für eine
eigene Zeit. Der Timer läuft in der Insel mit, groß mit Pause und Stopp. Es läuft immer nur ein Timer; ein
neuer ersetzt den alten.

Ist die Zeit um, **pulsiert die Insel orange, bis du sie anklickst**, und der Ton wiederholt sich höchstens
eine Minute lang. Das geht auch über Apps im Vollbild. Schalter „Timer-Ablauf bis Klick anzeigen“ aus: nur
ein kurzer Hinweis und ein Ton. Den Ton wählst du unter **Timer → Ton** oder in den Einstellungen.

## Spiegel

Das Kamera-Symbol in der Leiste der großen Insel zeigt dein Kamerabild, gespiegelt, zum Beispiel vor einem
Anruf. Die Kamera läuft nur, solange der Spiegel zu sehen ist: Klappt die Insel zu oder wählst du ein anderes
Symbol, ist sie sofort aus. Beim ersten Mal fragt macOS nach der Kamera-Freigabe. Schalter: „Spiegel in
der Notch“.

## Mitteilungen und Anrufe

Einstellungen → **Mitteilungen in der Notch** (ab Werk aus). Beim Einschalten startet Gnotchi das Hilfsprogramm
**„Gnotchi Mitteilungen“** und macOS fragt nach der Bedienungshilfen-Freigabe für dieses Programm. Erlaube sie
unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → „Gnotchi Mitteilungen“. Gnotchi selbst
bekommt keine Freigabe.

- **Welche Apps:** In der Liste darunter hakst du die Apps an, deren Mitteilungen in die Notch dürfen. Beim
  ersten Einschalten sind Nachrichten-Apps vorgeschlagen. Weitere über **App hinzufügen …**. Alle anderen
  Mitteilungen bleiben, wo sie waren.
- **Eine Mitteilung** klappt die Insel auf: App, Titel, Text und die Knöpfe der Mitteilung. Klick auf die
  Mitteilung öffnet die App, ein Knopf macht genau das, was er bei Apple auch macht, × schließt sie. Solange die
  Maus darauf ist, bleibt sie stehen. Danach liegt sie wie gewohnt in der Mitteilungszentrale.
- **Antworten** geht nicht in der Notch, dafür öffnest du die App.
- **Anrufe** (Schalter „Anrufe in der Notch“): grün Annehmen, rot Ablehnen, dazwischen **Mitlesen**. Rot schickt
  den Anrufer auf die Mailbox, und Apples Anruf-Fenster ist danach weg. Mitlesen schickt ihn ebenfalls auf die
  Mailbox, du liest aber in Apples Fenster mit; in der Notch stehen dann „Mitlesen beenden“ und Annehmen. Im
  Gespräch gibt es rot Auflegen, und Apples Gesprächsleiste bleibt mit Stumm und Ziffernblock sichtbar. Solange es
  klingelt, ist Apples Anruf-Fenster versteckt. Die Knöpfe werden eine halbe Sekunde nach dem Erscheinen klickbar.
  Ganz ohne Mailbox auflegen kann macOS nicht, auch nicht in Apples Fenster.
- **Ungelesen-Zahlen** (Schalter „Ungelesen-Zahlen zeigen“, ab Werk aus): Die Zahlen auf den Dock-Symbolen der
  ausgewählten Apps stehen im Band und in der großen Insel, ein Klick öffnet die App. Läuft keine Musik, zeigt die
  kleine Insel die Summe („Zähler auch in der kleinen Insel“). Es zählen nur Apps, die im Dock liegen.
- Während die Tippi-Aufnahme läuft oder die große Insel offen ist, wartet eine Mitteilung. So lange bleibt Apples
  Banner stehen, es geht nichts verloren.

## Claude Code

Aktivitäten → **Claude Code in der Notch** (ab Werk aus). Gnotchi zeigt dann deine laufenden Claude-Code-Sitzungen,
egal ob im Terminal, in der Claude-App oder in einem Programm wie Obsidian:

- **Arbeitet** (orange), **wartet auf Erlaubnis** (gelb, mit Werkzeug und Befehl, etwa „Bash – git push“) oder
  **fertig** (grün, mit dem Anfang der Antwort). Ist eine Antwort fertig, klappt die Insel kurz auf.
- In der großen Insel stehen bis zu zwei Sitzungen, im Band die neueste. Ein **Klick** holt das Programm nach vorn,
  in dem die Sitzung läuft. Den einzelnen Tab oder Chat kann Gnotchi nicht auswählen.
- **Erlauben oder ablehnen** geht nicht in der Notch, das machst du in der Sitzung. Gnotchi gibt Claude Code nie
  eine Antwort.
- Fertige Sitzungen verschwinden nach 30 Minuten.

Beim Einschalten trägt Gnotchi eigene Einträge („Hooks“) in `~/.claude/settings.json` ein und legt vorher eine
Sicherung `settings.json.gnotchi-backup` daneben. Deine übrigen Einstellungen bleiben Zeichen für Zeichen gleich.
Kann Gnotchi das nicht garantieren, ändert es nichts und sagt dir in den Einstellungen, warum. Ausschalten nimmt
genau diese Einträge wieder heraus. Ist Gnotchi beendet, laufen die Einträge ins Leere und bremsen nichts.

## Dateiablage

Zieh eine Datei (oder einen Ordner, auch mehrere) zur Notch. Die Insel wird zum Feld **„Hier ablegen“**, dort
loslassen. Die Datei bleibt, wo sie war; die Ablage merkt sich nur den Ort. Dann wechselst du in Ruhe App oder
Space und ziehst sie dort wieder heraus.

- **Rausziehen:** aus der Reihe unter der großen Insel oder – bei „Aufklappen als: Band“ – direkt aus dem Band
  (die kleinen Symbole neben dem Titel). Danach verschwindet sie aus der Ablage (abschaltbar).
- **Volle Ablage:** Klick auf das Ablage-Symbol. Rechtsklick auf eine Datei: Im Finder zeigen, Teilen …, AirDrop,
  Entfernen. Unten für alle: Teilen, AirDrop, ZIP, ZIP mit Passwort, Leeren.
- **ZIP** landet als „Ablage.zip“ in deinem Downloads-Ordner und auch in der Ablage. **Mit Passwort** ist es mit
  AES-256 verschlüsselt; öffnen lässt es sich mit Keka, The Unarchiver oder 7-Zip, nicht per Doppelklick auf dem Mac.
- **Bildschirmfotos automatisch (ab 0.10):** Einstellungen → Ablage → „Bildschirmfotos automatisch ablegen“. Jedes neue
  Bildschirmfoto von macOS oder CleanShot erscheint von selbst in der Ablage und bleibt dort, bis du es herausziehst.
  Videos nicht. Fotos aus iCloud Drive brauchen manchmal bis zu einer Minute. Liegen sie auf dem Schreibtisch, fragt
  macOS einmal nach dem Zugriff; ohne „Erlauben“ bleiben sie draußen.
- **Rausziehen kopiert** (ab 0.10): Das Original bleibt, wo es war, auch wenn du in den Finder ziehst.
- **Fotos aus der Fotos-App, Anhänge aus Outlook und aus Gmail im Browser** (und andere Apps, die ihre Datei erst
  beim Ablegen schreiben) landen als **Kopie** in Gnotchis eigenem Ordner. Entfernen oder Leeren löscht diese Kopie,
  nie dein Foto in der Mediathek oder den Anhang in der Mail.
- Bei allen anderen Dateien löschen Entfernen und Leeren nie etwas. Höchstens 50 Einträge.

## Wetter

Einstellungen → **Wetter in der Notch** einschalten (ab Werk aus), dann unter „Stadt suchen“ deinen Ort eingeben,
**Suchen**, und den richtigen Treffer anklicken (es gibt z. B. mehrere „München“). °C oder °F wählst du darunter.

In der großen Insel steht dann ein Wetter-Symbol. Ein Klick zeigt das Wetter groß: Temperatur, Zustand, gefühlt,
Höchst- und Tiefstwert, die nächsten 8 Stunden, 7 Tage, Luftfeuchte, Wind, UV, Luftdruck, Sonnenauf- und
-untergang. Gnotchi fragt beim Einschalten, alle 30 Minuten und nach dem Aufwachen nach. Ohne Internet bleibt der
letzte Stand bis zu 3 Stunden stehen.

Die Daten kommen von **Open-Meteo.com** (Lizenz CC BY 4.0). Gesendet wird nur der gewählte Ort (gerundet), nie
dein Standort.

## Einstellungen

- **Musik in der Notch:** zeigt Musik und Videos in der Insel. Ab Werk an. Aus heißt: kein Abfragen der Wiedergabe. Die Insel bleibt für die anderen Anzeigen da, solange eine davon an ist.
- **Kopfhörer-Hinweis**, **Mikrofon & Kamera anzeigen**, **Tippi-Aufnahme anzeigen**, **Qotti-Kontingent anzeigen**, **Termine aus Kalli anzeigen:** jeweils ab Werk an. Sind alle Schalter aus, gibt es keine Insel.
- **Aufklappen als:** Insel (ab Werk) oder Band.
- **Wiedergabe-Knöpfe in der kleinen Insel**, **Wiedergabe immer groß:** ab Werk aus (siehe „Große Insel“).
- **Spiegel in der Notch**, **Timer-Ablauf bis Klick anzeigen:** ab Werk an. **Timer-Ton:** ab Werk „Glass“, oder „Kein Ton“.
- **Aufklappen nach:** Sofort, 0,3 s, 0,6 s oder 1 s. So lange musst du mit der Maus auf der kleinen Insel bleiben, bis sie aufgeht.
- **Live-Aktivitäten:** „Rotation“, „Kopfhörer-Aktivität“ und „Updates der App-Familie“, jeweils ab Werk an. Darunter der Medienfilter mit einem Schalter je Wiedergabe-App.
- **Claude Code in der Notch** (Aktivitäten), **Ungelesen-Zahlen zeigen** (Mitteilungen): ab Werk aus. **Zähler auch in der kleinen Insel:** ab Werk an.
- **Bei Anmeldung starten:** Gnotchi startet nach dem Anmelden.
- **Nach Updates suchen …:** sucht sofort nach einer neuen Version.

## Menü und Rechtsklick

Gnotchi hat ein Symbol in der Menüleiste. Ein Klick darauf öffnet das Menü mit „Timer“, „Einstellungen …“,
„Hilfe …“, „Nach Updates suchen …“ und „Beenden“. Läuft keine Musik, gibt es keine Insel, dann
erreichst du Gnotchi über dieses Symbol.

Ein Rechtsklick auf die Insel (oder Ctrl-Klick) öffnet ein kleines Menü mit „Einstellungen …“ und
„Hilfe …“. Die Insel klappt dabei nicht auf.

## Berechtigungen

Gnotchi braucht **keine Bedienungshilfen**, keine Bildschirmaufnahme, kein Mikrofon und kein Bluetooth. Auch
die Dateiablage braucht keine Freigabe. Ausnahme: Wer „Bildschirmfotos automatisch ablegen“ einschaltet und Fotos auf
dem Schreibtisch speichert, erlaubt Gnotchi einmal den Zugriff auf den Schreibtisch.
Nur wer „Mitteilungen in der Notch“ einschaltet, erteilt die Bedienungshilfen dem eigenen Hilfsprogramm
„Gnotchi Mitteilungen“, nicht Gnotchi. Dasselbe Hilfsprogramm liest für die Ungelesen-Zahlen die Abzeichen im Dock.
„Claude Code in der Notch“ braucht keine Freigabe, Gnotchi trägt nur Einträge in `~/.claude/settings.json` ein.
Ob eine App Mikrofon oder Kamera nutzt, erfährt es ohne eigene Freigabe.

macOS fragt höchstens in diesen Fällen:

- **Kamera:** erst beim ersten Klick auf den Spiegel. Lehnst du ab, zeigt der Spiegel „Kamera nicht erlaubt“ mit einem Knopf zu den Einstellungen. Ändern: Systemeinstellungen → Datenschutz & Sicherheit → Kamera → Gnotchi.
- **Spotify steuern:** beim ersten Spulen in Spotify. Gnotchi spult Spotify direkt, sonst springt die Zeit über Spotify Connect zurück.
- **Musik steuern:** nur, wenn Gnotchi auf den Ersatzweg umschalten muss (siehe „Wenn etwas nicht geht“).
- **Anmeldeobjekt:** wenn du „Bei Anmeldung starten“ einschaltest. Steht in den Einstellungen „macOS wartet auf deine Freigabe“, klick auf „Freigeben …“ und schalte Gnotchi unter Systemeinstellungen → Allgemein → Anmeldeobjekte ein.

Ändern oder widerrufen: Systemeinstellungen → Datenschutz & Sicherheit → Automation → Gnotchi.
Lehnst du Spotify ab, spult Gnotchi trotzdem, dann aber auf dem Weg, der über Spotify Connect
nicht wirkt.

## Datenschutz

- Was du hörst und siehst, bleibt auf deinem Mac. Titel, Interpret und Cover liegen nur im Arbeitsspeicher und sind nach dem Beenden weg.
- Gnotchi speichert sie nicht, schreibt sie nicht ins Protokoll und schickt sie nirgendwohin.
- Gespeichert werden nur deine Einstellungen.
- Gnotchi liest keine Fenstertitel und keine Inhalte anderer Apps und nimmt keinen Ton auf.
- Welche App Mikrofon oder Kamera nutzt, steht nur in der Insel, nie im Protokoll.
- Von Tippi erfährt Gnotchi über eine Systemmeldung „nimmt auf“, „wandelt um“ und den Pegel. Diese Meldung kann jedes Programm auf deinem Mac mitlesen; sie verrät nur, dass du gerade diktierst, nie was.
- Den Text der Live-Vorschau bekommt Gnotchi auf einem eigenen, geschützten Weg: Beide Apps prüfen vorher die Signatur der anderen, andere Programme werden abgewiesen. Der Text steht nur in der Insel, wird nicht gespeichert, nicht protokolliert und ist weg, sobald das Diktat endet.
- Von Qotti kommen nur die Prozente, der Zeitpunkt der Zurücksetzung und „ok/veraltet/gedrosselt“, nie Konto, E-Mail oder Plan. Auch diese Meldung kann jedes Programm auf deinem Mac mitlesen.
- Update-Meldungen der Familien-Apps enthalten nur den App-Namen und die Versionsnummer. Auch sie kann jedes Programm mitlesen. Gnotchi zeigt daraus nur Namen und Version und speichert sie nicht.
- Der Medienfilter speichert nur die Kennungen der ausgeschalteten Apps, keine Titel und keine Zeitpunkte.
- Deinen nächsten Termin bekommt Gnotchi von Kalli auf demselben geschützten Weg wie Tippis Live-Text: Beide Apps prüfen vorher die Signatur der anderen. Kalli schickt nur Titel, Beginn und Kalenderfarbe des Termins, den seine Menüleiste ohnehin zeigt. Gnotchi speichert ihn nicht, protokolliert ihn nicht und vergisst ihn bei Beginn.
- Das Kamerabild des Spiegels geht direkt auf den Bildschirm. Gnotchi speichert es nicht, verarbeitet es nicht und schickt es nirgendwohin.
- Der Timer lebt nur im Arbeitsspeicher.
- Mitteilungen liest nur das Hilfsprogramm „Gnotchi Mitteilungen“, und nur die der Apps, die du ausgewählt hast,
  gehen an Gnotchi weiter. Beide prüfen vorher die Signatur des anderen. Texte werden nicht gespeichert, nicht
  protokolliert und sind weg, sobald die Mitteilung verschwindet. Gespeichert wird nur die App-Liste.
- Von Claude Code bekommt Gnotchi nur Projektname, Status, Werkzeug, einen gekürzten Befehl und den gekürzten
  Anfang der Antwort, über einen eigenen Weg, auf dem beide Seiten die Signatur prüfen. Nie deine Eingabe, nie den
  Verlauf, nie Dateiinhalte. Nichts davon wird gespeichert oder protokolliert.
- Für die Ungelesen-Zahlen liest das Hilfsprogramm nur die Zahl am Dock-Symbol der ausgewählten Apps, nie deren Text.
- Die Dateiablage speichert nur, wo die Dateien liegen (nur für dich lesbar), nie ihren Inhalt. Ausnahme: Fotos aus
  der Fotos-App und Mail-Anhänge aus Outlook oder Gmail liegen als Kopie in Gnotchis Ordner (nur für dich lesbar),
  bis du sie aus der Ablage entfernst.
  ZIP-Passwörter werden nicht gespeichert.
- Ins Internet geht Gnotchi nur, um nach Updates zu suchen, und – wenn du das Wetter einschaltest – zu
  Open-Meteo.com. Dorthin geht nur der gewählte Ort, gerundet auf etwa einen Kilometer; Open-Meteo speichert laut
  eigenen Angaben IP-Adresse und Koordinaten bis zu 90 Tage in seinen Serverprotokollen und gibt sie nicht weiter.

## Nur eine Notch-App gleichzeitig

Zwei Apps, die über die Notch zeichnen (zum Beispiel NotchNook, Boring Notch oder Alcove),
überdecken sich gegenseitig. Erkennt Gnotchi eine solche App, steht oben im Menü und in den
Einstellungen ein Hinweis mit ihrem Namen. Beende dann eine der beiden oder schalte deren
Notch-Anzeige aus. Der Hinweis verschwindet von selbst, sobald die andere App weg ist.

Gnotchi prüft das nur, solange die Insel zu sehen ist, und liest dafür nur Lage und Ebene der
Fenster und den Namen der App, keine Fenstertitel.

## Wenn etwas nicht geht

**Die Insel erscheint nicht.** Ist „Musik in der Notch“ an? Ist die App im Medienfilter
ausgeschaltet? Läuft gerade etwas, oder ist es länger als 5 Sekunden pausiert? Läuft auf diesem Bildschirm eine App im Vollbild? Ein maximiertes Fenster
bei ausgeblendetem Dock zählt dabei wie Vollbild.

Hinweise in den Einstellungen und was sie bedeuten:

- **„… – nur Spotify und Musik“:** Gnotchi kann die Wiedergabe nicht für alle Apps lesen und nutzt den Ersatzweg. Dann zeigt und steuert es nur Spotify und Musik. Der Teil vor dem Strich sagt, warum:
- **„macOS blockiert den Zugriff auf die Wiedergabe“:** macOS lässt den Weg gerade nicht zu, etwa kurz nach dem Einschalten des Macs oder nach einem System-Update. Gnotchi versucht es selbst erneut (nach 5 und 30 Sekunden, nach 2 Minuten, danach alle 5 Minuten) und schaltet von allein zurück, sobald es klappt. Bis dahin funktionieren Spotify und Musik über den Ersatzweg.
- **„Signatur des Programmpakets ungültig …“** oder **„Adapter fehlt im Programmpaket“:** Gnotchi ist verändert oder beschädigt. Lade es neu und ersetze es in *Programme*.
- **„Adapter bricht wiederholt ab“:** Schalte „Musik in der Notch“ aus und wieder ein oder starte Gnotchi neu.
- **„Automation für … nicht erlaubt“:** Du hast Gnotchi verboten, Spotify oder Musik zu steuern. Erlaube es unter Systemeinstellungen → Datenschutz & Sicherheit → Automation.
- **„… zeichnet ebenfalls über die Notch“:** siehe „Nur eine Notch-App gleichzeitig“.
- **„macOS meldet einen unbekannten Autostart-Status“:** Gnotchi kann „Bei Anmeldung starten“ gerade nicht lesen. Prüfe es unter Systemeinstellungen → Allgemein → Anmeldeobjekte.

**Spulen geht nicht.** Bei Livestreams ohne Gesamtzeit ist der Balken gesperrt. Springt die Zeit
in Spotify zurück, hat Gnotchi vermutlich keine Erlaubnis, Spotify zu steuern (siehe
„Berechtigungen“).

**Es wird die falsche App gezeigt.** Gnotchi zeigt, was macOS gerade als laufende Wiedergabe
führt. Spielen zwei Apps gleichzeitig, entscheidet macOS.

## Updates

„Nach Updates suchen …“ steht im Menü und in den Einstellungen. Beim ersten Mal fragt Gnotchi, ob
es selbst nach Updates suchen darf. Findet es eines, steht es oben im Menü, ohne Mitteilung.
Gnotchi installiert nur Updates, die mit Michaels Schlüssel signiert sind. Ist „Updates der App-Familie“
an, erscheint ein gefundenes Update auch in der Insel. Ein Klick darauf öffnet das Update-Fenster.

Was sich geändert hat, steht hier im Fenster unter „Änderungen“.
