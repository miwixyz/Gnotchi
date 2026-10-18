<!-- Entwurf, vor Veröffentlichung durch /humanizer -->
# Gnotchi

**Die Notch zeigt, was gerade läuft, und ein Blick mit der Maus reicht, um es zu steuern.**

<img src="assets/render-insel-pille-gross.png" width="520" alt="Gnotchi: große Insel mit Cover, Titel, Tasten und Fortschritt">

Kostenlos · Open Source (MIT) · für macOS 27 auf Macs mit Apple-Chip · kein Konto, keine Analyse

---

## Das Problem

Die Notch des MacBook ist ein schwarzer Fleck mitten in der Menüleiste, der nichts tut. Und wer
beim Arbeiten Musik hört oder nebenher ein Video laufen hat, sucht zum Pausieren oder Weiterspringen
erst die richtige App, das richtige Fenster oder den richtigen Browser-Tab.

## Was Gnotchi macht

- Läuft Musik oder ein Video, zeigt die Notch klein das Cover und einen Pegel. Auf Bildschirmen
  ohne Notch sitzt dieselbe Insel als Pille oben in der Mitte.
- Fährst du mit der Maus darüber, geht sie auf: Titel, Interpret, Zurück, Pause, Weiter und ein
  Fortschrittsbalken, in dem du per Klick spulst.
- Das klappt für Spotify, Musik und Browser wie Safari, Edge oder Helium, egal in welchem Fenster
  sie gerade liegen.
- Die Insel zeigt, welche App spielt und wo der Ton herauskommt: „Auf anderem Gerät“ bei Spotify
  Connect, sonst der Name des AirPlay-Lautsprechers oder der Bluetooth-Kopfhörer.
- Sie bleibt aus dem Weg. Ab Werk geht sie erst nach 0,6 Sekunden auf, 5 Sekunden nach dem
  Pausieren verschwindet sie, und bei Apps im Vollbild ist sie gar nicht da.

## Sieht aus wie von Apple

Die Insel ist tiefschwarz, liegt bündig an der Notch und rundet sich unten weich ab. Sie nutzt die
Systemschrift und ist aufgebaut wie die Wiedergabe im Kontrollzentrum. Es gibt kein eigenes
Farbschema, keinen Rahmen und kein Gnotchi-Logo in der Notch.

## Datenschutz als Argument

- **Keine Bedienungshilfen-Freigabe.** Gnotchi fragt nie danach, liest keine Fenstertitel und
  löst keine Eingaben aus.
- **Nichts verlässt deinen Mac** außer der Suche nach Updates. Titel, Interpret und Cover bleiben
  im Arbeitsspeicher.
- **Keine Titel im Protokoll.** Was du hörst, steht nirgends geschrieben.
- **Kein Mithören.** Für „Auf anderem Gerät“ fragt Gnotchi nur ab, ob eine App gerade Ton ausgibt.
- **Quelloffen unter MIT.** Jede dieser Aussagen lässt sich im Code und im Sicherheitsentwurf
  nachprüfen.

## Voraussetzungen

macOS 27 auf einem Mac mit Apple-Chip. Mit Notch am schönsten, ohne Notch läuft es als Pille.
macOS fragt höchstens einmal, ob Gnotchi Spotify steuern darf, und zwar beim ersten Spulen in
Spotify.

## So bekommst du Gnotchi

Version 0.1.0 folgt, signiert und von Apple notarisiert. Danach aktualisiert sich Gnotchi selbst,
wenn du es erlaubst. Eine Website unter gnotchi.mwlr.dev ist geplant.

---

Gnotchi ist ein Projekt von Michael Wildenauer.
