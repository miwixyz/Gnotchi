# Gnotchi – Hilfe

## Was ist Gnotchi

Gnotchi macht aus der Notch deines MacBook eine kleine Insel für Musik und Videos. Du siehst, was
gerade läuft, und steuerst es, ohne die App zu suchen. Auf Bildschirmen ohne Notch erscheint
dieselbe Insel als Pille oben in der Mitte. Jeder Bildschirm hat seine eigene; welche Bildschirme eine bekommen, wählst du unter Einstellungen → Allgemein → Aussehen (ab 0.46, ab zwei Bildschirmen). Zeigt die Pille nur Wetter, Ablage oder
Ungelesen-Zahlen, sieht sie aus wie die Menüleiste. Sobald etwas läuft, wird sie schwarz (ab 0.16, abschaltbar unter
Einstellungen → Allgemein → Aussehen → „Ruhige Insel ohne Notch“).

Gnotchi zeigt alles, was macOS als laufende Wiedergabe meldet: Spotify, Musik und Browser wie
Safari, Edge oder Helium, auch Videos.

Außerdem zeigt die Insel, wenn du mit Tippi diktierst, wenn eine App Mikrofon oder Kamera nutzt,
wenn Kopfhörer verbunden sind und wenn für eine App der Familie (Tippi, Kalli, Qotti, Seam, Gnotchi)
ein Update bereitliegt. In der großen Insel wählst du, wo der Ton herauskommt.

## Die Insel

**Klein:** Läuft etwas, zeigt die Insel links neben der Notch das Cover und rechts einen kleinen
Pegel. Der Pegel ist nur eine Animation, Gnotchi misst dafür keinen Ton.

**Groß:** Bleib mit der Maus auf der kleinen Insel, dann geht die große Insel auf. Sie schwebt ab 0.22
knapp unter der Notch bzw. Pille, die kleine Insel bleibt dabei stehen. Du siehst Cover, App, Titel,
Interpret, die Tasten und den Fortschritt. Fährst du wieder weg, schließt sie sich.

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
Bei Spotify und Musik steht davor **Shuffle** (ab 0.17): hell hinterlegt mit Punkt darunter heißt an, gedimmt heißt aus.
Der erste Klick kann die Frage von macOS auslösen, ob Gnotchi die App steuern darf.

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

## Musik auf dem Schreibtisch

Ab 0.26 ist das ein echtes macOS-Widget, das aussieht wie Uhr und Kalender – gedämpft, wenn ein Fenster davor liegt, farbig, wenn der Schreibtisch aktiv ist. Einschalten unter Einstellungen → Wiedergabe → „Cover und Titel auf dem Schreibtisch“ (ab Werk aus), Darstellung „Widget“. Dann Rechtsklick auf den Schreibtisch → „Widgets bearbeiten …“ → „Gnotchi“ und eine Größe auf den Schreibtisch ziehen: Klein zeigt Cover und Titel, Mittel und Groß zusätzlich Zurück, Wiedergabe/Pause und Weiter. Das Widget zeigt, was gerade spielt oder pausiert, und nach 10 Minuten Pause „Keine Wiedergabe“. Ist ein Fenster davor, zeigt macOS das Cover in Graustufen. Ein Klick aufs Cover holt die Musik-App nicht nach vorne – das kann ein Widget nicht.

**Widget zeigt nur graue Platzhalter?** Das kann nach einem Gnotchi-Update passieren, auch wenn Musik läuft. Gnotchi liefert die Daten, aber der Widget-Dienst von macOS findet sie nicht mehr. Abhilfe: Terminal öffnen und `killall chronod` eingeben. macOS startet den Dienst sofort neu, alle Widgets sind kurz leer und zeigen danach wieder Cover und Titel. Es geht nichts verloren.

**Plattenspieler (ab 0.17):** Unter Einstellungen → Wiedergabe → „Darstellung“ wählst du statt des Widgets den Plattenspieler. Er steht mittig, etwa ein Drittel des Bildschirms groß, links daneben die Hülle, darunter Titel und Interpret. Die Platte dreht sich, solange Musik läuft. Der Tonarm fährt beim Start auf die Platte, wandert im Lauf des Titels nach innen und geht bei Pause in die Ablage. Dahinter liegt ein Farbverlauf aus den Farben des Covers, unter deinen Schreibtisch-Symbolen, die bleiben klickbar. Fährst du über den Plattenspieler, erscheinen Shuffle, Zurück, Wiedergabe/Pause und Weiter. Ein Klick auf die Hülle holt die App nach vorne. Weitere Schalter:
- **Bildschirm:** auf welchem Bildschirm er steht, ab Werk der Hauptbildschirm. Ist der gewählte nicht angeschlossen, steht er auf dem Hauptbildschirm.
- **Neonschrift „Now Playing“:** leuchtender Schriftzug in der Coverfarbe über dem Plattenspieler, ab Werk an.
- **Start/Stopp-Knopf bedienen** (ab 0.17.2): Ein Klick auf den großen Knopf unten links am Plattenspieler startet oder hält die Musik an, der Tonarm fährt dann von selbst. Ab Werk aus.
Ecke, Größe und Verschieben gelten nur für die Karte.

## Musik auf dem Sperrbildschirm

Ab 0.21 zeigt Gnotchi auf Wunsch die laufende Musik auch bei gesperrtem Mac: eine kleine Karte mit Cover, Titel, Interpret, Fortschritt und den Knöpfen Zurück, Wiedergabe/Pause und Weiter. Sie steht mittig zwischen der Uhr und der Anmeldung. Ein Klick aufs Cover zeigt es groß, ein zweiter Klick oder 30 Sekunden ohne Bedienung bringen die kleine Karte zurück. Die Karte ist da, solange Musik spielt oder pausiert, und verschwindet nach 10 Minuten Pause. Sobald du entsperrst, ist sie weg.

Einschalten unter Einstellungen → Wiedergabe → „Auf dem Sperrbildschirm zeigen“ (ab Werk aus). **Achtung:** Jeder, der vor deinem gesperrten Mac sitzt, sieht dann, was läuft, und kann die Wiedergabe steuern. Mehr geht nicht: Die Karte öffnet keine App, kein Menü und nimmt keine Eingabe an. Mit „Titel verbergen“ zeigt sie nur eine Musiknote und die Knöpfe, kein Cover, keinen Text.

Gnotchi nutzt dafür eine nicht offizielle Funktion von macOS, nur so bleibt ein Fenster über dem Sperrbildschirm sichtbar. Fehlt sie in einer macOS-Version, ist der Schalter ausgegraut („Unter dieser macOS-Version nicht verfügbar“).

## Ausgabe wählen

Klick in der großen Insel oben rechts auf das Ausgabe-Symbol (bzw. auf den Gerätenamen). Es öffnet
sich eine Liste aller Ausgabegeräte, das aktuelle mit Häkchen. Wählst du eines, spielt der Mac ab
sofort darüber, genau wie unter Systemeinstellungen → Ton. Gnotchi ändert den Ausgang nur, wenn du
klickst.

