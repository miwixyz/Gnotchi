# Changelog

Alle nennenswerten Änderungen an Gnotchi. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## [Unreleased]

### Neu
- **Tippis Live-Vorschau in der Insel:** Ist in Tippi die Live-Vorschau an, klappt die Insel beim Diktat auf und zeigt die letzten zwei Zeilen deines Texts, ältere Wörter laufen vorne raus. Tippis eigene Anzeige bleibt dann weg. Der Text kommt über eine eigene Verbindung, die Gnotchi nur vom echten, signierten Tippi annimmt. Er landet weder in einer Datei noch im Protokoll und ist weg, sobald das Diktat endet. Braucht eine Tippi-Version, die das unterstützt.

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
