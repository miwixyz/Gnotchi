# Changelog

Alle nennenswerten Änderungen an Gnotchi. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## [0.18.0] — 2026-10-28

Alle Dateien der Ablage auf einmal herausziehen, und Zurückholen, wenn am Ziel nichts ankommt.

### Neu
- **„Alle ziehen“.** In der großen Ablage steht unten links ein neuer Griff, sobald mindestens zwei Dateien darin liegen. Zieh ihn, und alle Dateien wandern in einem Zug ans Ziel, wie eine Mehrfachauswahl im Finder. Wie beim einzelnen Rausziehen wird kopiert, die Originale bleiben, wo sie sind.
- **„Zurückholen“ nach dem Rausziehen.** Nimmt Gnotchi Dateien nach dem Rausziehen aus der Ablage, zeigt die Insel 6 Sekunden lang „Rausgezogen“ mit der Anzahl und einem Knopf „Zurückholen“. Ein Klick legt genau diese Einträge zurück. Das hilft, wenn das Ziel die Übernahme meldet, aber nichts anlegt: Der Finder tut das zum Beispiel, wenn dort schon eine gleichnamige Datei liegt. Ist „Nach dem Rausziehen entfernen“ aus, erscheint kein Hinweis.

### Intern
- `DragSource` nimmt mehrere URLs (`init(urls:…)`, ein Ziehvorgang mit allen, leicht versetzter Stapel); `ShelfLink.draggedOut(_:[Item])`, `restoreLastDrag()`, `ShelfStore.restore(_:)` (eigene Kopien gelten wieder als benutzt, Höchstzahl gilt). `Notice.action` (`NoticeAction.restoreShelf`): nur Hinweise mit Knopf sind anklickbar, sie bleiben doppelt so lange; Überfahren klappt aus einem Hinweis weiterhin nichts auf. 7 neue Tests (`ShelfDragAllTests`), ein Render-Fall (`notch/pill-notice-restore`).

## [0.17.5] — 2026-10-27

Der Plattenspieler ist wieder klar statt milchig.

### Behoben
- **Kein grauer Schleier mehr auf dem Plattenspieler.** Das Gerät war blass, die Platte grau statt schwarz, je nach Cover mit grauem oder olivem Stich. Ursache war die Farbtönung des Raums: Sie sollte das Gerät nur leicht in die Coverfarbe tauchen, lag im echten Fenster aber als deckende Schicht darüber. Die Tönung ist entfernt. Farbverlauf, Lichtschein und Neonschrift nehmen die Coverfarbe weiter auf.

### Intern
- `TurntableView.deck` ohne Tönungs-Overlay, `layers(at:)` ohne den Parameter `shadows` (gab es nur für die Tönungsmaske). Die Testbilder (`ImageRenderer`) zeigten die Mischart `softLight` korrekt, das echte Fenster nicht, wahrscheinlich schon seit 0.17.0. Gefunden per Messschalter am Schreibtisch: ohne Tönung klar. Neues Testbild mit hellem Cover (`testRenderTurntableWhiteCover`).

## [0.17.4] — 2026-10-27

Der Tonarm steht wieder ganz auf dem Plattenspieler.

### Behoben
- **Tonarm ragt wieder über den Plattenspieler hinaus.** Lager und Gegengewicht waren an der Oberkante des Geräts abgeschnitten. Die Farbtönung des Raums bleibt trotzdem auf Gerät und Arm, die Luft daneben wird nicht gefärbt.

### Intern
- Die Maske begrenzt nur noch die Tönung (`TurntableView.deck`), nicht mehr alle Ebenen. Maskenform: `layers(at:shadows: false)`, also Gerät, Platte und Arm ohne die weichen Armschatten. Seit dem Tönungs-Fix von 0.17.0 schnitt die Maske alles außerhalb der Gerätefläche ab. Vorher/Nachher per `testRenderTurntable`.

## [0.17.3] — 2026-10-27

Hülle und Platte im richtigen Verhältnis.

### Behoben
- **Größere Hülle am Plattenspieler.** Die Hülle neben dem Plattenspieler war ein Viertel kleiner als die Platte und wirkte wie eine Single. Jetzt ist sie knapp so groß wie die Platte. Der echte LP-Maßstab, etwas größer als die Platte, wirkte aufrecht neben der schräg gesehenen Platte zu wuchtig. Damit alles bei einem Drittel des Bildschirms bleibt, ist der Plattenspieler etwas kleiner geworden.

### Intern
- Plattenbreite im Bild aus der gemessenen Perspektive (0,565 Gerätebreiten), Hülle 0,52 (vorher 0,42). Test prüft das Verhältnis und dass die Hülle nie größer als eine echte LP wird.

## [0.17.2] — 2026-10-27

Start und Stopp am Plattenspieler, so wie an einem echten.

### Behoben
- **Start/Stopp-Knopf statt Tonarm.** „Tonarm bedienen“ reagierte kaum: Starten ging, Stoppen nie. Jetzt bedienst du den Plattenspieler über den großen Start/Stopp-Knopf unten links am Gerät. Ein Klick hält die Musik an oder startet sie, der Knopf wird dabei kurz dunkler, und der Tonarm fährt von selbst. Der Schalter heißt jetzt Einstellungen → Wiedergabe → „Start/Stopp-Knopf bedienen“ (ab Werk aus, wer „Tonarm bedienen“ an hatte, hat ihn an).

### Intern
- Gemessen per Messpunkt: Die Farbtönung über dem Gerät fing jeden Klick ab; oben drauf gelegt kam beim Spielen trotzdem kein Klick an, weil der Griff zehnmal pro Sekunde mit dem Arm neu gesetzt wurde. Der Knopf steht fest, Test prüft seine Lage im Sockelbild.

## [0.17.1] — 2026-10-27

Die Zwischenablage öffnet wieder sofort.

### Behoben
- **Strg+< öffnet ohne Wartezeit.** Mit vielen Einträgen dauerte es spürbar, bis die Zwischenablage aufging, aus der Notch wie am Rand. Gnotchi baute beim Öffnen alle Karten auf einmal und verkleinerte dabei jedes gespeicherte Bildschirmfoto neu. Jetzt entstehen nur die Karten, die du siehst, und die Vorschaubilder liegen schon bereit: Gnotchi bereitet sie nach dem Start und bei jedem neuen Bild im Hintergrund vor.

### Intern
- Gemessen an 350 Einträgen (92 mit Bild): vorher rund 90 % der Wartezeit im Aufbau der Kartenreihe, davon über die Hälfte im Entpacken der Bilder. Vorbereiten danach: 88 Vorschaubilder in knapp 2 s, im Hintergrund. Protokoll (`zwischenablage`) nennt nur Anzahl und Dauer.

