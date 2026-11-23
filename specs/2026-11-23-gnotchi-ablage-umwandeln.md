# Gnotchi – Ablage: Umwandeln und überwachte Ordner (Entwurf, Sicherheitsentwurf G63)

Stand 2026-11-23 (Mac mini). Entwurf, **noch kein Code, keine Entscheidung gefallen**. Anlass: Vergleich mit Droppy
(getdroppy.app, geschlossen, nur Ideenquelle, kein Code und keine Texte übernehmen). Wunsch Michael 23.11.: „Transform in die
0.6.0-Spec aufnehmen“.

## Zur Nummer: nicht 0.6.0

In `specs/` ist **0.6.0 = Mitteilungen und Anrufe**. Die **Dateiablage ist seit 0.8.0 gebaut** (`specs/2026-10-22-gnotchi-0.8.0-ablage.md`,
Sicherheitsentwurf G32), die Zeile „0.6.0 Dateiablage“ im Fahrplan vom 21.10. ist überholt. Gnotchi steht bei **0.41.0**
(CHANGELOG, 22.11.). Dieser Entwurf erweitert die bestehende Ablage und bekommt die **nächste freie Stufe nach dem Feinschliff**
(`2026-11-23-gnotchi-ablage-feinschliff.md`, Vorschlag 0.42.0): also **0.43.0**, bei Baubeginn festlegen.

## Stand der Ablage (gemessen im Code, 23.11.)

- **Seit 0.8.0:** Dateien und Ordner als **Verweise** (Lesezeichen, keine Kopien), höchstens 50 Einträge, Rausziehen, Teilen …,
  AirDrop, **ZIP** (auch AES-256 mit Passwort, `ShelfZip`, libarchive im Prozess), Stapel (`ShelfStore.stacks`), Ergebnisse
  landen in **Downloads** und danach selbst in der Ablage.
- **Seit 0.10.0:** Bildschirmfotos kommen automatisch in die Ablage (Schalter, ab Werk aus). Erkennung über das
  Spotlight-Merkmal `kMDItemIsScreenCapture` (macOS und CleanShot), nicht über einen festen Ordner.
- **Bildtext-Suche** (`specs/2026-11-14-gnotchi-bildtext-suche.md`) existiert.

Daraus folgt für Droppys Funktionsliste: **ZIP ist da**, „Datei ablegen, Teilen, AirDrop“ ist da. Neu wären nur die zwei Punkte unten.

## Idee 1 – Umwandeln („Transform“)

Datei(en) in der Ablage wählen, **Umwandeln ▸** im Rechtsklick-Menü und in der unteren Leiste. Das Ergebnis ist **eine neue
Datei**, das Original bleibt unberührt (nie überschreiben, `ShelfZip.uniqueURL`-Muster), Ziel **Downloads**, das Ergebnis liegt
danach selbst in der Ablage. Alles lokal, kein Netz.

| Umwandlung | Für | Bausteine (zu messen, nicht angenommen) |
|---|---|---|
| Bildformat ändern (PNG ↔ JPEG ↔ HEIC) | Bilder | ImageIO, Qualitätsstufe fest (Standard 0,85) |
| Bild verkleinern (lange Seite 2048 / 1280 / 800 px) | Bilder | ImageIO-Vorschaubild mit Höchstgröße, **Ortsdaten (GPS) und Kameradaten entfernen** als Schalter, ab Werk an |
| Video komprimieren (1080p / 720p) | Videos | `AVAssetExportSession` mit Preset; Fortschritt und Abbruch |
| Zu einem PDF zusammenfügen | mehrere Bilder oder PDFs | PDFKit: je Bild eine Seite, PDFs hintereinander, Reihenfolge wie in der Ablage |

**Nicht Teil davon:** Texterkennung (steht bei Bildtext-Suche und in Knippi), Dokumentformate (Word, Excel), Audio, eigene
Skripte, Shell-Werkzeuge wie ffmpeg (siehe G63). Umbenennen/Sortieren von Filmmaterial bleibt bei `material-rename`.

**Vor dem Bau messen (Michaels echte Dateien, nicht Beispiele):** Zeit und Größe von 5 typischen Screenshots (PNG → JPEG),
einem iPhone-Foto (HEIC → JPEG, mit und ohne Ortsdaten), einem Bildschirmvideo von Knippi (MP4, 1080p → 720p) und von drei Fotos
zu einem PDF. Dazu Speicherspitze bei einem sehr großen Bild (36 MP, Knippi-Messung: 650 MB bei Vision, hier nur ImageIO).

