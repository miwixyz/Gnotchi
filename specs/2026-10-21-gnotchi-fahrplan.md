# Gnotchi – Fahrplan nach 0.3.0 (Stand 2026-10-21)

Wunschliste Michael 21.10., Vorbild MacNotch (macnotch.io, Abschnitte „Notch & System“, „Alltag“, „Code & KI“).
Jede Stufe ist eine eigene Version: Spezifikation + `rafter-secure-design` **vor** dem Code, Tests, Sichttest,
Release mit eigenem Go.

## Entscheidungen (Michael, 21.10.)

| Frage | Entscheidung |
|---|---|
| Mitteilungen + Lautstärke-/Helligkeitsanzeige brauchen die Bedienungshilfen-Freigabe | **Eigenes Hilfsprogramm** bekommt die Freigabe, Gnotchi selbst bleibt ohne (G1 gilt weiter). Ab Werk aus. Vorbild gemessen: Boring Notch `BoringNotchXPCHelper/NotificationWatcher.swift` (AXObserver auf das Mitteilungsfenster) |
| Womit anfangen | **Grundgerüst Live-Aktivitäten** |
| Himmel hinter dem Wetter | **Farbverlauf** aus Wetter + Tageszeit, keine Fotos |
| Timer / App-Updates | **Eigene Timer** in Gnotchi · **Updates der App-Familie** (Tippi, Kalli, Qotti, Seam, Gnotchi) · Kalender aus **Kalli** (18.10.: keinen zweiten Kalender bauen) |

## Stufen

| Version | Inhalt | Neue Fläche (für den Sicherheitsentwurf) |
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