## [0.17.0] — 2026-10-27

Ein Plattenspieler auf dem Schreibtisch, und Shuffle in der Insel.

### Neu
- **Plattenspieler als Hintergrund.** Die Musik auf dem Schreibtisch gibt es jetzt auch als Plattenspieler: mittig, etwa ein Drittel des Bildschirms groß, links daneben die Hülle mit dem Cover, darunter Titel und Interpret. Die Platte dreht sich, solange Musik läuft. Der Tonarm fährt beim Start auf die Platte, wandert im Lauf des Titels langsam nach innen und geht beim Pausieren in die Ablage. Dahinter liegt ein Farbverlauf aus den Farben des Covers, der beim Titelwechsel weich überblendet. Er liegt unter deinen Schreibtisch-Symbolen, die bleiben sichtbar und klickbar. Einschalten unter Einstellungen → Wiedergabe → „Cover und Titel auf dem Schreibtisch“, dann „Darstellung: Plattenspieler“ (ab Werk bleibt es die Karte).
- **Bildschirm wählbar.** Für den Plattenspieler wählst du, auf welchem Bildschirm er steht (ab Werk der Hauptbildschirm). Ist der gewählte Bildschirm nicht angeschlossen, nimmt Gnotchi den Hauptbildschirm, bis er wieder da ist.
- **Neonschrift „Now Playing“.** Über dem Plattenspieler leuchtet auf Wunsch ein Neon-Schriftzug in der Farbe des Covers. Er zündet beim Start mit kurzem Flackern und brummt ab und zu leise nach. Abschalten unter Einstellungen → Wiedergabe → „Neonschrift „Now Playing““ (ab Werk an).
- **Tonarm bedienen.** Auf Wunsch startest und hältst du die Musik, indem du den Tonarm anfasst. Einschalten unter Einstellungen → Wiedergabe → „Tonarm bedienen“ (ab Werk aus).
- **Shuffle.** Bei Spotify und Musik steht in der großen Insel und unter dem Plattenspieler ein Shuffle-Knopf. Ist Shuffle an, ist der Knopf hell hinterlegt und hat einen Punkt darunter. Ist es aus, ist er gedimmt.

### Gut zu wissen
- Shuffle gibt es nur bei Spotify und Musik, nicht bei Videos im Browser. Der erste Klick kann die Frage von macOS auslösen, ob Gnotchi Spotify bzw. Musik steuern darf.
- Ein Favoriten-Herz fehlt noch: Musik nimmt den Befehl bei Apple-Music-Titeln an, ändert aber nichts, und Spotify lässt sich von außen gar nicht so steuern. Es kommt in einer späteren Version auf anderem Weg.
- Solange die Platte dreht, braucht Gnotchi etwa ein Zehntel eines Prozessorkerns (gemessen am Mac mini). Bei Pause steht alles still.

### Intern
- Plattenspieler aus KI-Fotos, in Ebenen zerlegt (Sockel, Platte, Glanz, Spindel, Tonarm, Schatten), Perspektive per gemessener Homografie (`TurntableGeometry`). Rohmaterial liegt nicht im Repo.
- Schrift Neonderthaw (SIL OFL 1.1) mitgeliefert, Lizenz unter „Fremdcode“.
- Shuffle per AppleScript, gleiche Regeln wie Spulen (G7): feste Kennungen, nur an laufende Apps, 3-s-Zeitgrenze, ein Befehl gleichzeitig, nur auf Klick. Den Stand liest Gnotchi nur, wenn macOS die Steuerung schon erlaubt hat (`AEDeterminePermissionToAutomateTarget` ohne Dialog).

## [0.16.0] — 2026-10-27

Eine ruhigere Insel ohne Notch und eine Ablage, die sich selbst aufräumt.

### Neu
- **Ruhige Insel ohne Notch.** Auf Bildschirmen ohne Notch war die Insel immer schwarz, auch wenn sie nur Wetter oder Ungelesen-Zahlen zeigte. Auf einer hellen Menüleiste fiel sie dann auf. Jetzt sieht sie in diesem Fall aus wie die Menüleiste, mit Glas und passender Schrift. Sobald etwas läuft (Musik, Timer, Termin, Anruf, Diktat, Mitteilung, Mikrofon oder Kamera), wird sie wieder schwarz. Abschalten unter Einstellungen → Allgemein → Aussehen → „Ruhige Insel ohne Notch“ (ab Werk an). Mit Notch bleibt die Insel schwarz.
- **Bildschirmfotos verschwinden wieder aus der Ablage.** Automatisch abgelegte Bildschirmfotos bleiben nur noch eine wählbare Zeit in der Ablage: 5, 15, 30 oder 60 Minuten oder immer (ab Werk 30). Die Datei selbst bleibt liegen, nur der Eintrag in Gnotchi geht. Einstellen unter Einstellungen → Ablage → „Bildschirmfotos behalten“. Dateien, die du selbst hineinziehst, laufen nie ab.

### Gut zu wissen
- Bildschirmfotos, die schon vor dem Update in der Ablage lagen, laufen nicht ab. Entferne sie bei Bedarf von Hand.

### Intern
- Messpunkt Fokus: Wechselt die vordere App, während eine Mitteilung oder ein Anruf zu sehen ist, steht im Protokoll (Kategorie `fokus`), ob Gnotchi oder sein Hilfsprogramm das war. Nur ja oder nein, keine App-Namen. Gemessen am 27.10.: Eine Mitteilung nahm keiner App den Fokus.
- `ablage.json` merkt sich bei automatisch abgelegten Bildschirmfotos den Zeitpunkt (`shot`, Schema weiter `v: 1`, ältere Versionen übergehen das Feld). Beim Lesen geprüft: nur eine endliche Zahl nach 2020.

## [0.15.1] — 2026-10-26

Drei Korrekturen, gefunden an der echten MacBook-Notch.

### Behoben
- **„Alle …“ öffnet vorne.** Der Knopf in der großen Insel öffnete die Zwischenablage hinter der Insel, sichtbar erst, wenn die Maus wegging. Jetzt öffnet er direkt die Seitenansicht am Rand.
- **Bilder statt Datei-Symbol.** Kopierst du ein Bildschirmfoto als Datei (etwa aus CleanShot), zeigen Karte, Insel und Vorschau jetzt das Bild. Die Vorschau nennt darunter den Pfad. Das gilt für alles, was ab jetzt kopiert wird. Ältere Einträge zeigen das Bild nur, wenn es damals mitgespeichert wurde.
- **Band klappt nicht mehr sofort zu.** Ein Klick auf die Ablage im linken Teil des Bands öffnete die große Insel, die schloss sich aber gleich wieder: Sie ist schmaler als das Band, und die Maus stand danach neben ihr. Jetzt bleibt sie kurz offen, bis du hineinfährst.

