# Gnotchi

**Die Notch zeigt, was gerade läuft. Mit der Maus darüber steuerst du es.**

<img src="assets/render-insel-pille-gross.png" width="520" alt="Gnotchi: große Insel mit Cover, Titel, Tasten und Fortschritt">

Kostenlos und quelloffen (MIT). Für macOS 27 auf Macs mit Apple-Chip. Ohne Konto und ohne Nutzungsstatistik.

---

## Warum es Gnotchi gibt

Die Notch am MacBook ist ein schwarzer Fleck mitten in der Menüleiste. Sie tut nichts. Und wenn
beim Arbeiten Musik läuft oder nebenher ein Video, suche ich zum Pausieren jedes Mal erst die App
oder den richtigen Browser-Tab.

Es gibt Notch-Apps, die das lösen. Die meisten wollen aber viel mehr sein und sehen nach eigener
App aus. Ich wollte eine Insel, die so aussieht, als hätte Apple sie gebaut, und sonst nichts tut.

## Was Gnotchi macht

- Läuft Musik oder ein Video, zeigt die Notch klein das Cover und einen Pegel. Auf Bildschirmen
  ohne Notch sitzt dieselbe Insel als Pille oben in der Mitte.
- Bleibt die Maus kurz darauf, klappt sie auf: Titel, Interpret, Zurück, Pause, Weiter und ein
  Fortschrittsbalken zum Spulen.
- Das funktioniert mit Spotify, Musik und mit Videos in Safari, Edge oder Helium. Egal, in
  welchem Fenster sie gerade liegen.
- Über dem Titel steht, welche App spielt. Läuft der Ton woanders, sagt die Insel es dir: „Auf
  anderem Gerät“ bei Spotify Connect, bei AirPlay oder Bluetooth der Name des Lautsprechers.
- Sie drängt sich nicht auf. Ab Werk klappt sie erst nach 0,6 Sekunden auf (einstellbar), fünf
  Sekunden nach dem Pausieren ist sie weg, und bei Vollbild-Apps bleibt sie aus.

## Wie von Apple

Tiefschwarz, bündig an der Notch, unten weich gerundet. Systemschrift, Aufbau wie die Wiedergabe
im Kontrollzentrum. In der Notch steht kein Logo und keine eigene Farbe.

## Datenschutz

Gnotchi braucht keine Bedienungshilfen-Freigabe. Es liest keine Fenstertitel und löst keine
Eingaben aus.

Titel, Interpret und Cover bleiben im Arbeitsspeicher deines Macs. Ins Netz geht Gnotchi nur, um
nach Updates zu suchen. Im Systemprotokoll steht nicht, was du hörst.

Für den Hinweis „Auf anderem Gerät“ fragt Gnotchi nur ab, ob eine App gerade Ton ausgibt. Es hört
nichts mit und nimmt nichts auf.

Der Code ist offen. Jede dieser Aussagen lässt sich dort und im Sicherheitsentwurf nachprüfen.

## Voraussetzungen

macOS 27 auf einem Mac mit Apple-Chip. Mit Notch am schönsten, ohne Notch läuft es als Pille.
Beim ersten Spulen in Spotify fragt macOS einmal, ob Gnotchi Spotify steuern darf. Dieselbe Frage
kann für Musik kommen, falls macOS den normalen Zugriff auf die Wiedergabe sperrt.

## So bekommst du Gnotchi

Version 0.1.0 gibt es als signierte, von Apple notarisierte App unter
[GitHub-Releases](https://github.com/miwixyz/Gnotchi/releases/latest). Danach aktualisiert sich
Gnotchi selbst, wenn du es erlaubst. Eine Website unter gnotchi.mwlr.dev ist geplant.

---

Gnotchi ist ein Projekt von Michael Wildenauer.
