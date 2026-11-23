# Gnotchi – Ablage-Feinschliff: Vorschau, Mehrfachauswahl, Rückgängig (Entwurf, Sicherheitsentwurf G64)

Stand 2026-11-23 (Mac mini). Entwurf, **noch kein Code, nichts entschieden**. Anlass: Vergleich mit Tendedero
(`alejandrobujan/tendedero`, MIT, nur Ideen, kein Code übernommen) und Michaels Frage „Was war mit der Idee einer Leine?“.

## Zur Leine: nicht als eigene Fläche

Tendederos **Leine** ist ein Streifen am oberen Bildschirmrand, an dem Bildschirmfotos und Kopiertes hängen, mit Gesten und Suche.
Gnotchi ist in der Sache schon so eine Fläche (Insel an der Notch, Pille oben mittig auf Bildschirmen ohne Notch): Ablage seit 0.8.0,
Bildschirmfotos seit 0.10.0, Zwischenablage-Verlauf, Bildtext-Suche (der erkannte Text liegt dort **verschlüsselt**, AES-GCM, G50).
Eine zweite Fläche würde dasselbe doppelt zeigen. **Entscheidung (Vorschlag): keine eigene Leine.** Übernommen wird, was der
Ablage fehlt (unten). Will Michael doch eine Leine, wäre das ein eigenes Vorhaben mit der Frage, was sie kann, das die Insel nicht kann.

## Stand der Ablage (aus Code und Spec 0.8.0, 23.11.)

- Kacheln mit Symbol und Name, Rechtsklick-Menü (im Code vorhanden, Einträge laut Spec 0.8.0): Im Finder zeigen, Teilen …, AirDrop, Entfernen. Unten **für alle**: Teilen …, AirDrop, ZIP,
  ZIP mit Passwort, Leeren. Rausziehen entfernt den Eintrag (Schalter), **„Zurückholen“** (0.18) holt rausgezogene Einträge zurück
  (`ShelfStore.restore`). Höchstens 50 Einträge.
- **Keine** Schnellansicht, **keine** Auswahl einzelner Kacheln, **kein** Rückgängig für Entfernen und Leeren, **keine** Vergrößerung
  beim Überfahren (Suche in `Gnotchi/Shelf`, `Gnotchi/Clipboard` nach QuickLook, Auswahl, Undo, Hover: keine Treffer).
- Knippi-Fotos fehlten in der Bildschirmfoto-Ablage, weil Knippi das Spotlight-Merkmal nicht setzte. **Behoben in Knippi 0.5.4** (Merkmal wird
  beim Sichern und nach dem Ersetzen im Editor gesetzt; gemessen: Spotlight meldet die Datei nach rund 6 s). Noch nicht gemessen:
  die Strecke Knippi → Gnotchi-Ablage von Ende zu Ende am echten Gerät, und ältere Knippi-Fotos bleiben unmarkiert.

## Was die Insel kann und nicht kann (bestimmt die Lösung)

- Das Insel-Fenster ist **nie aktiv und nimmt keine Tastatur an** (`IslandPanel`, `allowsKey` nur für das Namensfeld der Timer-Auswahl).
  **G1** verbietet globale Tasten-Beobachter. Folge: **Leertaste und ⌘Z gehen in der Ablage nicht** (anders als in Knippi). Bedienung also
  über **Maus, Modifikator-Tasten beim Klick** (lesbar im Klick-Ereignis, ohne Beobachter) und **Knöpfe**.
- Das Insel-Fenster ist **nie in Bildschirmfreigabe und -aufnahme** (`sharingType = .none`, G58). Ein **Quick-Look-Fenster** des Systems wäre
  ein eigenes Fenster, in einer Freigabe sichtbar, und stünde außerhalb dieser Regel. Darum **keine Systemansicht, sondern Vorschau in der Insel selbst**.
- Das Seitenpanel des Zwischenablage-Verlaufs (`ClipboardPanel`) **kann** Tastatur (lokaler Tasten-Beobachter, G-Muster der Zwischenablage). Dort wäre
  die Leertaste möglich (nicht Teil dieses Entwurfs, siehe offene Fragen).

## Idee 1 – Vorschau in der Insel („Zoom beim Überfahren“)

Ruht der Zeiger **etwa 0,6 s** auf einer Bild-Kachel (oder Rechtsklick → **Vorschau**), erscheint eine größere Vorschau **in der großen Insel**,
über den Kacheln, kein neues Fenster. Wegbewegen oder Esc (nur wenn Fokus) schließt sie. Nur für Bilder und PDFs (erste Seite); andere Dateien: nichts.
Vorschaubild aus ImageIO/PDFKit mit Höchstgröße und Pixelgrenze (gleiche Regel wie in G63), nie die ganze Datei dekodieren.
**Schalter** „Vorschau beim Überfahren“, ab Werk **an**.

## Idee 2 – Mehrfachauswahl