### Intern
- `ClipThumbnails.image` nimmt jetzt auch Datei-Einträge mit gespeichertem Bild an (`public.file-url` + `public.png`, gemessen an Clop). Gelesen wird nur das gespeicherte Bild, nie die Datei (G40). Text mit Bild bleibt eine Textkarte (getestet).
- `IslandController`: Schrumpft die Insel beim Aufklappen aus dem Band unter der Maus weg, wartet das erste Zuklappen 1,5 s statt 300 ms.

## [0.15.0] — 2026-10-26

Musik auf dem Schreibtisch, und eine Vorschau für die Zwischenablage.

### Neu
- **Musik auf dem Schreibtisch.** Gnotchi zeigt auf Wunsch Cover, Titel und Interpret auf dem Schreibtisch, hinter allen Fenstern. Einschalten unter Einstellungen → Wiedergabe → „Cover und Titel auf dem Schreibtisch“ (ab Werk aus), dort wählst du auch Ecke und Größe (Klein, Mittel, Groß). Die Anzeige ist da, solange Musik spielt oder pausiert, und geht nach 10 Minuten Pause weg. Fährst du darüber, erscheinen ganz unten Zurück, Pause und Weiter. Ein Klick aufs Cover holt die App nach vorne, die gerade spielt.
- **Frei verschiebbar.** Zieh die Anzeige mit der Maus, wohin du willst, bündig in eine Ecke und bis auf Höhe des Docks. Gnotchi merkt sich die Lage relativ zur nächsten Ecke, so bleibt sie beim Wechsel zwischen Bildschirmen, wo sie hingehört.
- **Vorschau per Leertaste.** In der Zwischenablage zeigt die Leertaste die markierte Karte groß: Text vollständig, Bild groß, Farbe mit HEX, RGB und HSL, Link als volle Adresse. ←/→ blättert weiter, Leertaste oder Esc schließt. Steht im Suchfeld schon Text, bleibt die Leertaste ein Leerzeichen.

### Gut zu wissen
- Die Schreibtisch-Anzeige erscheint nur auf dem Hauptbildschirm. Das Dock liegt immer darüber.
- Der Klick aufs Cover startet nie eine App. Er holt nur eine, die schon läuft, nach vorne.

### Intern
- `DesktopMusicLink`: randloses Fenster eine Ebene über den Schreibtisch-Symbolen, dieselben Daten wie die Insel (G4–G6), keine Berechtigung, kein Netz. Lage als Ecke + Abstand gespeichert, Zurückholen in den erlaubten Bereich nach dem Ziehen. `ClipPreview` mit HSL-Umrechnung (getestet). SECURE-DESIGN G44.

## [0.14.0] — 2026-10-26

Die Zwischenablage klappt jetzt aus der Notch herunter, und jede Karte zeigt ihren Inhalt so, wie er ist.

### Neu
- **Aus der Notch.** ⌃< klappt die Zwischenablage direkt aus der Notch herunter, auf Bildschirmen ohne Notch aus der Pille oben. Oben stehen die Suche und deine Sammlungen als Knöpfe mit Name und Anzahl, darunter eine Reihe Karten, getrennt nach „Heute“, „Gestern“ und älteren Tagen. ←/→ wählt, Doppelklick oder ↵ fügt ein. Fährt die Maus hinaus, klappt die Ansicht wieder zu.
- **Mehr Platz auf Wunsch.** Drückst du ⌃< nochmal oder klickst auf „Mehr“, öffnet sich die große Ansicht am Rand, mit derselben Suche und Sammlung. Ein drittes Mal schließt. Wer lieber gleich am Rand startet, schaltet unter Einstellungen → Zwischenablage „Zuerst aus der Notch“ aus.
- **Karten je Inhalt.** Ein kopierter Farbcode wie `#E50914` oder `rgb(…)` erscheint als Farbfläche mit Hex-Wert. Bilder füllen die Karte, Links zeigen die Domain groß und den Pfad klein, Dateien ihr Symbol. Schlüssel und Tresor-Einträge bleiben verdeckt. Auch die große Ansicht zeigt Farbfelder und Domains.
- **Stern und Papierkorb.** Fährst du über eine Karte, kannst du sie direkt anheften oder löschen.

### Gut zu wissen
- Links lädt Gnotchi nicht. Es gibt keine Vorschaubilder von Webseiten, die Domain steht nur als Text da.
- Eine Vorschau per Leertaste kommt in einer späteren Version.

### Intern
- `ColorCode` (nur ganze Kopie, höchstens 64 Zeichen, verankerte einfache Muster), `ClipDays` (Tagestrenner, getestet über die Zeitumstellung), `ClipTile`. Das Herunterklappen ist ein eigenes, nicht aktivierendes Fenster eine Ebene unter der Insel, oben bündig mit Notch bzw. Menüleiste, nicht in Bildschirmfreigaben. Die verspätete Fokusverlust-Meldung schließt beim Wechsel zur großen Ansicht nicht mehr das neue Fenster. Testbilder mit erfundenen Einträgen (`ClipboardRenderTests`). Keine neue Berechtigung, kein Netz.

## [0.13.0] — 2026-10-26

Kopierte Schlüssel stehen nicht mehr lesbar im Verlauf.

### Neu
- **Schlüssel und Tokens erkennen.** Kopierst du einen API-Schlüssel, ein Token oder einen privaten Schlüssel, erkennt Gnotchi das an der Form, etwa an der Vorsilbe des Anbieters. Rund 40 Dienste sind dabei, darunter OpenAI, Anthropic, GitHub, Cloudflare, Stripe, ElevenLabs und Rafter. In der Seitenansicht steht dann nur `••••••` mit der Art und der Restzeit. Der Eintrag erscheint nicht in der Notch und lässt sich nicht herausziehen. 5 Minuten nach der letzten Nutzung ist er weg. Liegt er dann noch in der Zwischenablage, leert Gnotchi sie auch. Doppelklick fügt weiter ein. Behalten willst du ihn? Rechtsklick → In Tresor.
- Erkannt wird nur, wenn die ganze Kopie der Schlüssel ist. Ein Schlüssel mitten in einem längeren Text bleibt ein normaler Eintrag. Schlüssel ohne feste Vorsilbe (etwa Hostinger, Mistral, ältere von Cloudflare) erkennt Gnotchi nicht.
- **In Sammlungen löscht Gnotchi nichts.** Liegen dort schon Schlüssel, erscheinen sie verdeckt, und die Seitenansicht bietet einmal an, sie in den Tresor zu verschieben.
- Ab Werk an. Abschalten unter Einstellungen → Zwischenablage → „Schlüssel und Tokens erkennen“.

