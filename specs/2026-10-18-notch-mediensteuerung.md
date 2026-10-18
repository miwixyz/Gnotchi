# Seam – Mediensteuerung in der Notch (Design)

> **Herkunft:** Entstanden am 18.10. im Seam-Repo (Zweig feature/notch-medien), am 18.10. nach Gnotchi verschoben; Aufgaben 1–7 umgesetzt, Aufgaben 8–15 folgen hier; Seam-Bezüge (Engine, Abdunkeln, SettingsView) gelten sinngemäß für Gnotchi. Pfade: `Seam/Notch/*` → `Gnotchi/Media/*`, `SeamTests/` → `GnotchiTests/`; Sicherheitsentscheidungen E17a–i → `docs/SECURE-DESIGN.md` G2–G10. Übernommen aus Seam-Commit dc0e71d.

Stand 2026-10-18 · Entschieden mit Michael im Brainstorming · Status: Entwurf, wartet auf Freigabe

## Ziel

Läuft Musik oder ein Video, zeigt Seam in der MacBook-Notch eine Insel im Stil von Apples
Dynamic Island: klein mit Cover und Pegel, beim Darüberfahren groß mit Titel, Interpret, Tasten
und Fortschritt. Auf Bildschirmen ohne Notch (Mac mini, externe Monitore) erscheint dieselbe
Insel als Pille oben mittig. Erster Teil einer möglichen Notch-Reihe; weitere Funktionen
(Ablage, Zwischenablage, Termine …) sind **nicht** Teil dieses Entwurfs.

**Erfolg =** auf MacBook (Notch) und einem Bildschirm ohne Notch werden Spotify, Music,
YouTube in Helium, Edge und Safari angezeigt und lassen sich per Insel pausieren, weiterschalten
und spulen; die Insel wirkt wie ein Teil von macOS.

## Entscheidungen (Michael, 18.10.)

| Frage | Entscheidung |
|---|---|
| Erste Notch-Funktion | Mediensteuerung |
| Ohne Notch | nachgebaute Insel oben mittig |
| Quellen | Spotify, Music, Browser, Podcasts/Sonstiges – also systemweit |
| Verhalten | klein bei Wiedergabe, groß beim Darüberfahren, sonst unsichtbar |
| Weg | `mediaremote-adapter` (BSD) über `/usr/bin/perl`, Rückfall AppleScript |
| Stil | Systemstil: SF Pro, Weiß/Grau, tiefschwarz – Ausnahme vom App-Familie-Design nur für die Insel |

## Messung vorab (MacBook Air M5, macOS 27.0.1, 18.10.)

`media-control` 0.7.7 (Homebrew, gleicher Adapter): `test` → Exit 0.
Mitschnitt `spike/nowplaying-mitschnitt-2026-10-18.jsonl`.

| Quelle | `bundleIdentifier` | Titel/Interpret | Dauer | Pause |
|---|---|---|---|---|
| Spotify | `com.spotify.client` | ✓ | ✓ | – |
| Music | `com.apple.Music` | ✓ | ✓ | ✓ |
| Helium | `net.imput.helium` | ✓ | ✓ | ✓ |
| Edge | `com.microsoft.edgemac` | ✓ | ✓ | ✓ |
| Safari | `com.apple.WebKit.GPU`, Eltern `com.apple.Safari` | ✓ | ✓ | ✓ |

Steuern (Spotify): pause, play, seek 60, next, previous – alle wirksam binnen 1,5 s. Cover JPEG
110–140 KB. **Nicht gemessen:** Steuern von Browser-Medien → erster Prüfpunkt im Prototyp.

Funde: Safari meldet den WebKit-Hilfsprozess (Eltern-ID nutzen) · Browser liefern zuerst Titel
ohne Interpret/Dauer, Sekundenbruchteile später vollständig · Werbung erscheint als eigener Titel.

## Aufbau (`Seam/Notch/`)

1. **`NowPlayingSource`** (Protokoll) mit zwei Umsetzungen:
   - `AdapterSource`: startet `/usr/bin/perl <Bundle>/mediaremote-adapter.pl <Bundle>/MediaRemoteAdapter.framework stream --micros --debounce=100`, liest JSON-Zeilen von stdout. Beim Start einmal `test` (Timeout 10 s).
   - `AppleScriptSource`: Spotify + Music per `tell application`, Abfrage im Sekundentakt nur, solange eine der beiden läuft.
