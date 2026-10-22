# Gnotchi – Fahrplan nach 0.3.0 (angelegt 2026-10-21, Versionen nachgezogen 2026-10-22)

Wunschliste Michael 21.10., Vorbild MacNotch (macnotch.io, Abschnitte „Notch & System“, „Alltag“, „Code & KI“).
Jede Stufe ist eine eigene Version: Spezifikation + `rafter-secure-design` **vor** dem Code, Tests, Sichttest,
Release mit eigenem Go. Mehrere Stufen können in einem Release erscheinen (0.3.0 → 0.4.0; 0.6.0 + 0.7.0 → 0.8.0).

**Nachgezogen 22.10. (Michael: „korrigier das“):** Die Reihenfolge hat sich verschoben – Mitteilungen/Anrufe wurden
vorgezogen (Michael 21.10.: „Benachrichtigungen + Anrufe, danach Wetter“), der Spiegel kam schon mit 0.5.0, die
Dateiablage erst danach. Die ursprüngliche Planung steht unten unter „Erste Fassung (21.10.)“.

## Entscheidungen (Michael, 21. und 22.10.)

| Frage | Entscheidung |
|---|---|
| Mitteilungen + Lautstärke-/Helligkeitsanzeige brauchen die Bedienungshilfen-Freigabe | **Eigenes Hilfsprogramm** bekommt die Freigabe, Gnotchi selbst bleibt ohne (G1 gilt weiter). Ab Werk aus. Vorbild gemessen: Boring Notch `BoringNotchXPCHelper/NotificationWatcher.swift` (AXObserver auf das Mitteilungsfenster) |
| Womit anfangen | **Grundgerüst Live-Aktivitäten** |
| Himmel hinter dem Wetter | **Farbverlauf** aus Wetter + Tageszeit, keine Fotos |
| Mitteilungen (22.10.) | Anzeigen **+ Knöpfe**, **ohne Antworten** · Apples Banner verstecken (fremde Alerts nie) · nur ausgewählte Apps |
| Wetter (22.10.) | **Open-Meteo**, Ort **eintippen** (keine Standort-Freigabe), **nur groß** (Symbol in der Leiste), 600 pt breit |
| Ablage (22.10.) | **Verweise** statt Kopien, nach dem Rausziehen entfernen, Finder/Teilen/AirDrop/ZIP (+ AES-256-Passwort); Reihe unter der großen Insel und im Band |
| Ruhe-Insel (22.10.) | Läuft nichts: kleine Insel bleibt bei Wetter/Ablage mit Inhalt (Temperatur, Anzahl) |
| Timer / App-Updates | **Eigene Timer** in Gnotchi · **Updates der App-Familie** (Tippi, Kalli, Qotti, Seam, Gnotchi) · Kalender aus **Kalli** (18.10.: keinen zweiten Kalender bauen) |

## Stufen (Stand 22.10.)

| Stufe | Inhalt | Erschienen | Spezifikation / Sicherheit |
|---|---|---|---|
| **0.4.0 Live-Aktivitäten** | Rotation (Medien, Kopfhörer, Updates der App-Familie), Medienfilter je App, Trackwechsel breiter | **v0.4.0**, 21.10. (mit 0.3.0) | `2026-10-21-gnotchi-0.4.0-live-aktivitaeten.md`, G23–G25 |
| **0.5.0 Termine, Timer, Spiegel** | Nächster Termin aus Kalli, eigene Timer, Spiegel (Kamera), „Eine Sache groß“, Band, Stecknadel | **v0.5.0**, 21.10. | `…-0.5.0-termine.md`, `…-0.5.0-timer.md`, `…-0.5.0-spiegel.md`, G26–G27 |
| **0.6.0 Mitteilungen + Anrufe** | Mitteilungen ausgewählter Apps mit Knöpfen, Anrufe annehmen/ablehnen/beenden; Hilfsprogramm „Gnotchi Mitteilungen“ (vorgezogen aus der ersten Fassung „0.9.0 Hilfsprogramm“) | in **v0.8.0**, 22.10. | `2026-10-22-gnotchi-0.6.0-mitteilungen-anrufe.md`, G28–G30 |
| **0.7.0 Wetter** | Open-Meteo, Ort eintippen, groß mit 8 Stunden, 7 Tagen, Einzelwerten, Farbverlauf | in **v0.8.0**, 22.10. | `2026-10-22-gnotchi-0.7.0-wetter.md`, G31 |
| **0.8.0 Dateiablage, Ruhe-Insel, Reiter** | Ablage (Verweise, ZIP mit AES-Passwort), Ruhe-Insel, Einstellungen in Reitern, Absturz-Fix Fortschrittsbalken | **v0.8.0**, 22.10. | `2026-10-22-gnotchi-0.8.0-ablage.md`, G32 |
| offen | **Rest Mitteilungen:** Ablehnen aus der Notch messen → Apples Anruf-Banner verstecken; Ungelesen-Blick in der Leiste; FaceTime-Audio/-Video messen | – | Erweiterung G28–G30 |
| offen | **Lautstärke-/Helligkeitsanzeige** (aus der ersten Fassung „0.9.0“) | – | Helligkeit = private Schnittstelle (DisplayServices) → eigene Abwägung; Bedienungshilfen nur im Hilfsprogramm |
| offen | **Code & KI** (Michael 21.10.: „ja“): Claude-Code-Sitzungen in der Notch mit Status, letzter Nachricht und Erlauben/Ablehnen, wenn die Kommandozeile wartet; danach ggf. Cursor, GitHub-Reviews, Übersetzung | – | Weg über Claude-Code-Hooks (lokal, ohne Bedienungshilfen). Erlauben/Ablehnen aus der Notch = Freigabe von KI-Werkzeugen → eigener Sicherheitsentwurf: nur echter Klick, Sitzung eindeutig, Zeitlimit, nie automatisch |