### Behoben
- Der Hinweis in den Einstellungen sagte noch „Einfügen machst du selbst mit ⌘V“. Seit 0.12.0 fügt ein Doppelklick ein.

### Intern
- `SecretDetector` mit 41 festen, verankerten Mustern (gitleaks-Standardkonfiguration, MIT, plus Anbieter-Doku). Keine Entropie-Schätzung. Nur reiner Text bis 8 KB. Die Art wird aus dem entschlüsselten Inhalt im Arbeitsspeicher berechnet, nicht gespeichert, also kein neues Datenbankfeld. Automatisch gelöscht werden nur lose, erkannte, abgelaufene Einträge. Verlässt ein gespeichertes Geheimnis eine Sammlung, beginnt die Frist neu. Protokoll nur mit Zahlen. SECURE-DESIGN G43. 584 Tests.

## [0.12.0] — 2026-10-26

Gnotchi fügt jetzt selbst ein: Doppelklick in der Seitenansicht, und der Eintrag steht in deiner App.

### Neu
- **Einfügen per Doppelklick.** In der Seitenansicht der Zwischenablage fügen Doppelklick, ↵ und ⌘1 bis ⌘9 den Eintrag direkt in die App ein, in der du gerade arbeitest. ⇧ dazu fügt reinen Text ein. Das klappt auch mit dem Tresor, nach Touch ID oder deinem Mac-Passwort. Ein einfacher Klick markiert nur noch. „Nur kopieren“ steht im Rechtsklick-Menü.
- **Name der Sammlung oben.** Über den Karten steht jetzt, welche Sammlung offen ist. Unten bleiben die Reiter als Symbole.

### Gut zu wissen
- Das ⌘V drückt das Hilfsprogramm „Gnotchi Mitteilungen“, das die Bedienungshilfen-Freigabe schon hat. Gnotchi selbst bekommt weiter keine. Deshalb geht Einfügen nur, wenn „Mitteilungen in der Notch“ an ist. Sonst kopiert Gnotchi wie bisher, und du drückst ⌘V selbst. Die Zeile unten in der Seitenansicht zeigt, was gerade gilt.
- Die Kacheln in der Notch kopieren weiterhin nur.

### Intern
- Neuer Befehl `{"v":1,"paste":true}` über den beidseitig geprüften Socket `notify.sock`. Er trägt keinen Inhalt, keine Taste und kein Ziel. Das Hilfsprogramm drückt darauf genau ⌘V (`PasteKey.swift`, Tastencode 9, nur ⌘), höchstens einmal je 0,3 s, nicht wenn Gnotchi vorn ist, nur mit Freigabe. Die Lint-Regel `keine_eingaben_im_helfer` nimmt nur diese Datei aus. Beim Tresor hängt das Einfügen an `ClipboardLink`, nicht an der Seitenansicht. Die schließt sich, sobald der Passwort-Dialog den Fokus nimmt, und vorher ging das Einfügen dabei verloren. SECURE-DESIGN G42. 570 Tests.

## [0.11.1] — 2026-10-24

### Behoben
- **Im Band lag die Kontingent-Anzeige teilweise unter der Notch.** Das passierte, wenn links nur eine Claude-Sitzung stand und rechts nichts. Dann rutschte „Claude … · Codex …“ über die Mitte, und der Anfang verschwand hinter der Kamera. Jetzt bleibt alles links neben der Notch.

### Intern
- Rechte Hälfte des Bands immer als eigenes Element (`HStack` mit `Spacer`). Ein leeres `EmptyView` nahm trotz `.frame(maxWidth:)` keinen Platz, die Notch-Lücke saß dadurch nicht mehr über der Kamera. Neues Testbild `notch-band-claude-quota`. 568 Tests.

## [0.11.0] — 2026-10-24

Das Wichtigste: Gnotchi merkt sich jetzt, was du kopierst. Mit Sammlungen, einem Tresor für Geheimes und Import aus PastePal.

### Neu
- **Verlauf der Zwischenablage.** Einschalten unter Einstellungen → Zwischenablage (ab Werk aus). Gnotchi merkt sich Text, formatierten Text, Links, Bilder und Dateien, Dateien nur als Verweis. Mit ⌃< öffnet sich am Bildschirmrand eine Seitenansicht mit Suche, das Kürzel ist frei wählbar. Ob die Ansicht rechts, links oder unten sitzt, stellst du ein. ↑ und ↓ wählen, ↵ kopiert, ⇧↵ kopiert als reinen Text, ⌘1 bis ⌘9 holen die ersten neun. Einfügen machst du danach selbst mit ⌘V. Gnotchi drückt keine Tasten für dich und braucht deshalb auch keine Bedienungshilfen.
- **Zwischenablage in der Notch.** In der Leiste der großen Insel sitzt ein neues Symbol. Es zeigt Angeheftetes und die letzten Kopien als Kacheln. Ein Klick kopiert, ⇧-Klick kopiert als reinen Text, „Alle …“ öffnet die Seitenansicht.
- **Sammlungen und Angeheftetes.** Per Rechtsklick heftest du einen Eintrag an, legst ihn in eine Sammlung oder gibst ihm einen Titel. Du kannst eine Karte auch auf einen Reiter unten ziehen. Ein Eintrag darf in mehreren Sammlungen stecken. Die Suche findet Titel und Inhalt. Angeheftetes und Sammlungen bleiben, der übrige Verlauf hält 30 Tage oder 1 000 Einträge.
- **Tresor für Geheimes.** In einer Tresor-Sammlung stehen nur Titel und Punkte. Den Inhalt gibt es erst nach Touch ID oder deinem Mac-Passwort. Danach bleibt der Tresor fünf Minuten offen. Das Schloss oben sperrt ihn sofort, Bildschirmsperre und Ruhezustand ebenso. Was du aus dem Tresor kopierst, ist als vertraulich markiert, andere Verlaufs-Apps übernehmen es also nicht. Nach 60 Sekunden leert Gnotchi die Zwischenablage wieder, außer du hast inzwischen etwas anderes kopiert.
- **Aus PastePal importieren.** Unter Einstellungen → Zwischenablage → „Aus PastePal importieren …“ übernimmt Gnotchi deine Sammlungen samt Einträgen. Für jede Sammlung entscheidest du, ob sie in den Tresor kommt. PastePal exportiert nur reinen Text, Formatierungen gehen dabei verloren. Danach liegt die Exportdatei im Papierkorb. Leere ihn, denn sie enthält alles im Klartext.
- **Nie im Verlauf** landen Kopien, die eine App als vertraulich kennzeichnet (etwa die Passwörter-App), und alles aus Apps auf deiner Ausschlussliste. In den Einstellungen pausierst du das Mitlesen für 30 Minuten.