**Shift- oder ⌘-Klick** auf eine Kachel wählt sie (blauer Rand) oder nimmt sie heraus; ein normaler Klick hebt die Auswahl auf. Die untere Leiste zeigt
„3 gewählt“ und wirkt dann **nur auf die Auswahl**: Teilen …, AirDrop, ZIP, Entfernen (bei Auswahl; **Leeren** bleibt „alle“). Ohne Auswahl wie bisher auf alle.
Auswahl liegt nur im Speicher, ist nach Schließen der Insel weg.

## Idee 3 – Rückgängig statt Taste

Nach **Entfernen** oder **Leeren** erscheint in der unteren Leiste **10 Sekunden** lang **„Rückgängig“**. Ein Klick holt die entfernten Einträge zurück
(`ShelfStore.restore`, Höchstzahl 50 und doppelte Einträge werden wie dort behandelt). Nur der **letzte** Vorgang. Wird die Insel geschlossen, gilt die Frist weiter,
beim Beenden von Gnotchi verfällt sie. Gelöscht werden dabei ohnehin nie Dateien (die Ablage hält Verweise), nur die Einträge.

## Entscheidungen (offen, Michael)

1. Keine eigene Leine, nur dieser Feinschliff? (Vorschlag: ja.)
2. Vorschau in der Insel (Vorschlag) oder doch Systemansicht (Quick Look) im eigenen Fenster?
3. Vorschau beim Überfahren ab Werk an oder aus?
4. Soll die Leertaste im Seitenpanel des Zwischenablage-Verlaufs eine Schnellansicht öffnen (dort möglich)?
5. Nummer: Vorschlag **0.42.0** für diesen Feinschliff, „Umwandeln“ (`2026-11-23-gnotchi-ablage-umwandeln.md`) danach **0.43.0**.

## Sicherheitsentwurf G64 – Vorschau, Auswahl, Rückgängig (Skizze, vor dem Bau auszuarbeiten)

**Grenzen:** Ablage-Eintrag → Datei lesen für die Vorschau (Lesezeichen auflösen, wie ZIP) · Decoder (ImageIO, PDFKit) auf **fremden Dateien** ·
Klick-Ereignis → Auswahl (Modifikator-Tasten) · Frist → Rückgängig.

- **Keine neue Eingabe-Grenze:** Modifikator-Tasten kommen aus dem Klick-Ereignis der Kachel; kein Tasten-Beobachter, keine Bedienungshilfen (G1).
- **Vorschau bleibt im Insel-Fenster** (`sharingType .none`, G58), kein Systemfenster, kein Dateiname im Fenstertitel, nichts im Protokoll außer Anzahl und Ausgang.
- **Decoder-Grenzen:** Pixelgrenze (400 MP lehnt ab statt zu öffnen), Vorschau höchstens 1600 px, Zeitlimit, bei Fehler nur das Symbol der Kachel; PDFs nur erste Seite.
- **Symbolische Links** wie beim ZIP nicht geöffnet; Ordner ohne Vorschau.
- **Rückgängig:** hält nur die Einträge des letzten Vorgangs im Speicher (Verweise, keine Dateiinhalte), 10 s Frist, danach verworfen. Keine Datei wird je gelöscht.
- **Auswahl** nur im Speicher, nie gespeichert, nie ins Protokoll.

## Testfälle (Skizze)

1. Zeiger ruht 0,6 s auf PNG: Vorschau erscheint **in** der Insel (Fensterliste unverändert), Wegbewegen schließt.
2. Bild mit 400 MP und defektes Bild: kein Absturz, kein Speicherspitze über Grenze (messen), Kachel zeigt weiter ihr Symbol.
3. Shift-Klick auf drei Kacheln, dann ZIP: nur diese drei im Archiv; ohne Auswahl alle.
4. Normaler Klick nach Auswahl hebt sie auf; Auswahl überlebt das Schließen der Insel nicht.
5. Entfernen von zwei Einträgen, „Rückgängig“ innerhalb 10 s: beide zurück an ihrer Stelle; nach 11 s: Knopf weg.
6. Leeren, dann „Rückgängig“ bei voller Ablage (50): nur so viele zurück, wie Platz ist (wie `restore`), Hinweis.
7. Auswirkung auf **Bildschirmfreigabe**: Vorschau ist im geteilten Bild nicht zu sehen (wie die Insel, G58), gegenprüfen mit `CGWindowListCopyWindowInfo` und einem Freigabe-Test.
8. Knippi-Foto (0.5.4) erscheint in der Bildschirmfoto-Ablage (Ende-zu-Ende, einmal am echten Gerät).

## Umfang

- **Drin (nach Entscheidung):** Vorschau beim Überfahren, Mehrfachauswahl, Rückgängig-Knopf, Einstellung, Hilfe, README, Tests, G64 in `docs/SECURE-DESIGN.md`.
- **Nicht drin:** eigene Leine, Tasten-Kürzel in der Ablage (G1), System-Quick-Look-Fenster (Vorschlag), Umwandeln (eigener Entwurf), neue Dateiformate.