## Idee 2 – Überwachte Ordner und Knippi

**Messung (23.11., Knippi-Code):** Knippi setzt `kMDItemIsScreenCapture` an seinen Fotos **nicht** (keine Treffer im Code). Gnotchis
Bildschirmfoto-Erkennung (0.10.0) sieht Knippi-Aufnahmen deshalb **nicht**. (Ungemessen: ob Spotlight das Merkmal an Knippi-Dateien
nach dem Setzen genauso schnell meldet wie bei CleanShot, ~3 s.)

Zwei Wege, **sie schließen sich nicht aus**:

- **A (klein, Empfehlung zuerst):** Knippi markiert seine gesicherten Bildschirmfotos als Bildschirmfoto (Spotlight-Merkmal
  `kMDItemIsScreenCapture`, wie macOS und CleanShot). Eine Zeile am Schreibort in Knippis `ScreenshotSaver`; Gnotchi muss nichts
  lernen, und jede App, die auf dieses Merkmal achtet, sieht Knippi-Fotos. Aufwand: klein, aber **ein Knippi-Release**.
- **B (allgemein):** Gnotchi bekommt **überwachte Ordner**, höchstens drei, ab Werk **keiner**. Neue Dateien (Bild, PDF, Video) erscheinen
  als Verweise in der Ablage. Ein-Klick-Vorschlag „Knippi-Ordner“ liest Knippis Einstellung `exportLocation` (`defaults`, kein Ordnerraten).
  Aufwand: größer (Dateisystem-Beobachtung, Freigabe für Ordner unter Dokumente/Schreibtisch, Dubletten mit 0.10.0 vermeiden).

**Frage an Michael:** reicht A, oder soll Gnotchi überhaupt beliebige Ordner beobachten (Downloads, Fotos-Export, Scans)? Sagt er „reicht A“,
entfällt B.

## Entscheidungen (Michael, 23.11.)

1. **Umfang 0.43.0:** Bild verkleinern, Bildformat ändern, zu einem PDF zusammenfügen. **Video erst nach Messung** an echten Dateien (eigene Stufe).
2. **Ziel:** **Downloads**, einheitlich mit ZIP; das Ergebnis liegt danach auch in der Ablage.
3. **Überwachte Ordner (B): entfällt.** Knippi 0.5.4 markiert seine Fotos als Bildschirmfoto, Ende zu Ende am echten Gerät bestätigt (23.11.). Idee A ist erledigt.
4. **Ortsdaten bei jeder Bildumwandlung ab Werk entfernen** (Verkleinern **und** Formatwechsel; Schalter „Ortsdaten entfernen“, abschaltbar; Michael 23.11. „ja, ab Werk entfernen“). Technisch: beide Wege über das Vorschaubild (kein Metadaten-Pfad), Ausrichtung wird eingerechnet. Umwandeln selbst läuft nur auf Klick, keine Hintergrundarbeit.

**Nächster Schritt:** Messung an Michaels echten Dateien (siehe „Vor dem Bau messen“), dann Sicherheitsentwurf G63 ausarbeiten, dann bauen. Nummer 0.43.0 bei Baubeginn bestätigen.

## Messung 23.11. (Mac mini, `tools/transform-probe`, **synthetische Testdateien**, nicht Michaels echte)

Erfundene Bilder (Verläufe plus bunte Flächen als „Details“): 5 Screenshots 2880×1800 PNG, 3 JPEG 12 MP, 1 HEIC 12 MP mit Ortsdaten, 1 JPEG 36 MP, 2 PDFs. **Zeiten und Speicher taugen als Größenordnung, die Dateigrößen nicht** (echte Fotos komprimieren anders als erfundene).