### Behoben
- **Gnotchi startete manchmal gar nicht.** 0.10.0 konnte direkt beim Start abstürzen. Die Insel ging los, während die App sich noch aufbaute. Jetzt startet sie einen Augenblick später.

### Intern
- Verlauf je Feld mit AES-256-GCM verschlüsselt, Datensatz-ID als zusätzliche authentifizierte Daten. Der Schlüssel liegt im Schutzklassen-Schlüsselbund in Gnotchis eigener Gruppe. Dafür trägt Gnotchi ab 0.11.0 ein eingebettetes Provisioning-Profil (einmal je Mac: `make profile`). Der Tresor-Schlüssel ist per `.userPresence` an Touch ID gebunden, die fünf Minuten misst Gnotchi selbst. Speicher: SwiftData in `~/Library/Application Support/Gnotchi/Zwischenablage` (0700), schon für den späteren iCloud-Abgleich aufgebaut. Feste Typenliste. HTML und RTF werden nie angezeigt oder geparst. Seitenansicht und Kacheln erscheinen nicht in Bildschirmfreigaben. Protokoll ohne Inhalte, Titel und Quell-Apps. Kürzel über `RegisterEventHotKey`, ohne Event-Tap. Der Tastencode wird aufgenommen, nicht fest eingetragen, denn „<“ hat auf deutschen ISO-Tastaturen den Code 50. SECURE-DESIGN G37–G41. 567 Tests.

## [0.10.0] — 2026-10-23

### Neu
- **Bildschirmfotos landen von selbst in der Ablage.** Einschalten unter Einstellungen → Ablage → „Bildschirmfotos automatisch ablegen“ (ab Werk aus). Jedes neue Bildschirmfoto erscheint als Kachel an der Notch, und du ziehst es von dort direkt in einen Chat, eine Mail oder ein Dokument, ohne es erst im Finder zu suchen. Das klappt mit macOS (⇧⌘3/4/5) und mit CleanShot, auch wenn CleanShot in iCloud Drive speichert. Ein Foto bleibt, bis du es herausziehst oder entfernst. Bildschirmvideos kommen nicht in die Ablage. Liegen die Fotos auf dem Schreibtisch, fragt macOS beim Einschalten einmal nach dem Zugriff. Fotos aus iCloud Drive brauchen manchmal bis zu einer Minute, bis Gnotchi sie sieht.

### Geändert
- **Rausziehen aus der Ablage kopiert immer.** Bisher konnte der Finder eine Datei dabei verschieben, ein Bildschirmfoto verschwand so aus seinem Ordner. Jetzt bleibt das Original, wo es war.

### Intern
- Spotlight-Live-Abfrage auf `kMDItemIsScreenCapture` (setzen macOS und CleanShot), Bereiche Benutzerordner **und iCloud Drive ausdrücklich** – für Apps deckt der Benutzerordner iCloud nicht ab (gemessen). Nur Dateien ab dem Einschalten, nur Bilder, keine App-internen Kopien unter `~/Library/` (CleanShot legt jedes Foto zusätzlich in seinen Verlauf), Kopien eines schon übernommenen Fotos (gleicher Erstellzeitpunkt + Größe) nicht erneut. Die Freigabe-Rückfrage für den Schreibtisch läuft im Hintergrund, auf dem Hauptthread fror Gnotchi bis zur Antwort ein. Protokoll nur mit Zahlen und Gründen, nie Namen oder Pfade. SECURE-DESIGN G36. 543 Tests.

## [0.9.2] — 2026-10-23

### Behoben
- **Anhänge aus Outlook und aus Gmail im Browser lassen sich in die Ablage ziehen.** Bisher ging die Ablage dabei gar nicht erst auf. Beide Programme geben den Anhang beim Ziehen nicht als fertige Datei mit, sondern schreiben ihn erst, wenn das Ziel danach fragt. Gnotchi fragt jetzt danach. Wie bei Fotos landet der Anhang als Kopie in Gnotchis eigenem Ordner und verschwindet mit dem Eintrag wieder. Getestet mit Gmail in Helium, einem Browser auf Chromium-Basis; in Chrome, Edge und Brave sollte es genauso gehen, geprüft ist es dort nicht.
- Das Feld „Hier ablegen“ konnte nach einem abgebrochenen Ziehen offen stehen bleiben. Der Abbruch passiert nicht mehr.

### Intern
- Ablagefläche als AppKit-Ansicht statt SwiftUI-`onDrop`, damit `NSDraggingInfo` zur Verfügung steht. Versprechen ohne `NSFilePromiseItemMetaData` (Outlook, Chromium) über `namesOfPromisedFilesDropped(atDestination:)` in einen frischen UUID-Ordner, angenommen wird nur, was danach geprüft darin liegt (≤ 120 s). `NSFilePromiseReceiver` bleibt für Fotos; bei Chromium hatte er eine Ausnahme geworfen und macOS den Ziehvorgang abgebrochen. Höchstens so viele Kopien wie Plätze frei, Überzähliges wird gelöscht; eigene Kopie nach dem Lesezeichen erneut geprüft. Protokoll beim Wechsel „Ziehen an/aus“ mit Tastenzustand (nur Zahlen). 534 Tests.

## [0.9.1] — 2026-10-23

### Behoben
- **Fotos aus der Fotos-App lassen sich in die Ablage ziehen.** Bisher öffnete sich die Ablage, nahm das Foto aber nicht an und meldete fälschlich „Schon in der Ablage“. Die Fotos-App gibt beim Ziehen nur eine Vorschau als Datei mit, das Original schreibt sie erst auf Anfrage. Gnotchi fragt jetzt danach und legt das Foto in voller Größe als Kopie in einen eigenen Ordner (nur für dich lesbar). Entfernst du das Foto aus der Ablage, löscht Gnotchi diese Kopie. Dateien aus dem Finder bleiben wie bisher, wo sie sind.
- Der Hinweis nach dem Ablegen stimmt jetzt: „Schon in der Ablage“ nur, wenn wirklich alles schon drin war, sonst „Nicht abgelegt“.

### Intern
- Dateiversprechen (`NSFilePromiseReceiver`) nach `~/Library/Application Support/Gnotchi/Ablage-Kopien/<UUID>/`, Ordner 0700, Kopie geprüft (direkt im eigenen Ordner, kein Link). Gelöscht wird nur dort, verwaiste Ordner beim Start (SECURE-DESIGN G32). Eine rausgezogene Kopie löscht Gnotchi erst beim nächsten Start, weil die Ziel-App sie vielleicht noch liest. 530 Tests.

