# Gnotchi

Eine Insel in der MacBook-Notch für macOS 27, im Stil des Systems. Auf Bildschirmen ohne Notch
erscheint dieselbe Insel als Pille oben in der Mitte. Erste Funktion: **Mediensteuerung für alle
Quellen** (Spotify, Musik, Browser) – Titel, Cover, Play/Pause, Weiter, Zurück, Spulen.

**Stand:** in Arbeit (0.1.0, noch nicht veröffentlicht). Die Datenquelle (Medien-Adapter mit
Signaturprüfung, bereinigter Strom, Cover-Grenzen) steht und ist getestet; Insel, Rückfall und
Einstellungs-Verdrahtung folgen (`specs/2026-10-18-notch-mediensteuerung-plan.md`, Aufgaben 8–15).

Voraussetzungen: macOS 27, Mac mit Apple-Chip. Kostenlos, Open Source (MIT).

Entstanden im Repo von [Seam](https://github.com/miwixyz/Seam) (Zweig `feature/notch-medien`) und
am 18.10.2026 ausgelagert: Seam hält die Bedienungshilfen-Freigabe, und ein Kindprozess könnte
sie erben. Gnotchi hat diese Freigabe nicht und fragt sie nie an.

## Installieren

Noch kein Release. Sobald es eines gibt:

```bash
gh release download --repo miwixyz/Gnotchi --pattern '*.zip'
ditto -x -k Gnotchi-*.zip . && mv Gnotchi.app /Applications/ && open /Applications/Gnotchi.app
```

`ditto`, nicht `unzip` – `unzip` zerstört die Metadaten des signierten Bundles.

## Datenschutz und Berechtigungen

- **Keine Bedienungshilfen-Freigabe.** Gnotchi liest keine Fenster und erzeugt keine Eingaben.
- **Apple Events nur an Spotify und Musik**, und nur als Rückfall, wenn macOS den systemweiten
  Zugriff sperrt. macOS fragt dafür einmal.
- Titel, Interpret und Cover bleiben im Speicher, kommen nie ins Protokoll und nie ins Netz.
- Einziger Netzzugriff: die Update-Prüfung (Sparkle, signierter Feed).

Begründungen: [docs/SECURE-DESIGN.md](docs/SECURE-DESIGN.md).

## Bauen

```bash
make build     # xcodegen + xcodebuild (Sparkle fest auf Commit-SHA, Package.resolved)
make test      # Zeilen, Adapter-Zeile, Cover, Signaturprüfung, Kindprozess-Argumente
make lint      # SwiftLint strikt, inkl. Regel „keine Bedienungshilfen“
make dev       # Testversion mit Developer ID signiert aus /tmp starten
make install   # signiert nach /Applications (für den Entwickler-Mac)
make release   # notarisiertes ZIP, GitHub-Release, signierter Appcast
```

Voraussetzungen: macOS 27, Xcode, `xcodegen`, `swiftlint`. Der Adapter läuft nur aus einem mit
Michaels Team signierten Bundle (`make dev`/`make install`); ein unsignierter `make build` zeigt
deshalb keine Medien.

## Aufbau

| Pfad | Was |
|---|---|
| `Gnotchi/App/GnotchiApp.swift` | Einstieg, Menüleiste, Fenster |
| `Gnotchi/Media/MediaAdapter.swift` | Kindprozess `/usr/bin/perl` + Adapter, Neustart, Waisen |
| `Gnotchi/Media/NowPlayingInfo.swift` | Adapter-Zeile → bereinigter Wiedergabe-Zustand |
| `Gnotchi/Media/BundleIntegrity.swift` | Signatur + Team des eigenen Bundles vor jedem Start |
| `Gnotchi/Media/Artwork.swift`, `LineSplitter.swift` | Cover-Grenzen, Zeilen mit Längenlimit |
| `Vendor/mediaremote-adapter/` | eingespielter Adapter (BSD-3), siehe `VENDOR.md` |
| `specs/` | Spezifikation und Umsetzungsplan |
| `spike/` | Beispiel des Adapter-Stroms: Aufbau, Zahlen und Zeitpunkte wie im Mitschnitt vom 18.10.2026, Titel/Interpreten/IDs erfunden |

## Lizenz

MIT, siehe [LICENSE](LICENSE). Fremdcode (Sparkle, Plus Jakarta Sans, mediaremote-adapter):
[THIRD-PARTY-LICENSES](Gnotchi/Resources/THIRD-PARTY-LICENSES.md).