- **Zeit:** jede Umwandlung 40 bis 210 ms, auch das 36-MP-Bild (JPEG 0,85 voll 205 ms, auf 2048 px 94 ms). Kein Fortschrittsbalken nötig für Bilder.
- **Speicherspitze:** 130 MB für alle zehn Bilder nacheinander (inkl. 36 MP), PDF aus 3 Bildern + 2 PDFs 173 MB, 331 ms Aufbau. Unkritisch.
- **Ortsdaten:** Der reine Formatwechsel (Pfad „Metadaten behalten“) **behält GPS** (HEIC und JPEG „ja“ → „ja“). Der Verkleinern-Weg (Vorschaubild) **entfernt** sie in allen Fällen. Folge: Wer GPS ab Werk loswerden will, muss den Formatwechsel ebenfalls über den Vorschaubild-Weg schicken oder die Metadaten gezielt streichen. **Entschieden: auch beim Formatwechsel ab Werk entfernen** (Schalter).
- **Format ≠ Verkleinern:** HEIC → JPEG in voller Größe wird **größer** (1440 → 3345 KB). Wer Platz sparen will, braucht „Verkleinern“, nicht „Format“; im Menü beides klar trennen, bei HEIC → JPEG den Zweck „zum Weitergeben“ nennen.
- **Nicht gemessen:** echte Fotos und Screenshots (Dateigrößen), Video, sehr große PDFs. Die Probe kommt mit Michaels Dateien erneut (`/tmp/transform-probe <ordner>`).

## Sicherheitsentwurf G63 – Umwandeln fremder Dateien (Skizze, vor dem Bau auszuarbeiten)

**Grenzen:** Ablage-Eintrag → Datei lesen (Lesezeichen auflösen, wie ZIP) · Decoder (ImageIO, AVFoundation, PDFKit) auf **fremden
Dateien** · Schreiben nach Downloads · (B) Ordner → neue Einträge.

- **Nur Systemdecoder im Prozess**, keine Shell, kein ffmpeg, keine externen Programme (kein Befehls-Einschleusen über Dateinamen).
- **Nie überschreiben:** immer neue Datei mit eindeutigem Namen; Dateiname aus dem Original, gesäubert (`ShelfZip.safeComponent`).
- **Symbolische Links** übersprungen wie beim ZIP; Ordner nicht rekursiv umwandeln.
- **Grenzen gegen Ressourcenmissbrauch:** Höchstgröße je Datei und je Auftrag, Pixelgrenze (Bild mit 400 MP wird abgelehnt statt
  geöffnet, gleiche Regel wie in Knippis Suchindex), Zeitlimit, Abbruch-Knopf, ein Auftrag zugleich.
- **Quarantäne-Merkmal** vom Original auf das Ergebnis übertragen (`ShelfZip.copyQuarantine`).
- **Ortsdaten:** Beim Verkleinern ab Werk entfernen, damit ein Foto, das zum Teilen verkleinert wird, nicht den Aufnahmeort mitgibt.
- **Fehler sichtbar:** kein stilles Weglassen; „3 von 4 umgewandelt, 1 fehlgeschlagen: Name“.
- ~~(B) **Überwachte Ordner:** nur Lesen, nie ändern oder löschen; macOS fragt bei geschützten Ordnern selbst nach Freigabe, Gnotchi
  fragt nicht nach Vollzugriff; Pfad aus Knippis `exportLocation` wird nur als Vorschlag angezeigt, nie ungefragt übernommen.~~ (entfällt, siehe Entscheidung 3)

## Testfälle (Skizze)

1. 5 PNG → JPEG: Größe kleiner, Original unverändert, Name eindeutig bei zweitem Lauf.
2. HEIC mit GPS → JPEG: Ortsdaten weg (Prüfung mit `mdls`/EXIF), Ausrichtung stimmt.
3. 36-MP-Bild verkleinern: Speicherspitze gemessen, Ergebnis lesbar.
4. Video 1080p → 720p: Dauer gleich, Ton da, Abbruch mitten drin lässt keine halbe Datei zurück.
5. Drei Bilder + ein PDF → ein PDF: Seitenzahl und Reihenfolge.
6. Defekte, leere und zu große Datei: sichtbare Meldung, Rest läuft weiter.
7. Symbolischer Link in der Auswahl: übersprungen und gemeldet.
8. ~~(B) überwachte Ordner~~ (entfällt).

## Umfang

- **Drin (nach Entscheidung):** Umwandeln im Rechtsklick-Menü und in der unteren Leiste der Ablage, Einstellungskarte, Hilfe und README,
  Tests, Stand in `docs/SECURE-DESIGN.md` als G63.
- **Nicht drin:** Cloud, Konten, Skripte, Audio, Dokumentformate, Umbenennen.
- **Einmal gemessen:** Zeit und Größe an Michaels Dateien (siehe oben), bevor die Stufen festgelegt werden.