## Stream Deck

Mit einem Elgato Stream Deck steuerst du Lautstärke, Wiedergabe und Lautsprecher je App, dazu Ausgabe und Mikrofon des ganzen Macs. Das geht auf jedem Stream Deck mit Tasten; mit den Drehreglern eines Stream Deck + am bequemsten.

1. Einstellungen → **Audio** → ganz unten **„Steuerung über Stream Deck“** einschalten.
2. **„Plugin installieren“** klicken. Stream Deck fragt, ob es das Plugin „Gnotchi“ installieren soll.
3. Stream Deck bietet beim Installieren das fertige Profil **„Gnotchi“** an (Stream Deck + und Neo), mit allen Funktionen. Oder du ziehst die Aktionen aus der Gruppe **„Gnotchi“** selbst auf Regler oder Tasten und wählst rechts die App.

**App-Lautstärke** (Regler oder Taste)
- Drehen: lauter oder leiser
- Drücken: stumm, noch einmal drücken: alte Lautstärke zurück
- Gedrückt halten und drehen: nächster (rechts) oder vorheriger Titel (links)
- Auf die Leiste tippen: Play/Pause
- Die Leiste zeigt App, Prozent und den laufenden Titel; lange Titel laufen durch.
- Auf einer **Taste** (jedes Stream Deck): rechts unter „Taste“ Stumm, Lauter oder Leiser wählen; je Druck 5 %.

**Wiedergabe** (Taste): Play/Pause, Weiter oder Zurück, je Taste einstellbar.

**YouTube im Browser** (Taste „Wiedergabe“ mit der App „Safari“, „Chrome“, „Helium“ oder „Edge“, ab Werk aus; bis 0.44 nur Helium)
- Spotify läuft und daneben YouTube im Browser? Dann schaltet die Taste gezielt nur den YouTube-Tab dieses Browsers, und die Leiste zeigt seinen Titel.
- Einschalten: Einstellungen → Stream Deck → **„YouTube in Browsern gezielt steuern“**. Im Browser muss **„JavaScript von Apple Events“** eingeschaltet sein: in Edge **Ansicht → Entwickler → JavaScript von Apple Events zulassen** (so gemessen), in Chrome vermutlich genauso, in Helium **Darstellung → Entwickler**, in Safari **Einstellungen → Entwickler** (vorher unter Erweitert das Entwickeln-Menü einschalten; Wortlaut vermutet). macOS fragt je Browser beim ersten Mal, ob Gnotchi ihn steuern darf.
- Achtung: Mit dem Schalter in einem Browser kann in diesem Browser jedes Programm mit Steuerungsfreigabe JavaScript in allen Tabs ausführen, auch in angemeldeten. Gnotchi selbst führt es nur in YouTube-Tabs aus, fragt nur Browser ab, die laufen und auf dem Deck liegen, und schaltet den Schalter im Browser nie selbst.
- Mehrere YouTube-Tabs: Ein Druck pausiert alle Videos, die spielen; der nächste startet das, das zuletzt lief.
- Mehrere Browser gleichzeitig: Jede Taste gehört dem Browser, dessen App sie gewählt hat. Gnotchi fragt alle zusammen höchstens einmal pro Sekunde ab, reihum, nie zwei gleichzeitig.
- **Search und Firefox lassen sich nicht so steuern.** Search erlaubt Skripten nur das Lesen von Adresse und Titel (kein JavaScript, kein Play/Pause), Firefox hat keine Skriptschnittstelle. Für beide gilt der bisherige Weg: nur, solange sie die aktive Quelle sind.
- Läuft nichts von YouTube im gewählten Browser, gilt ebenfalls der bisherige Weg.

**Cover auf dem Deck** (ab Werk aus)
- Einschalten: Einstellungen → Stream Deck → **„Cover auf dem Deck“**, danach einmal **„Plugin installieren“**.
- Die Wiedergabe-Taste zeigt das Cover der App, die gerade spielt, bei YouTube im Browser das Vorschaubild. Oben rechts steht, ob sie spielt oder pausiert.
- Das Bild geht an die Stream-Deck-App von Elgato, auch private Cover. Gnotchi verkleinert es vorher und lädt nichts aus dem Netz.

**App-Lautsprecher** (Regler oder Taste, ab 0.36): auf welchem Gerät die App spielt.
- Drehen: Gerät vorwählen, die Leiste zeigt es mit „· drücken“
- Drücken: übernehmen
- Auf die Leiste tippen: zurück aufs eigene Gerät der App
- Auf einer Taste: jedes Drücken schaltet zum nächsten Gerät
- Zuerst stehen deine Ausgabe-Favoriten aus dem Mixer, dann die übrigen Geräte.
- **Teams** (neu): Teams hat keine Einstellung „Systemstandard“ und folgt deshalb der Taste „Ausgabe“ nicht. Mit „App-Lautsprecher“ und der App „Teams“ legst du den Ton eines Anrufs trotzdem auf die AirPods. Das geht nur, während Teams Ton ausgibt (im Anruf), und nur für den Ton: Das Mikrofon stellst du in Teams selbst um.

**Ausgabe** und **Mikrofon** (Taste oder Regler, neu): Gerät für den ganzen Mac, z. B. AirPods.
- Rechts unter „Gerät“ ein festes Gerät wählen: Ein Druck stellt den Mac darauf um. Die Taste leuchtet, solange es eingestellt ist, sonst ist sie gedimmt.
- Für AirPods am besten zwei Tasten: eine „Ausgabe“ und eine „Mikrofon“, beide auf die AirPods. Sonst hörst du über die AirPods und sprichst ins Mikrofon des Macs.
- Ist das Gerät nicht verbunden (AirPods im Etui), steht „nicht da“ auf der Taste; ein Druck zeigt ein Warnzeichen.
- „Nächstes je Druck“: jedes Drücken schaltet reihum weiter, die Taste zeigt das eingestellte Gerät.
- Am Regler: drehen wählt vor, drücken übernimmt, auf die Leiste tippen stellt das feste Gerät ein.
- Zur Auswahl stehen höchstens 8 Geräte, zuerst deine Favoriten aus dem Mixer.
- Apps mit eigener Geräteauswahl behalten ihr Gerät. **Teams** auf dem Mac bietet keine Einstellung „Systemstandard“ und bleibt bei dem Gerät, das dort gewählt ist.

Gut zu wissen:
- Spotify und Musik gehen immer. Browser und andere Apps lassen sich nur steuern, solange sie gerade spielen.
- Für die Lautstärke von Browsern und für „App-Lautsprecher“ muss oben im Reiter **„Lautstärke je App“** an sein, und Gnotchi braucht die Freigabe für Systemaudio (siehe Berechtigungen).
- Auf der Leiste steht der Titel. Dafür bekommt die Stream-Deck-App auf deinem Mac Titel und Interpret, kein Cover.
- Gnotchi nimmt Befehle nur vom eigenen Plugin an, und nur, wenn die Stream-Deck-App es gestartet hat.

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

## Tippi-Gerät