## [0.9.0] — 2026-10-22

Das Wichtigste: Claude Code erscheint jetzt in der Notch. Dazu lehnst du Anrufe ab, ohne danach Apples Fenster wegklicken zu müssen, und siehst, wie viel ungelesen ist.

### Neu
- **Claude Code in der Notch:** Laufende Claude-Code-Sitzungen erscheinen in der Insel. Orange heißt „arbeitet“, gelb „wartet auf Erlaubnis“ (mit Werkzeug und Befehl), grün „fertig“ (mit dem Anfang der Antwort). Ist eine Antwort fertig, klappt die Insel kurz auf. Ein Klick auf die Sitzung holt das Programm nach vorn, in dem sie läuft, etwa Terminal oder Obsidian. Erlauben oder ablehnen musst du weiter in der Sitzung selbst, Gnotchi zeigt nur an. Einschalten unter Aktivitäten → „Claude Code in der Notch“. Gnotchi trägt dafür eigene Einträge in `~/.claude/settings.json` ein und nimmt genau diese beim Ausschalten wieder heraus. Der Rest der Datei bleibt Zeichen für Zeichen gleich. Ab Werk aus.
- **Anruf ablehnen ohne Apples Fenster:** Rot lehnt ab, und Apples Anruf-Fenster ist danach weg. Der Anrufer landet auf der Mailbox. Neu ist der Knopf **Mitlesen**: Der Anrufer spricht auf die Mailbox, und du liest in Apples Fenster mit. In der Notch kannst du dann noch annehmen oder das Mitlesen beenden. Solange es klingelt, ist Apples Anruf-Fenster versteckt, auch wenn dort gerade eine Erinnerung steht.
- **Ungelesen-Zahlen:** Die Zahlen auf den Dock-Symbolen der Apps, die du für Mitteilungen ausgewählt hast, stehen im Band und in der großen Insel. Ein Klick aufs Symbol öffnet die App. Läuft keine Musik, zeigt auch die kleine Insel die Summe (abschaltbar). Gnotchi übernimmt nur Ziffern, nie den Text eines Abzeichens. Es zählen nur Apps, die im Dock liegen. Ab Werk aus.
- **Qotti-Kontingent auch im Band**, beschriftet mit „Codex“ statt „GPT“ wie in Qotti. Zu sehen ist es, sobald Qotti es sendet (ab Qotti 1.5.0).

### Geändert
- Pausierte Musik verschwindet nach 5 Sekunden überall, auch im Band und in der großen Insel. Bisher blieb der letzte Titel stehen, solange etwas anderes die Insel offen hielt.
- Ohne Notch zeigt die kleine Insel den Titel in der freien Mitte, und das Band nutzt die ganze Breite.

### Intern
- Hook-Programm `Contents/Helpers/Gnotchi Claude.app` ohne Berechtigungen, Socket `claude.sock` mit beidseitiger Signaturprüfung. Gesendet werden nur Projektname, Status, Werkzeug, gekürzter Befehl und gekürzte Antwort, nie Eingabe, Verlauf oder Dateiinhalte (SECURE-DESIGN G34). `settings.json` wird nur geändert, wenn sie danach byte-genau gleich bleibt, mit Sicherung (G35). Dock-Abzeichen nur gelesen (G33). „Live-Voicemail stoppen“ nur direkt nach deinem Klick und am selben Anruf (G30). 519 Tests.

## [0.8.0] — 2026-10-22

Mitteilungen, Anrufe, Wetter und eine Ablage für Dateien. 0.6.0 und 0.7.0 sind nie einzeln erschienen, sie stecken hier mit drin.

### Neu
- **Mitteilungen in der Notch:** Mitteilungen der Apps, die du auswählst (etwa Nachrichten, WhatsApp, Telegram, Slack, Mail), erscheinen in der Notch statt oben rechts: App, Titel, Text und die Knöpfe der Mitteilung, zum Beispiel „Erledigt“. Ein Klick öffnet die App an der richtigen Stelle, × schließt sie. Kommen mehrere, zeigt die Insel „+2“. Apples Banner ist so lange weg. Danach liegt die Mitteilung wie immer in der Mitteilungszentrale. Ab Werk aus.
- **Anrufe in der Notch:** Ruft jemand dein iPhone an, zeigt die Notch Name und Anrufart mit grünem Annehmen und rotem Ablehnen. Nach dem Annehmen wird daraus eine Gesprächsleiste mit rotem Auflegen. Apples eigenes Anruf-Fenster bleibt vorerst trotzdem stehen.
- Mitteilungen und Anrufe liest ein eigenes kleines Hilfsprogramm, **„Gnotchi Mitteilungen“**. Nur es bekommt die Bedienungshilfen-Freigabe, Gnotchi selbst nicht. Gnotchi startet es erst, wenn du die Mitteilungen einschaltest.
- **Wetter:** In der großen Insel steht ein Wetter-Symbol. Ein Klick zeigt das Wetter für deinen Ort: Temperatur, gefühlt, Höchst- und Tiefstwert, die nächsten 8 Stunden, 7 Tage, Luftfeuchte, Wind, UV, Luftdruck, Sonnenauf- und -untergang. Den Ort suchst du in den Einstellungen, °C oder °F. Die Daten kommen von Open-Meteo.com, gesendet wird nur der gewählte Ort. Ab Werk aus.
- **Dateiablage:** Zieh Dateien oder Ordner zur Notch und lass sie bei „Hier ablegen“ los. Dort warten sie, bis du sie woanders wieder herausziehst. Die Ablage merkt sich nur, wo die Datei liegt, und vergisst sie nach dem Herausziehen. Liegt etwas darin, hängt unter der großen Insel eine Reihe mit den Dateien, im Band stehen sie neben dem Titel. Die volle Ablage kann Im Finder zeigen, Teilen, AirDrop und ZIP, auf Wunsch mit Passwort (AES-256; öffnen lässt es sich mit Keka, The Unarchiver oder 7-Zip, nicht per Doppelklick).
- **Ruhe-Insel:** Läuft gerade nichts, bleibt die kleine Insel trotzdem da, wenn das Wetter an ist oder etwas in der Ablage liegt. Sie zeigt dann Temperatur oder Anzahl.
- **Einstellungen in Reitern:** Allgemein, Wiedergabe, Aktivitäten, Mitteilungen, Wetter und Ablage statt eines langen Fensters.

### Behoben
- Gnotchi stürzte ab, wenn ein Programm mit Bedienungshilfen (etwa Thaw) die Insel abfragte, während etwas ohne Dauer lief.
- Nach dem Ablegen einer Datei klappte die Insel erst nach mehreren Klicks wieder auf.