Nächste freie Versionsnummer: **0.9.0**.

## Erste Fassung (21.10.) – zum Nachvollziehen, nicht mehr gültig

| Version (geplant) | Inhalt | Neue Fläche (für den Sicherheitsentwurf) |
|---|---|---|
| **0.4.0 Live-Aktivitäten** | Eingeklappte Leiste rotiert die aktiven Aktivitäten (Medien, Bluetooth-Audiogerät, App-Updates). Medienfilter je Quelle (neu: je App ein Schalter, z. B. Spotify an, Safari aus). Beim Trackwechsel kurz breiter. Einstellungsbereich „Live-Aktivitäten“. Gleiches auf Bildschirmen ohne Notch (Pille, gibt es schon) | App-Updates: Familien-Apps melden über distnoted (wie G17/G22: nur Schema, nur Anzeige). Bluetooth nur über Core Audio (kein Akku: AirPods-Akku ist privat) |
| **0.5.0 Timer + Kalender** | Eigene Timer (Start aus Menü/Insel, Ablauf als Hinweis). Nächster Termin aus Kalli | Kalli muss senden → Kalli-Release. Termin-Titel sind privat → nicht über distnoted (jeder Prozess liest mit), Weg wie G21 (Socket, beidseitig signaturgeprüft) |
| **0.6.0 Dateiablage** | Karussell: Dateien reinlegen, später rausziehen. Drop Actions (AirDrop, Teilen) | Dateipfade, Sicherheitslesezeichen statt Kopien, Quarantäne bleibt, nichts ausführen |
| **0.7.0 Wetter** | Open-Meteo ohne Schlüssel. Kompakt: Temperatur, Zustand, Max/Min, gefühlt, Stundenleiste. Groß: Luftfeuchte, Wind, UV, Druck, Sonnenauf-/-untergang, 7 Tage, Verlauf-Himmel. Standort oder Stadt, °C/°F | **Erster Netzzugriff außer Updates** (G11 ändern). Standort-Freigabe + Berechtigung im Paket (Positivliste). Gerundete Koordinaten senden |
| **0.8.0 Spiegel** | Kamera-Vorschau vor Calls | Kamera-Freigabe + Berechtigung `device.camera` (Positivliste, `entitlement-gate.sh`). Bild nie speichern |
| **0.9.0 Hilfsprogramm** | Mitteilungen zentriert in der Notch (ansehen, wegräumen, antworten), Ungelesen-Blick in der Leiste. Eigene Lautstärke-/Helligkeitsanzeige | Bedienungshilfen nur im Hilfsprogramm, XPC beidseitig geprüft (wie G21), Mitteilungstexte nie ins Protokoll. Helligkeit ist private Schnittstelle (DisplayServices) → eigene Abwägung |
| eigene Stufe (Platz offen) | **Code & KI** (Michael 21.10.: „ja“): Claude-Code-Sitzungen in der Notch mit Status, letzter Nachricht und Erlauben/Ablehnen, wenn die Kommandozeile wartet; danach ggf. Cursor, GitHub-Reviews, Übersetzung | Weg über Claude-Code-Hooks (lokal, ohne Bedienungshilfen). Erlauben/Ablehnen aus der Notch = Freigabe von KI-Werkzeugen → eigener Sicherheitsentwurf: nur echter Klick, Sitzung eindeutig, Zeitlimit, nie automatisch |

## Nicht übernommen

- Mehrere Notch-Apps gleichzeitig: weiter „nie“ (18.10.). Vor MacNotch-ähnlichen Funktionen nichts daran ändern.