Hast du Tippis Schreibtischgerät (ESP32 mit Tippi-Firmware ab 0.10), zeigt es auf der Seite „Musik“,
was gerade läuft: Titel, Interpret und App. Die Tasten dort steuern die Wiedergabe und die Lautstärke des
Macs. Einschalten unter Einstellungen → Aktivitäten → „Tippi-Gerät“, dann den Schlüssel eintragen, der
auch im Gerät steht, und „Speichern“. Darunter steht, ob das Gerät erreichbar ist („Verbunden“).
Gnotchi meldet jede Sekunde, eine Taste am Gerät wirkt also nach höchstens einer Sekunde. Beim ersten
Senden fragt macOS nach dem Zugriff aufs lokale Netzwerk. Titel und Interpret gehen im Heimnetz
unverschlüsselt, aber signiert.

## Große Insel

Fährst du mit der Maus auf die kleine Insel, klappt sie auf. Groß zeigt sie **eine Sache**: dieselbe, die
gerade klein zu sehen ist. Oben steht eine Leiste mit kleinen Symbolen für alles, was gerade läuft (Musik,
Termin, Timer, Kopfhörer, Updates). Ein Klick auf ein Symbol zeigt diese Sache groß. Rechts in der Leiste
stehen das Timer-Symbol, der Spiegel, die Stecknadel und die Punkte für Mikrofon und Kamera.

- **Tasten um die Insel (ab 0.28):** Die Werkzeuge sitzen als runde Glas-Tasten links, rechts und unten neben der großen Insel: Timer, Wach bleiben, Spiegel (links), Wetter, Ablage, Zwischenablage (rechts), Anheften, Einstellungen (unten). Ein Punkt an einer Taste heißt: läuft gerade. Ein Klick zeigt die Sache groß. Einstellungen → Tasten → „Tasten um die Insel“ schaltet jede Taste einzeln; ohne Tasten steht wieder die kleine Leiste. Ab Werk aus und einzeln zuschaltbar: **Mikrofon stumm** (rot, wenn stumm; erscheint, solange eine App das Mikrofon nutzt, oder immer auf Wunsch; beim Beenden von Gnotchi wird wieder laut gestellt), **Bildschirmfoto** (öffnet die Screenshot-App) und **Geschwindigkeitstest** (misst bis zu 20 Sekunden gegen Apples Server und zeigt Download, Upload, Latenz).
- **Lautstärke je App (ab 0.30, ab Werk aus):** Einstellungen → Audio → „Mixer“. Dann hat im Mixer jede App mit Ton einen Regler von 0 bis 200 % (nahe 100 % rastet er ein). Dafür braucht Gnotchi die Freigabe „Audio-Aufnahme“ (macOS fragt beim ersten Verschieben). Bei 100 % spielt die App wieder direkt. Seit 0.35 merkt sich Gnotchi jeden anderen Wert je App und stellt ihn wieder ein, sobald die App erneut Ton ausgibt, auch nach einem Neustart oder Gerätewechsel (Werte bis 5 % nie von selbst). Beim Ausschalten und Beenden spielen alle Apps wieder direkt; „Gemerkte Lautstärken vergessen“ löscht die Liste. Einen Regler gibt es nur für Apps, die auf genau einem Gerät spielen. **Lautsprecher je App (ab 0.36):** Klick in der Zeile der App auf ihr Gerät und wähl ein anderes; die App spielt dann dort, alle anderen bleiben, wo sie sind. „(eigenes Gerät)“ stellt zurück. Bei Gerätewechsel, beim Ausschalten und auch nach einem Absturz von Gnotchi spielt die App wieder auf ihrem eigenen Gerät.
- **Mixer in der Insel (ab 0.30):** Die Ring-Taste „Mixer“ (rechts neben der großen Insel, ab Werk an) zeigt denselben Mixer wie das Menüleisten-Symbol groß in der Insel, in zwei Spalten. Er fragt nur ab, solange er zu sehen ist.
- **Favoriten im Mixer (ab 0.31):** Öffne das Auswahlfeld für Ausgabe oder Mikrofon und wähle unten „Favoriten …“. Mit einem Klick auf ein Gerät setzt oder entfernst du den Stern. Favoriten stehen danach als Tasten direkt unter dem Auswahlfeld; ein Klick schaltet um. Bis zu 6 je Liste. Ist ein Favorit gerade nicht angeschlossen, fehlt seine Taste, er bleibt aber gemerkt.
- **Warnton-Lautstärke (ab 0.33):** Unter „Systemtöne“ im Mixer steht ein Regler für die Lautstärke der Warn- und Hinweistöne des Macs. Das ist dieselbe Einstellung wie „Warntonlautstärke“ in Systemeinstellungen → Ton: Sie gilt dauerhaft für den ganzen Mac, nicht nur für Gnotchi, und braucht keine Freigabe. Die Zeile steht nur da, wenn mehrere Ausgabegeräte vorhanden sind.
- **Mixer und Menü (ab 0.30):** Ein Klick auf das Gnotchi-Symbol in der Menüleiste (Kopf mit Panda-Ohren, darin Notch-Pille und Play-Dreieck) öffnet ein Fenster mit zwei Reitern. **Mixer:** Ausgabegerät mit Lautstärke und Stumm, Gerät für Systemtöne, Mikrofon, darunter eine Zeile je App, die gerade Ton ausgibt, mit ihrem Ausgabegerät (AirPlay und Bluetooth farbig). Für Spotify und Musik gibt es einen Regler (nur, wenn Gnotchi sie steuern darf). **Funktionen:** Timer, Wach bleiben, Bildschirmfoto, Geschwindigkeitstest und Status. Unten Einstellungen, Hilfe, Updates und Beenden. Die Tastenkürzel ⌘, und ⌘Q des alten Menüs gibt es nicht mehr.
- **Meeting-Leiser (ab 0.29):** Einstellungen → Audio → „Meeting-Leiser“. Nutzt eine gewählte App (Teams, Zoom, FaceTime, Webex, Slack, weitere wählbar) das Mikrofon, wird Spotify und Musik auf 20, 30 oder 50 % leiser und nach dem Meeting wieder auf die alte Lautstärke gestellt. Tippi-Diktat zählt nicht. Änderst du die Lautstärke selbst, gilt dein Wert. Gnotchi fragt nie mitten im Meeting nach einer Erlaubnis: Fehlt sie für Spotify oder Musik, steht das in den Einstellungen; macOS fragt beim ersten Spulen (Spotify) bzw. beim ersten Shuffle-Klick (Musik).
- **Batterie (ab 0.28):** Einstellungen → Aktivitäten → „Batterie in der Ruhe-Insel“ zeigt Prozent und Ladezustand, solange nichts anderes läuft. Nur auf Macs mit Batterie.
- **Schwebend (ab 0.22):** Die große Insel hängt nicht mehr an der Notch, sondern schwebt mit kleinem Abstand darunter, in durchscheinendem Glas und für alle Ansichten gleich breit. Mitteilungen, Anrufe, Hinweise, das Band und das Ablagefeld beim Ziehen bleiben an der Notch.
- **Schließen:** Fährst du mit der Maus weg, schließt sie sich. Der Weg von der kleinen Insel hinüber zählt mit, und nach dem Aufgehen hast du 1,5 Sekunden Zeit, sie zu erreichen. Ein Klick daneben schließt sie sofort. Esc schließt sie, wenn du gerade im Namensfeld der Timer-Auswahl tippst.
- **Verschieben:** Zieh die große Insel an einer freien Stelle (nicht auf Knöpfen, Reglern oder Kacheln) dorthin, wo du sie haben willst. Gnotchi merkt sich die Stelle für alle Bildschirme. Wird eine Ansicht höher, wächst die Insel nach unten und bleibt im Bild. Zurück unter die Notch: Doppelklick auf eine freie Stelle, Rechtsklick → „Insel zurücksetzen“ oder nah an die alte Stelle ziehen, dort rastet sie ein.
- **Stecknadel:** Die Insel bleibt offen, auch wenn die Maus weggeht oder du daneben klickst. Ein zweiter Klick löst sie wieder.
- **Wiedergabe immer groß** (Einstellungen): Die Musik bleibt immer die große Ansicht. Ein Klick auf Termin, Timer oder Update legt diese Sache als Glas-Karte über Cover und Titel, die Knöpfe rechts bleiben frei.
- **Wiedergabe-Knöpfe in der kleinen Insel** (Einstellungen): Pause/Wiedergabe und Weiter stehen dauerhaft in der kleinen Insel.
- **Aufklappen als Band** (Einstellungen): Die Insel wird nicht nach unten groß, sondern seitlich zu einem Band in Menüleisten-Höhe. Links die Musik, rechts im Wechsel Wiedergabe, Termin und Timer. Ein Klick links öffnet die große Insel.