### Intern
- Hilfsprogramm `Contents/Library/LoginItems/Gnotchi Mitteilungen.app` ohne Berechtigungen, Socket `notify.sock` mit beidseitiger Signaturprüfung, Mitteilungstexte nie im Protokoll (SECURE-DESIGN G28–G30). Wetter: zwei feste Adressen, keine Weiterleitungen, Antwort höchstens 64 KB und streng geprüft (G31). Ablage: Ziehen wird ohne Freigabe erkannt, ZIP im Programm über libarchive, das Passwort nie als Argument (G32). 479 Tests.

## [0.5.0] — 2026-10-21

Termine, Timer, Spiegel – und eine aufgeräumte große Insel.

### Neu
- **Eine Sache groß:** Die große Insel zeigt nur noch eine Sache, groß und 460 pt breit. Oben steht eine Leiste mit Symbolen für alles, was läuft; ein Klick zeigt diese Sache groß. Vorher stapelten sich Mikrofon, Kontingent, Updates und Musik übereinander.
- **Nächster Termin aus Kalli:** Ab Kalli 0.12.0 erscheint dein nächster Termin 15 Minuten vor Beginn in der Insel, mit Uhrzeit und Restzeit. Ein Klick öffnet den Apple Kalender. Der Titel kommt auf einem geschützten Weg, bei dem beide Apps die Signatur der anderen prüfen.
- **Timer:** 5, 10, 15, 25 Minuten oder eine eigene Zeit (1–180), über das Menü oder die Insel, mit Pause und Stopp. Ist die Zeit um, pulsiert die Insel orange, bis du klickst, und der Ton wiederholt sich höchstens eine Minute. Ton wählbar.
- **Spiegel:** Das Kamera-Symbol in der großen Insel zeigt dein Kamerabild gespiegelt, etwa vor einem Anruf. Die Kamera läuft nur, solange der Spiegel zu sehen ist.
- **Stecknadel:** hält die große Insel offen, dann durchscheinend.
- **Aufklappen als Band:** auf Wunsch seitlich breit in Menüleisten-Höhe statt nach unten.
- **Wiedergabe immer groß** und **Wiedergabe-Knöpfe in der kleinen Insel** als Einstellungen.

### Behoben
- Startet eine Familien-App nach einem Update neu, verschwindet ihr Update-Eintrag jetzt sofort. macOS meldet den Start von Apps ohne Dock-Symbol (Kalli, Tippi) nicht als App-Start; der Eintrag blieb so bis zur stündlichen Prüfung stehen.
- Neben der Notch passt die Restzeit jetzt in den schmalen Flügel („25′“ statt „25:00“, das unter die Notch lief).

### Intern
- Neue Berechtigung **Kamera** (`com.apple.security.device.camera`) nur für den Spiegel; Positivliste im Release-Skript angepasst (SECURE-DESIGN G27). Kalli-Termine über `kalli.sock` (G26), der Socket-Server von Tippis Live-Text ist dafür allgemein geworden. 420 Tests.

## [0.4.0] — 2026-10-21

Enthält auch alles, was für 0.3.0 geplant war. 0.3.0 ist nicht einzeln erschienen.

### Neu
- **Live-Aktivitäten:** Läuft mehr als eine Sache gleichzeitig, wechselt die kleine Insel alle 4 Sekunden zwischen ihnen: Musik, Kopfhörer und Updates. Bleibst du mit der Maus darauf, bleibt sie stehen. Die Tippi-Aufnahme und kurze Hinweise haben weiter Vorrang. Auf Bildschirmen ohne Notch passiert dasselbe in der Pille.
- **Kopfhörer bleiben sichtbar:** Solange der Ton über Bluetooth läuft, zeigt die Insel ein Kopfhörer-Symbol, ohne Notch auch den Namen.
- **Updates der App-Familie:** Meldet Tippi, Kalli, Qotti oder Seam ein bereites Update, steht es in der Insel, bis es installiert ist. Ein Klick öffnet die App bei ihrem Update-Fenster. Gnotchi öffnet dabei nur die echte, signierte App und prüft das vor jedem Start. Gnotchis eigenes Update erscheint dort auch. Die Familien-Apps brauchen dafür jeweils eine Version, die das unterstützt, Kalli kommt zuerst.
- **Neuer Titel:** Beginnt ein neuer Titel, wird die Insel 3 Sekunden breiter und zeigt Titel und Interpret.
- **Medienfilter:** In den Einstellungen bekommt jede Wiedergabe-App einen eigenen Schalter, zum Beispiel Spotify an und Safari aus.
- Neuer Bereich „Live-Aktivitäten“ in den Einstellungen mit „Rotation“, „Kopfhörer-Aktivität“, „Updates der App-Familie“ (alle ab Werk an) und dem Medienfilter.
- **Tippis Live-Vorschau in der Insel:** Ist in Tippi die Live-Vorschau an, klappt die Insel beim Diktat auf und zeigt die letzten zwei Zeilen deines Texts, ältere Wörter laufen vorne raus. Tippis eigene Anzeige bleibt dann weg. Der Text kommt über eine eigene Verbindung, die Gnotchi nur vom echten, signierten Tippi annimmt. Er landet weder in einer Datei noch im Protokoll und ist weg, sobald das Diktat endet. Braucht eine Tippi-Version, die das unterstützt.
- **Qotti-Kontingent:** Läuft Qotti, warnt die Insel kurz, wenn das 5-Stunden-Limit von Claude oder ChatGPT 80 % und 95 % erreicht oder Claude drosselt, mit der Zeit bis zur Zurücksetzung. In der großen Insel steht über der Musik „Claude 42 % · GPT 17 %“. Neuer Schalter „Qotti-Kontingent anzeigen“, ab Werk an. Braucht eine Qotti-Version, die das unterstützt.

## [0.2.1] — 2026-10-21

### Behoben
- **Gnotchi wurde mit der Zeit immer langsamer und hungriger.** Seit 0.2.0 meldete Gnotchi bei jeder Änderung an den Audio- oder Kamerageräten (Kopfhörer, iPhone als Kamera, Bildschirm mit Lautsprechern) alle Beobachter ab und neu an. macOS rief die alten trotzdem weiter auf, und jede Änderung vervierfachte die Arbeit. Nach einem Tag konnte Gnotchi so über 100 % CPU und viel Speicher brauchen, das Symbol in der Menüleiste verschwand. Jetzt bleibt die Arbeit pro Geräteänderung gleich (gemessen: 10 Änderungen ohne messbaren Mehraufwand, vorher nach 5 Änderungen tausendfach).

## [0.2.0] — 2026-10-20

### Neu