2. **`NowPlayingModel`**: ein Zustand für die Oberfläche. Eltern-ID statt Hilfsprozess; halbe Meldungen ~300 ms zusammenführen; Fortschritt aus `elapsedTime` + `timestamp` + `playbackRate` hochrechnen; Cover dekodieren und je `contentItemIdentifier` zwischenspeichern.
3. **`MediaCommands`**: play/pause, next, previous, seek über dieselbe Quelle (`send <ID>`, `seek`), ersatzweise AppleScript.
4. **`IslandPanel`**: je Bildschirm ein `NSPanel` (nicht aktivierend, `level = .mainMenu + 3`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`). Notch-Lage aus `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` + `safeAreaInsets.top`; `safeAreaInsets.top == 0` → Pille 180 × 24 pt oben mittig. Bei Bildschirmwechseln neu aufbauen.
5. **`IslandView`** (SwiftUI): Zustände unsichtbar / klein / groß.

**Zusammenspiel mit Seam:** Insel liegt über der Abdunklung (Dimmer = `.normal`) · bei gedrückter Maustaste (Ziehen/Andocken) kein Aufklappen · Vollbild-App auf dem Bildschirm → Insel dort aus.

**Einstellung:** ein Schalter „Musik in der Notch“ (Standard: an). Ist die Browser-Unterstützung
nicht verfügbar, steht darunter: „Browser-Medien nicht verfügbar – macOS blockiert den Zugriff“.

## Aussehen und Bewegung

- **Form:** tiefschwarz, oben bündig am Bildschirmrand, unten weich gerundet (kontinuierliche Ecken), wächst nahtlos aus der Notch. Kein Rand, kein Schatten, kein Glas.
- **Klein:** links der Notch Cover 18 pt (leicht gerundet), rechts animierter Pegel in Weiß. Pause → Pegel steht; nach ~5 s Pause zurück in die Notch.
- **Groß** (Maus darüber, ~380 × 110 pt): Cover 56 pt · Titel Weiß, Interpret Grau, je einzeilig mit „…“ · Symbol der Quell-App klein oben rechts · ⏮ ⏯ ⏭ als SF Symbols · schmaler Fortschrittsbalken mit Zeiten, spulbar.
- **Schrift:** SF Pro (System), keine Plus Jakarta Sans, kein Iris.
- **Bewegung:** Apples Federn (`.smooth` / `.snappy`); Titelwechsel weich überblendet; Maus weg → nach ~0,3 s zu.
- **Ohne Notch:** dieselbe Form als Pille, geschlossen 180 × 24 pt.

## Fehlerverhalten

- Adapter-`test` scheitert → `AppleScriptSource`, Hinweis in den Einstellungen.
- Perl-Prozess endet → Neustart mit wachsender Pause; nach 3 Abbrüchen in Folge → AppleScript + Hinweis. Jeder Wechsel einmal ins Protokoll, nie still.
- Unlesbare JSON-Zeile → überspringen, zählen, ab 10 in Folge Protokolleintrag.
- Nichts läuft / kein Titel → Insel unsichtbar.

## Sicherheit

Seam hat die Bedienungshilfen-Freigabe (siehe `docs/SECURE-DESIGN.md`). Neu: Kindprozess
`/usr/bin/perl` mit Skript + Framework aus dem **signierten Bundle**; Argumente fest, keine
Benutzereingaben; stdout wird nur als JSON gelesen. AppleScript-Rückfall braucht die
Automation-Freigabe für Spotify/Music. **Vor dem ersten Code: `rafter-secure-design`**, Ergebnis
als Abschnitt in `docs/SECURE-DESIGN.md`. Lizenz: BSD-3-Hinweis des Adapters in Hilfe/README.
GPL-Repos (Boring Notch, DynamicNotch, Atoll, FunNotch, NotchMore) nur gelesen, kein Code.

## Tests

- Einheitstests mit dem Mitschnitt: Safari-Eltern-ID, Zusammenführen halber Browser-Meldungen, Werbung als Titel, Pause, Fortschritt-Hochrechnung, leere Meldung → unsichtbar.
- `/app-sichttest`: Insel-Lage per Bedienungshilfen gegen Notch-Maße (MacBook) und Pille (Bildschirm ohne Notch); Klein/Groß-Zustände; Steuern einer Browser-Quelle.

## Nicht in diesem Schritt

Weitere Notch-Funktionen · Songtexte · Visualizer mit echtem Audiopegel (Pegel ist Animation) ·
Kurzeinblendung bei Titelwechsel · Einstellungen je Bildschirm.