## Termine aus Kalli

Läuft [Kalli](https://github.com/miwixyz/Kalli) ab Version 0.12.0, zeigt die Insel deinen nächsten Termin
ab 15 Minuten vor Beginn: Uhrzeit, Titel und wie lange es noch dauert. Bei Beginn verschwindet er. Ein
Klick öffnet den Apple Kalender. Ganztägige Termine und Erinnerungen erscheinen nicht. Schalter: „Termine
aus Kalli anzeigen“.

## Schnelleingabe

Termine und Erinnerungen in Alltagssprache anlegen, ohne eine App zu öffnen. Einschalten unter Einstellungen →
Aktivitäten → **Schnelleingabe** (ab Werk aus). Dafür muss [Kalli](https://github.com/miwixyz/Kalli) laufen, in
ab Version 0.16.0: Gnotchi selbst hat keinen Zugriff auf Kalender und Erinnerungen, gespeichert wird über
Kalli.

**Öffnen:** control + option + N (änderbar in den Einstellungen) oder die Ring-Taste **Neuer Eintrag** neben der
großen Insel. Die Zeile klappt unter der Notch herunter.

**Tippen:** zum Beispiel „Zahnarzt morgen 15 Uhr“, „Teams-Call 16:30 bis 17:15“, „Rechnung zahlen bis 30.11.“ oder
„erinnere mich in 2 Stunden Tom anzurufen“. Darunter steht beim Tippen, was daraus wird: Art, Tag, Uhrzeit, Titel.

- **Mit Uhrzeit** wird es ein **Termin** im Standardkalender, 1 Stunde lang. „bis 17 Uhr“, „2 Std“ oder „30 Min“
  ändern die Dauer.
- **Ohne Uhrzeit** wird es eine **Erinnerung** in der Standardliste. „erinnere mich“, „nicht vergessen“ und
  „bis <Datum>“ machen immer eine Erinnerung. „!“ am Ende macht sie dringend.
- **Tab** wechselt zwischen Termin und Erinnerung.
- **Uhrzeiten gelten wörtlich** im 24-Stunden-Format: „7 Uhr“ ist 07:00, „halb drei“ ist 02:30. „morgens“,
  „nachmittags“, „abends“ verschieben („halb drei nachmittags“ ist 14:30). Ein gelbes **Prüfen** steht da bei
  zwei Daten, bei Uhrzeiten zwischen 0 und 6 Uhr ohne Tageszeit und bei einem Ende vor dem Beginn.
- Ein Wochentag meint den nächsten („Freitag“), eine schon vergangene Uhrzeit ohne Datum morgen.

**↵** speichert. Danach steht kurz „Gespeichert · Rückgängig (⌘Z)“, dann geht die Zeile von selbst zu. **⌘Z** in
diesem Moment nimmt den Eintrag wieder zurück. **Escape** oder ein Klick daneben schließt ohne Speichern.

Läuft Kalli nicht oder antwortet es nicht, bleibt die Zeile offen und sagt das. Bei „Kalli antwortet nicht“ kurz in
Apple Kalender nachsehen, ob der Eintrag doch angekommen ist.

## Timer

Menüleisten-Symbol → **Timer** → 5, 10, 15 oder 25 Minuten oder **Eigene Zeit oder Name …** (1 bis 180 Minuten,
dazu auf Wunsch ein Name wie „Tee“, höchstens 30 Zeichen). Der Name steht in der Insel und beim Ablauf. Solange
ein Timer läuft, steht die Restzeit neben dem Menüleisten-Symbol, pausiert mit „‖“ davor.
Oder in der großen Insel auf das Timer-Symbol klicken: Oben gibst du auf Wunsch einen Namen ein und startest mit
**Start** oder ↵. Darunter stellst du die Zeit mit **−** und **+** oder ziehst am Lineal, ganz unten stehen
1m, 5m, 10m, 25m, 45m und 1h; die helle Markierung gleitet zur gewählten Zeit. Der Timer läuft in der Insel mit, groß mit Pause und Stopp. Es läuft immer nur ein Timer; ein
neuer ersetzt den alten.

Ist die Zeit um, **pulsiert die Insel orange, bis du sie anklickst**, und der Ton wiederholt sich höchstens
eine Minute lang. Das geht auch über Apps im Vollbild. Schalter „Timer-Ablauf bis Klick anzeigen“ aus: nur
ein kurzer Hinweis und ein Ton. Den Ton wählst du unter Einstellungen → Tasten → „Timer und Spiegel“ →
**Timer-Ton**: kein Ton, **Gnotchi** (neu: der kurze „Blubb“ der App-Familie) oder ein Systemton.
Ab Werk bleibt es „Glass“. Beim Auswählen hörst du den Ton einmal zur Probe.

## Wach bleiben

Ab 0.21 hält Gnotchi den Mac auf Wunsch wach. In der großen Insel auf das **Kaffeetassen-Symbol** klicken:
- Die große Tasse schaltet ein und aus. Daneben wählst du eine Dauer: **1 Std.**, **2 Std.**, **4 Std.** oder **Bis aus**.
- **Zeitplan:** Schalter an, Tage antippen (ab Werk Mo–Fr) und unter **Uhrzeit** von – bis in 15-Minuten-Schritten wählen (ab Werk 9:00–18:00). Im Zeitfenster bleibt der Mac wach **mit Mausbewegung** (siehe unten).
- **Außerhalb:** **Normal schlafen** oder **Wach, Bildschirm aus**. Mit dem zweiten bleibt der Mac auch abends und an den freien Tagen wach, aber ohne Mausbewegung. Der Bildschirm geht dann nach der Systemzeit aus.
- **Ohne Zeitplan:** **Ohne Maus** oder **Mit Maus**. Gilt, wenn du selbst einschaltest, über die Tasse oder eine Dauer (1, 2, 4 Std., Bis aus). Ohne Maus bleibt nur der Mac wach.
- Schaltest du von Hand aus, bleibt es bis zum nächsten Wechsel aus: im Zeitfenster bis zu dessen Ende, außerhalb bis zum nächsten Fensterbeginn.
- Ohne Mausbewegung schläft der Mac nicht ein, der Bildschirm darf trotzdem nach der Systemzeit ausgehen.

**Mausbewegung (Status in Teams/Slack aktiv):** Teams, Slack und Co. zeigen dich als „abwesend“, wenn du eine Weile nichts eingibst. Mit Mausbewegung schiebt Gnotchi den Zeiger um einen Punkt hin und zurück, sobald du 4 Minuten nichts eingegeben hast, höchstens einmal pro Minute. Arbeitest du, passiert nichts. Dadurch bleibt auch der Bildschirm an. Die Bewegung macht das Hilfsprogramm „Gnotchi Mitteilungen“, es braucht dafür seine Freigabe unter **Gerätesteuerung und Datenzugriff → Bedienungshilfen**. Ist „Mitteilungen“ aus, startet Gnotchi es trotzdem, nur für die Bewegung. Mitteilungen liest es dann nicht. Bei gesperrtem Bildschirm bewegt sich nichts.

## Spiegel

Das Kamera-Symbol in der Leiste der großen Insel zeigt dein Kamerabild, gespiegelt, zum Beispiel vor einem
Anruf. Die Kamera läuft nur, solange der Spiegel zu sehen ist: Klappt die Insel zu oder wählst du ein anderes
Symbol, ist sie sofort aus. Beim ersten Mal fragt macOS nach der Kamera-Freigabe. Schalter: „Spiegel in
der Notch“.

## Mitteilungen und Anrufe

Einstellungen → **Mitteilungen in der Notch** (ab Werk aus). Beim Einschalten startet Gnotchi das Hilfsprogramm
**„Gnotchi Mitteilungen“** und macOS fragt nach der Freigabe „Gerätesteuerung und Datenzugriff“ für dieses Programm. Erlaube sie
unter Systemeinstellungen → Datenschutz & Sicherheit → Gerätesteuerung und Datenzugriff → „Gnotchi Mitteilungen“. Gnotchi selbst
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
- **Türklingel:** Ein Hinweis der Home-App (etwa „Es hat geklingelt“) öffnet beim Klick die Klingel-App, Aqara Home,
  falls installiert, sonst Home. Mit dem Schalter „Türklingel: App automatisch öffnen“ (ab Werk aus) passiert das
  sofort, ohne Klick; die App nimmt dir dann den Fokus.
- **Türklingel-Kamera:** Trägst du unter „Türklingel-Kamera“ die Adresse eines Kamera-Einzelbilds ein (JPEG oder PNG,
  `http://` oder `https://`, ohne Benutzername und Passwort in der Adresse), zeigt die Insel beim Home-Hinweis das
  Bild darunter und erneuert es alle halbe Sekunde, 30 Sekunden lang bzw. solange die Maus darauf ist. Gnotchi
  spricht kein RTSP: Die Adresse muss ein fertiges Bild liefern, z. B. ein kleiner Dienst in deinem Heimnetz, der den
  Kamera-Stream abholt. **Testen** holt ein Bild und nennt die Größe, **Insel testen** zeigt einen erfundenen
  Klingel-Hinweis mit Bild, ohne dass jemand klingelt. Kommt kein Bild, steht der Grund in der Insel (etwa
  „Kamerabild: Fehler 503“). Beim ersten Abruf fragt macOS nach dem Zugriff aufs lokale Netzwerk. Leer = aus.
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
- **Stapel (ab 0.24):** Mehrere Dateien, die du in einem Zug ablegst, werden eine Kachel mit einer Zahl daran. Ziehst
  du sie heraus, kommen alle mit. Rechtsklick → **Stapel auflösen** macht wieder einzelne Kacheln daraus.
- **Alle auf einmal (ab 0.18):** In der vollen Ablage unten links **„Alle ziehen“** greifen und ans Ziel ziehen. Erscheint
  ab zwei Dateien.
- **Vorschau (ab 0.42):** Lass den Zeiger etwa eine halbe Sekunde auf einer Bild- oder PDF-Kachel ruhen, dann zeigt Gnotchi
  die Datei groß unter der Insel. Wegbewegen schließt sie. Unter Einstellungen → Dateiablage → „Vorschau beim Überfahren“ abschaltbar.
- **Umwandeln (ab 0.43):** Unten **„Umwandeln“** (oder Rechtsklick → Umwandeln): Bilder **verkleinern** (2048, 1280, 800 Pixel), in **JPEG, PNG oder HEIC** wandeln oder mit **„Zu einem PDF zusammenfügen“** Bilder und PDFs in einer Datei sammeln. Gilt für die Auswahl, sonst für alle. Das Ergebnis liegt als neue Datei in Downloads und danach auch in der Ablage; dein Original bleibt, nichts wird überschrieben. Orts- und Kameradaten werden dabei entfernt (abschaltbar unter Einstellungen → Dateiablage). Wichtig: HEIC nach JPEG in voller Größe macht die Datei **größer**; zum Platzsparen **verkleinern**.
- **Mehrfachauswahl (ab 0.42):** Mit Umschalt- oder Befehlstaste auf Kacheln klicken wählt sie (blauer Rand), noch einmal klicken nimmt sie
  heraus, ein normaler Klick hebt alles auf. Teilen, AirDrop, ZIP und „Alle ziehen“ gelten dann nur für die Auswahl.
- **Rückgängig (ab 0.42):** Nach Entfernen oder Leeren steht kurz „Entfernt“ mit **„Rückgängig“**.
- **Zurückholen (ab 0.18):** Nach dem Rausziehen steht kurz „Rausgezogen“ mit einem Knopf **„Zurückholen“**. Für den
  Fall, dass am Ziel nichts angekommen ist, etwa weil der Finder dort schon eine gleichnamige Datei hat.
- **Volle Ablage:** Klick auf das Ablage-Symbol. Rechtsklick auf eine Datei oder einen Stapel: Im Finder zeigen, Teilen …, AirDrop,
  Entfernen, bei Stapeln auch Stapel auflösen. Unten für alle: Alle ziehen, Teilen, AirDrop, ZIP, ZIP mit Passwort, Leeren.
- **ZIP** landet als „Ablage.zip“ in deinem Downloads-Ordner und auch in der Ablage. **Mit Passwort** ist es mit
  AES-256 verschlüsselt; öffnen lässt es sich mit Keka, The Unarchiver oder 7-Zip, nicht per Doppelklick auf dem Mac.
- **Bildschirmfotos automatisch (ab 0.10):** Einstellungen → Ablage → „Bildschirmfotos automatisch ablegen“. Jedes neue
  Bildschirmfoto von macOS oder CleanShot erscheint von selbst in der Ablage. **Ab 0.16** bleibt es dort nur eine
  wählbare Zeit (Einstellungen → Ablage → „Bildschirmfotos behalten“: 5, 15, 30, 60 Min. oder immer, ab Werk 30). Danach
  verschwindet nur der Eintrag, die Datei bleibt liegen. Was du selbst hineinziehst, bleibt, bis du es entfernst.
  Videos nicht. Fotos aus iCloud Drive brauchen manchmal bis zu einer Minute. Liegen sie auf dem Schreibtisch, fragt
  macOS einmal nach dem Zugriff; ohne „Erlauben“ bleiben sie draußen.
- **Rausziehen kopiert** (ab 0.10): Das Original bleibt, wo es war, auch wenn du in den Finder ziehst.
- **Fotos aus der Fotos-App, Anhänge aus Outlook und aus Gmail im Browser** (und andere Apps, die ihre Datei erst
  beim Ablegen schreiben) landen als **Kopie** in Gnotchis eigenem Ordner. Entfernen oder Leeren löscht diese Kopie,
  nie dein Foto in der Mediathek oder den Anhang in der Mail.
- Bei allen anderen Dateien löschen Entfernen und Leeren nie etwas. Höchstens 50 Einträge.

## Zwischenablage

Einschalten unter Einstellungen → Zwischenablage (ab Werk aus). Ab dann merkt sich Gnotchi, was du kopierst: Text, formatierten Text, Links, Bilder und Dateien. Bei Dateien merkt es sich nur, wo sie liegen.

- **Aus der Notch (ab 0.14, Voreinstellung):** ⌃< klappt die Zwischenablage direkt aus der Notch herunter, auf Bildschirmen ohne Notch aus der Pille oben. Oben die Suche, darunter deine Sammlungen als Knöpfe mit Name und Anzahl, dann eine Reihe Karten, getrennt nach „Heute“, „Gestern“ und älteren Tagen. Jede Karte zeigt ihren Inhalt passend: Farbcodes als Farbfläche, Bilder randlos, Links mit der Domain, Dateien mit ihrem Symbol. Bilddateien, die mitsamt Bild kopiert wurden (etwa aus CleanShot), zeigen das Bild. Fährst du über eine Karte, erscheinen Stern (anheften) und Papierkorb. Angeheftetes steht im Verlauf immer vorne, unter „Angeheftet“. ←/→ wählen, Doppelklick oder ↵ fügt ein, Esc oder Klick daneben schließt. Fährt die Maus hinaus, klappt die Ansicht wieder zu. **Mehr Platz:** Drück das Kürzel nochmal oder klick auf „Mehr“ (Pfeile oben rechts), dann öffnet sich die große Ansicht am Rand, mit derselben Suche und Sammlung. Ein drittes Mal schließt. Lieber direkt am Rand? Einstellungen → Zwischenablage → „Zuerst aus der Notch“ ausschalten.
- **Vorschau (ab 0.15):** Leertaste zeigt die markierte Karte groß: Text vollständig, Bild groß, Farbe mit HEX, RGB und HSL, Link als volle Adresse, Bilddatei als Bild mit Pfad darunter. Mit ←/→ blätterst du weiter, Leertaste oder Esc schließt. Steht im Suchfeld schon Text, tippt die Leertaste ein Leerzeichen.
- **Karten auf einen Blick (ab 0.50):** Oben links auf jeder Karte steht das Symbol der App, aus der du kopiert hast, daneben Art und Alter; die Karte schimmert oben leicht in der Farbe dieser App. Unten steht die Länge bei Text („49 Zeichen“) und die Größe bei Bildern („2400 × 1600“). Ohne Quell-App und bei vielfarbigen Symbolen wie Fotos bleibt sie neutral.
- **Filtern (ab 0.49):** Der Knopf mit den drei Strichen neben dem Suchfeld filtert nach Zeitraum (Heute, Letzte 7 Tage, Letzte 30 Tage) und nach der App, aus der du kopiert hast. Das wirkt zusammen mit dem Suchtext: „rechnung“ plus Mail plus 7 Tage findet nur, was du in der letzten Woche aus Mail kopiert hast. Ein aktiver Filter füllt den Knopf und steht daneben, etwa „Safari · 7 Tage“. „Filter zurücksetzen“ im selben Menü hebt ihn auf, beim nächsten Öffnen ist er ohnehin weg.
- **Große Ansicht am Rand oder an der Maus:** Unter Einstellungen → Zwischenablage → „Große Ansicht“ wählst du Rechts, Links, Unten oder Maus. Bei „Maus“ öffnet sie dort, wo der Mauszeiger steht. Das Kürzel änderst du dort ebenfalls. Oben sind die Suche und der Name der offenen Sammlung, darunter die Karten, unten die Reiter für Verlauf, Angeheftetes und deine Sammlungen. ↑/↓ wählen (bei „Unten“ auch ←/→), ein Klick markiert, Esc schließt.
- **Einfügen (ab 0.12):** **Doppelklick**, ↵ oder ⌘1–⌘9 fügen den Eintrag direkt in die App ein, in der du gerade arbeitest. **Mit ⇧ als reinen Text.** Das ⌘V drückt das Hilfsprogramm „Gnotchi Mitteilungen“. Deshalb geht das nur, wenn „Mitteilungen in der Notch“ an ist und das Hilfsprogramm die Freigabe „Gerätesteuerung und Datenzugriff“ hat. Sonst kopiert Gnotchi nur, und du fügst mit **⌘V** selbst ein. Die Zeile unten in der Seitenansicht sagt dir, was gerade gilt. Nur kopieren: Rechtsklick → Kopieren.
- **Reagiert das Kürzel nicht,** belegt es vermutlich eine andere App, zum Beispiel PastePal. Wähl dann ein anderes oder beende die andere App.
- **Reiner Text per Kürzel:** Mit „Kürzel für reinen Text“ (Einstellungen → Zwischenablage, ab Werk aus) fügt **⇧⌘V** die aktuelle Kopie ohne Formatierung ein, in jeder App und auch ohne Verlauf. Danach hat die Zwischenablage ihre Formatierung wieder. Passwörter und erkannte Schlüssel werden stattdessen geleert. Das Kürzel ist frei wählbar. Einfügen geht nur mit „Mitteilungen in der Notch“, sonst liegt danach reiner Text in der Zwischenablage, und du drückst ⌘V selbst. Eine App, die ⇧⌘V selbst nutzt, bekommt das Kürzel nicht mehr. Dann ein anderes wählen.
- **In der Notch:** Das Zwischenablage-Symbol in der Leiste der großen Insel zeigt Angeheftetes und die letzten Kopien. Klick kopiert, ⇧-Klick als reinen Text, „Alle …“ öffnet die Seitenansicht.
- **Ordnen:** Rechtsklick auf eine Karte → Anheften, Zu Sammlung, Titel, Löschen. Oder die Karte auf einen Reiter ziehen. Mit dem Plus unten legst du eine Sammlung oder einen Tresor an. Ein Eintrag kann in mehreren Sammlungen stecken. Karten kannst du auch direkt in andere Apps ziehen.
- **Aufbewahrung:** Was in keiner Sammlung steckt, bleibt 30 Tage, höchstens 1 000 Einträge. Angeheftetes, Sammlungen und Tresor bleiben, bis du sie löschst.
- **Text in Bildern (neu):** Gnotchi liest Text aus kopierten Bildern und Bildschirmfotos, auf deinem Mac und im Hintergrund. Die Suche findet dann auch das Bild, in dem ein Wort steht. Rechtsklick auf ein Bild → „Text aus Bild kopieren“ legt den erkannten Text in die Zwischenablage. Gleich nach dem Einschalten kann es etwas dauern, bis ältere Bilder gefunden werden. Bilder, in denen ein Schlüssel oder Token steht, bleiben ohne Text, ganz sicher ist das aber nicht: Ein Schlüssel, der im Bild umbricht oder schlecht lesbar ist, wird nicht erkannt. Tresor-Einträge liest Gnotchi nie. Abschalten unter Einstellungen → Zwischenablage → „Text in Bildern erkennen“, der erkannte Text wird dabei gelöscht.
- **Tresor:** Für Passwörter, Schlüssel und Ähnliches. Du siehst nur den Titel. Zum Kopieren fragt Gnotchi nach Touch ID oder deinem Mac-Passwort, danach bleibt der Tresor fünf Minuten offen. Das orange Schloss oben in der Seitenansicht sperrt ihn sofort. Kopiertes aus dem Tresor verschwindet nach 60 Sekunden aus der Zwischenablage, wenn du bis dahin nichts anderes kopiert hast. Tresor-Einträge erscheinen nie in der Notch und lassen sich nicht herausziehen.
- **Schlüssel und Tokens (ab 0.13):** Kopierst du einen API-Schlüssel, ein Token oder einen privaten Schlüssel, erkennt Gnotchi das an der festen Form (etwa die Vorsilbe eines Anbieters). Der Eintrag zeigt dann nur `••••••`, die Art und die Restzeit. Er erscheint nicht in der Notch, lässt sich nicht herausziehen und ist **5 Minuten nach der letzten Nutzung** weg. Steht er dann noch in der Zwischenablage, leert Gnotchi sie auch. Einfügen per Doppelklick geht weiter. Behalten willst du ihn? Rechtsklick → In Tresor. Erkannt wird nur, wenn die ganze Kopie der Schlüssel ist. Ein Schlüssel mitten in einem längeren Text bleibt ein normaler Eintrag. Schlüssel ohne feste Vorsilbe (etwa von Hostinger, Mistral oder ältere von Cloudflare) erkennt Gnotchi nicht. Leg sie am besten gleich in den Tresor. Liegen Schlüssel schon in deinen Sammlungen, löscht Gnotchi dort nichts: Sie erscheinen verdeckt, und die Seitenansicht bietet einmal an, sie in den Tresor zu verschieben. Abschalten unter Einstellungen → Zwischenablage → „Schlüssel und Tokens erkennen“.
- **Nie im Verlauf:** Kopien, die eine App als vertraulich kennzeichnet (etwa die Passwörter-App), und alles aus Apps unter „Nie aus diesen Apps“. „30 Min. pausieren“ hält das Mitlesen an.
- **Aus PastePal:** Exportiere in PastePal (Einstellungen → Exportieren). Dann in Gnotchi „Aus PastePal importieren …“ wählen und je Sammlung entscheiden, ob sie in den Tresor kommt. Formatierungen kommen nicht mit, denn PastePal exportiert nur reinen Text. Die Exportdatei landet danach im Papierkorb. Leere ihn.
- **Löschen:** „Verlauf löschen …“ entfernt alles außerhalb der Sammlungen. „Alles zurücksetzen …“ löscht auch Sammlungen, Tresor und die Schlüssel. Danach ist nichts mehr lesbar, auch nicht in Sicherungen.

## Terminal

Ab 0.44 kann Gnotchi ein Terminalfenster öffnen: **Einstellungen → Allgemein → Terminal → „Terminal-Fenster anbieten“** einschalten (ab Werk aus), dann im Menüleisten-Fenster unter **Funktionen → Werkzeuge** oder mit der **Terminal-Taste** unten an der großen Insel (Symbol `>_`) öffnen.
- Es öffnet sich ein normales Fenster mit deiner Anmelde-Shell (meist zsh) im Home-Ordner. **⌘N** öffnet ein weiteres Fenster, **⌘F** sucht, **⌘+** und **⌘−** ändern die Schrift, **⌘0** setzt sie zurück (ab Werk 16 Punkt).
- Schließt du ein Fenster, während noch ein Programm läuft, fragt es vorher. Beendest du die Shell mit `exit`, schließt sich das Fenster.
- Das Fenster ist ein eigenes Programm, **„Gnotchi Terminal“**, ohne Gnotchis Freigaben (Kamera, Apple Events). Programme im Terminal können weder die Zwischenablage mitlesen noch ändern.
- **Ordner hineinziehen (ab 0.48):** Ziehst du einen Ordner oder eine Datei aus dem Finder ins Fenster, steht der Pfad in der Eingabezeile, z. B. nach `cd `. Leerzeichen und Sonderzeichen sind geschützt. Ausgeführt wird erst mit Return.
- Die Shell hat deine Nutzerrechte, wie in Terminal.app. Für Ordner wie Dokumente, Schreibtisch oder Downloads fragt macOS unter **„Gnotchi Terminal“** nach.

## Wetter

Einstellungen → Tasten → **Wetter in der Notch** einschalten (ab Werk aus), dann unter „Stadt suchen“ deinen Ort eingeben,
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
- **Schnelleingabe** (Aktivitäten): ab Werk aus, Kürzel ab Werk control + option + N (siehe „Schnelleingabe“).
- **Ruhige Insel ohne Notch** (Allgemein → Aussehen): ab Werk an. Ohne Notch sieht die Pille aus wie die Menüleiste, solange nichts läuft.
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
„Hilfe …“, bei verschobener großer Insel dazu „Insel zurücksetzen“. Die Insel klappt dabei nicht auf.

## Berechtigungen

Gnotchi braucht **keine Freigabe „Gerätesteuerung und Datenzugriff“**, keine Bildschirmaufnahme, kein Mikrofon und kein Bluetooth. Nur wenn du „Lautstärke je App“ einschaltest (ab Werk aus), fragt macOS beim ersten Verschieben eines App-Reglers nach **„Audio-Aufnahme“** (bei Gnotchi nicht immer; dann selbst eintragen: Systemeinstellungen → Datenschutz & Sicherheit → „Aufnahme von Bildschirm & Systemaudio“ → „+“ → Gnotchi): Sie erlaubt Gnotchi, den Ton dieser App mitzuhören, solange ihr Regler nicht auf 100 % steht. Der Ton bleibt im Arbeitsspeicher und wird nicht gespeichert. Auch
die Dateiablage braucht keine Freigabe. Ausnahme: Wer „Bildschirmfotos automatisch ablegen“ einschaltet und Fotos auf
dem Schreibtisch speichert, erlaubt Gnotchi einmal den Zugriff auf den Schreibtisch.
Nur wer „Mitteilungen in der Notch“ einschaltet, erteilt die Freigabe „Gerätesteuerung und Datenzugriff“ dem eigenen Hilfsprogramm
„Gnotchi Mitteilungen“, nicht Gnotchi. Dasselbe Hilfsprogramm liest für die Ungelesen-Zahlen die Abzeichen im Dock
und drückt beim Einfügen aus der Zwischenablage ⌘V, sonst keine Taste.
Das Terminal („Gnotchi Terminal“) ist ein eigenes Programm ohne Freigaben; macOS fragt für Ordner wie Dokumente oder Schreibtisch unter diesem Namen.
„Claude Code in der Notch“ braucht keine Freigabe, Gnotchi trägt nur Einträge in `~/.claude/settings.json` ein.
Auch die Zwischenablage braucht keine Freigabe. Für den Tresor fragt macOS nach Touch ID oder deinem Mac-Passwort.
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
- Gnotchi speichert sie nicht, schreibt sie nicht ins Protokoll und schickt sie nirgendwohin. Einzige Ausnahme, nur wenn du „Stream Deck“ einschaltest: Titel und Interpret gehen an die Stream-Deck-App auf deinem Mac, damit die Leiste sie zeigt.
- Gespeichert werden nur deine Einstellungen.
- Gnotchi liest keine Fenstertitel und keine Inhalte anderer Apps und nimmt keinen Ton auf.
- Welche App Mikrofon oder Kamera nutzt, steht nur in der Insel, nie im Protokoll.
- Von Tippi erfährt Gnotchi über eine Systemmeldung „nimmt auf“, „wandelt um“ und den Pegel. Diese Meldung kann jedes Programm auf deinem Mac mitlesen; sie verrät nur, dass du gerade diktierst, nie was.
- Den Text der Live-Vorschau bekommt Gnotchi auf einem eigenen, geschützten Weg: Beide Apps prüfen vorher die Signatur der anderen, andere Programme werden abgewiesen. Der Text steht nur in der Insel, wird nicht gespeichert, nicht protokolliert und ist weg, sobald das Diktat endet.
- Von Qotti kommen nur die Prozente, der Zeitpunkt der Zurücksetzung und „ok/veraltet/gedrosselt“, nie Konto, E-Mail oder Plan. Auch diese Meldung kann jedes Programm auf deinem Mac mitlesen.
- Update-Meldungen der Familien-Apps enthalten nur den App-Namen und die Versionsnummer. Auch sie kann jedes Programm mitlesen. Gnotchi zeigt daraus nur Namen und Version und speichert sie nicht.
- Der Medienfilter speichert nur die Kennungen der ausgeschalteten Apps, keine Titel und keine Zeitpunkte.
- Deinen nächsten Termin bekommt Gnotchi von Kalli auf demselben geschützten Weg wie Tippis Live-Text: Beide Apps prüfen vorher die Signatur der anderen. Kalli schickt nur Titel, Beginn und Kalenderfarbe des Termins, den seine Menüleiste ohnehin zeigt. Gnotchi speichert ihn nicht, protokolliert ihn nicht und vergisst ihn bei Beginn.
- Die Schnelleingabe schickt, was du eintippst (Titel, Zeitpunkt, Art), über dieselbe geschützte Verbindung an Kalli, und nur, wenn du ↵ drückst. Gnotchi speichert nichts davon, protokolliert keine Eingaben und vergisst die Zeile beim Schließen. Kalli prüft jede Anfrage selbst und löscht per ⌘Z nur einen Eintrag, der gerade eben auf diesem Weg entstand. In Bildschirmfreigaben ist die Zeile unsichtbar.
- Der Geschwindigkeitstest (nur auf deinen Klick, ab Werk aus) schickt Datenverkehr zu Apples Testservern, höchstens 20 Sekunden lang. Das Ergebnis steht nur in der Insel und wird nicht gespeichert.
- Das Kamerabild des Spiegels geht direkt auf den Bildschirm. Gnotchi speichert es nicht, verarbeitet es nicht und schickt es nirgendwohin.
- Der Timer lebt nur im Arbeitsspeicher.
- Mitteilungen liest nur das Hilfsprogramm „Gnotchi Mitteilungen“, und nur die der Apps, die du ausgewählt hast,
  gehen an Gnotchi weiter. Beide prüfen vorher die Signatur des anderen. Texte werden nicht gespeichert, nicht
  protokolliert und sind weg, sobald die Mitteilung verschwindet. Gespeichert wird nur die App-Liste.
- Von Claude Code bekommt Gnotchi nur Projektname, Status, Werkzeug, einen gekürzten Befehl und den gekürzten
  Anfang der Antwort, über einen eigenen Weg, auf dem beide Seiten die Signatur prüfen. Nie deine Eingabe, nie den
  Verlauf, nie Dateiinhalte. Nichts davon wird gespeichert oder protokolliert.
- Das Türklingel-Bild holt Gnotchi nur von der Adresse, die du einträgst, und nur, solange der Klingel-Hinweis zu
  sehen ist. Es liegt nur im Arbeitsspeicher, wird nie gespeichert und ist mit dem Hinweis weg. Im Protokoll steht
  nur der Statuscode, nie die Adresse.
- Für die Ungelesen-Zahlen liest das Hilfsprogramm nur die Zahl am Dock-Symbol der ausgewählten Apps, nie deren Text.
- Die Dateiablage speichert nur, wo die Dateien liegen (nur für dich lesbar), nie ihren Inhalt. Ausnahme: Fotos aus
  der Fotos-App und Mail-Anhänge aus Outlook oder Gmail liegen als Kopie in Gnotchis Ordner (nur für dich lesbar),
  bis du sie aus der Ablage entfernst.
  ZIP-Passwörter werden nicht gespeichert.
- Der Zwischenablage-Verlauf liegt nur verschlüsselt auf deinem Mac, nur für dich lesbar. Der Schlüssel steckt im Schlüsselbund, und nur Gnotchi kommt an ihn. Er geht nirgendwohin, auch nicht in iCloud. Im Protokoll steht nie, was du kopiert hast.
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
- **„Spotify jetzt erlauben“ (Einstellungen → Wiedergabe):** Erscheint, wenn macOS Spotify nicht meldet und Gnotchi die Steuerung noch nicht erlaubt ist. Der Knopf löst die macOS-Frage aus. Sagst du Ja, merkt sich Gnotchi das; nimmt macOS die Erlaubnis später zurück, beendet Gnotchi den Ersatzweg.
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