- **Tippi-Diktat in der Insel:** Diktierst du mit Tippi, zeigt die Insel ein rotes Mikrofon mit dem Pegel deiner Stimme und danach „wandelt um“. Ohne Notch steht auch die Laufzeit da. Tippi blendet seine eigene Anzeige dann aus. Die Aufnahme hat Vorrang vor Musik und klappt nicht auf. Ist in Tippi die Live-Vorschau an, bleibt Tippis eigene Anzeige, denn Gnotchi zeigt keinen Text. Braucht eine Tippi-Version, die das unterstützt.
- **Mikrofon und Kamera:** Nutzt eine App das Mikrofon, sitzt ein oranger Punkt an der Insel, bei der Kamera ein grüner. Fährst du darüber, steht da, welche App das Mikrofon nutzt. Bei der Kamera nennt macOS keine App.
- **Kopfhörer-Hinweis:** Wechselt der Ton auf Bluetooth-Kopfhörer, zeigt die Insel 3 Sekunden ihren Namen und „Verbunden“, beim Zurückwechseln das neue Gerät und „Kopfhörer getrennt“.
- **Audio-Ausgang wählen:** Oben rechts in der großen Insel sitzt jetzt immer das Ausgabe-Symbol. Ein Klick zeigt alle Ausgabegeräte, die Auswahl gilt sofort für den ganzen Mac.
- Neue Schalter in den Einstellungen: „Kopfhörer-Hinweis“, „Mikrofon & Kamera anzeigen“, „Tippi-Aufnahme anzeigen“, alle ab Werk an. „Musik in der Notch“ aus heißt jetzt nur noch: keine Musik. Die Insel bleibt für die anderen Anzeigen da.

### Behoben

- **Musik aller Apps kommt von allein zurück.** Gnotchi prüft beim Start, ob macOS die Wiedergabe für alle Apps lesen lässt. Scheiterte diese Prüfung einmal, etwa direkt nach dem Einschalten des Macs, blieb Gnotchi bis zum nächsten Start beim Ersatzweg: YouTube im Browser fehlte in der Notch, es liefen nur Spotify und Musik. Jetzt versucht Gnotchi es selbst erneut, nach 5 und 30 Sekunden, nach 2 Minuten und danach alle 5 Minuten, und schaltet um, sobald es klappt. Bis dahin funktionieren Spotify und Musik wie bisher.
- Scheitert die Prüfung, steht der Grund im Systemprotokoll: Zeitlimit, Fehlercode oder Startproblem. Nur Codes, keine Titel und keine App-Namen.

### Datenschutz & Sicherheit

- Keine neue Berechtigung: Ob Mikrofon oder Kamera laufen, liest Gnotchi ohne Freigabe. Gemessen: keine Kamera-Anfrage, beim Mikrofon nur eine stille Vorabprüfung von macOS, kein Dialog.
- Welche App Mikrofon oder Kamera nutzt und wie deine Geräte heißen, steht nur in der Insel, nie im Protokoll.
- Von Tippi erfährt Gnotchi nur Zustand und Pegel, nie Text. Nachrichten mit anderem Aufbau verwirft es, und ohne Meldung blendet es die Aufnahme nach 3 Sekunden aus.
- Den Audio-Ausgang ändert Gnotchi nur auf deinen Klick.

## [0.1.0] — 2026-10-18

Erste Version. Gnotchi ist aus Seam ausgelagert, damit die Mediensteuerung ohne
Bedienungshilfen-Freigabe auskommt.

### Neu

- **Insel in der Notch:** Läuft Musik oder ein Video, zeigt die Notch klein Cover und Pegel. Auf Bildschirmen ohne Notch erscheint dieselbe Insel als Pille oben in der Mitte, auf jedem Bildschirm eine eigene. 5 Sekunden nach dem Pausieren und bei Apps im Vollbild verschwindet sie.
- **Groß beim Darüberfahren:** Cover, App, Titel, Interpret, Zurück, Wiedergabe/Pause und Weiter, darunter ein dünner Fortschrittsbalken mit Zeiten wie im Kontrollzentrum.
- **Alle Quellen:** Spotify, Musik und Browser wie Safari, Edge oder Helium, auch Videos.
- **Spulen** per Klick oder Ziehen im Balken, gesendet beim Loslassen. In Spotify auch über Spotify Connect. Ohne Gesamtzeit (Livestream) ist der Balken gesperrt.
- **Welche App spielt:** Symbol und Name der App über dem Titel, klein ein Abzeichen am Cover.
- **Wo die Musik spielt:** „Auf anderem Gerät“ (etwa Spotify Connect), bei AirPlay oder Bluetooth der Name des Geräts. Bei anderem Gerät und AirPlay zeigt die kleine Insel einen Lautsprecher statt des Pegels.
- **Einstellung „Aufklappen nach“** (Sofort, 0,3 s, 0,6 s, 1 s; ab Werk 0,6 s): Die Insel geht erst auf, wenn die Maus so lange darüber bleibt.
- **Rechtsklick auf die Insel** (oder Ctrl-Klick): Menü mit „Einstellungen …“ und „Hilfe …“.
- **Hinweis bei einer zweiten Notch-App** (z. B. NotchNook) oben im Menü und in den Einstellungen.
- Menüleisten-Symbol mit Einstellungen („Musik in der Notch“, „Aufklappen nach“, „Bei Anmeldung starten“), Hilfe, Update-Suche und Beenden.
- **Ersatzweg:** Lässt macOS den systemweiten Zugriff nicht zu, zeigt und steuert Gnotchi Spotify und Musik direkt.

### Datenschutz & Sicherheit

- **Keine Bedienungshilfen-Freigabe.** Gnotchi fragt nie danach, liest keine Fenstertitel und erzeugt keine Eingaben.
- **Nichts verlässt den Mac** außer der Update-Prüfung. Titel, Interpret und Cover bleiben im Arbeitsspeicher, nie im Protokoll, nie auf der Festplatte.
- **Kein Mithören:** Für den Wiedergabeweg liest Gnotchi nur, ob eine App Ton ausgibt, und Art und Namen des Ausgabegeräts.
- **Automation nur für Spotify und Musik**, angefragt erst beim ersten Spulen in Spotify oder wenn der Ersatzweg greift.
- Der Medien-Adapter startet nur aus einem unveränderten, von Michaels Team signierten Programmpaket. Titel aus dem Strom werden bereinigt, Cover begrenzt dekodiert, Cover-Adressen nie geladen.
- Updates und die Update-Liste sind signiert. Gnotchi installiert nur, was mit Michaels Schlüssel signiert ist.
- Keine echten Hördaten im Quellcode: Beispiele und Testdaten sind erfunden, ein Prüfschritt bei jedem Commit und Release erzwingt das.
