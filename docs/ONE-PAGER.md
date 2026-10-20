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

## Was sonst noch in der Notch landet

- Diktierst du mit [Tippi](https://github.com/miwixyz/Tippi), steht in der Notch ein rotes
  Mikrofon mit dem Pegel deiner Stimme. Tippis eigene Anzeige bleibt dann weg. Mit Tippis
  Live-Vorschau klappt die Insel auf und zeigt die letzten zwei Zeilen, während du sprichst.
- Ein oranger Punkt heißt: Eine App nutzt das Mikrofon. Grün ist die Kamera. Welche App am
  Mikrofon hängt, siehst du, wenn du mit der Maus darüberfährst.
- Kopfhörer verbunden? Die Notch zeigt drei Sekunden lang ihren Namen.
- Oben rechts in der großen Insel sitzt das Ausgabe-Symbol. Ein Klick, und der Ton kommt aus einem
  anderen Gerät.

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

Ob eine App Mikrofon oder Kamera nutzt, erfährt Gnotchi ohne eigene Freigabe. Den App-Namen zeigt es
nur in der Insel, im Protokoll steht er nicht. Von Tippi kommt „nimmt auf“ und der Pegel. Den Text der
Live-Vorschau bekommt Gnotchi nur auf einem geschützten Weg, den andere Programme nicht nutzen können.
Er steht nur in der Insel, gespeichert oder protokolliert wird er nicht.

Der Code ist offen. Jede dieser Aussagen lässt sich dort und im Sicherheitsentwurf nachprüfen.

## Voraussetzungen

macOS 27 auf einem Mac mit Apple-Chip. Mit Notch am schönsten, ohne Notch läuft es als Pille.
Beim ersten Spulen in Spotify fragt macOS einmal, ob Gnotchi Spotify steuern darf. Dieselbe Frage
kann für Musik kommen, falls macOS den normalen Zugriff auf die Wiedergabe sperrt.

## So bekommst du Gnotchi

Version 0.2.0 gibt es als signierte, von Apple notarisierte App unter
[GitHub-Releases](https://github.com/miwixyz/Gnotchi/releases/latest). Danach aktualisiert sich
Gnotchi selbst, wenn du es erlaubst. Eine Website unter gnotchi.mwlr.dev ist geplant.

---

Gnotchi ist ein Projekt von Michael Wildenauer.
