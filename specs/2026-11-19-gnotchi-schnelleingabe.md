# Gnotchi – Schnelleingabe in Alltagssprache (Spezifikation + Sicherheitsentwurf G61)

Stand 2026-11-19 (MacBook). Per `/grill-me` mit Michael geklärt, sieben Entscheidungen, jede einzeln
bestätigt („ja, passt“). Vorbild: Cupola (trycupola.com), Natural-Language-Quick-Add. Noch kein Code.
Zieht mit Kalli zusammen (Kalli schreibt, Gnotchi erkennt und zeigt).

> **Gebaut am 19.11.** (Zweige `feature/schnelleingabe` und Kalli `feature/schnelleingabe-rueckkanal`). Abweichungen
> von diesem Entwurf: Zeitlimit für Kallis Antwort 4 s statt 1 s (Kalli liest nach dem Speichern nach); ein altes
> Kalli zeigt sich als „Kalli antwortet nicht … Kalli aktualisieren“; kein eigener Plus-Knopf in der großen Insel,
> nur die Ring-Taste „Neuer Eintrag“; Kalendername in der Vorschau fehlt. Stand der Sicherheit: `docs/SECURE-DESIGN.md`
> G61 und Kalli K2.

## Messung vorab (19.11., MacBook)

`NSDataDetector` allein an 20 deutschen Sätzen (`2026-11-19-schnelleingabe-messung.swift`):
14 richtig, 3 nicht erkannt („in 2 Stunden“, „am Wochenende“, „halb drei“), **3 falsch ohne Warnung**
(„Sonntag um 7:15“ → 19:15 · „nächsten Montag … 11 Uhr“ → zwei Treffer, 11 Uhr als 23:00 ·
„bis 30.11.“ → heute). Reine Datumsangaben bekommen 12:00. → Eigene deutsche Regelschicht nötig,
`NSDataDetector` höchstens als Hilfe für Datumsformen („3. Dezember“, „12.01.2027“).

## Entscheidungen

1. **Kalli schreibt, Gnotchi erkennt.** Gnotchi bekommt keinen Zugriff auf Kalender/Erinnerungen
   (für Erinnerungen gibt es keinen Nur-Schreiben-Zugriff). Entwurf geht über einen Rückkanal am
   bestehenden `kalli.sock` an Kalli, Kalli speichert mit `QuickReminder.save` bzw. neuem
   `QuickEvent.save` und antwortet. Kalli läuft nicht → sichtbar „Kalli läuft nicht“.
2. **Eingabezeile aus der Notch** wie die Zwischenablage. Kürzel wählbar, Vorschlag ab Werk
   **control + option + N** (vor dem Bauen auf Belegung messen). Zusätzlich Plus-Knopf in der großen
   Insel und Taste im Tasten-Ring. Ohne Notch unter der Pille. Darunter mitlaufende Vorschauzeile.
   Return speichert, Escape schließt. Erfolg: „Gespeichert · Rückgängig (⌘Z)“, schließt nach ~1,5 s
   selbst. Fehler: bleibt offen mit Meldung.
3. **Art:** mit Uhrzeit → Termin, ohne → Erinnerung. Signalwörter „erinnere mich“, „nicht vergessen“,
   „bis <Datum>“ → immer Erinnerung. **Tab** wechselt die Art in der Vorschau. Symbol zeigt die Art.
4. **Termin:** Standardkalender für neue Termine (Name + Farbpunkt in der Vorschau), Dauer 1 h,
   erkannt werden „bis 17 Uhr“, „2 Std“, „30 Min“. Kein eigener Alarm (Kalli-Vorlauf + Gnotchi-Insel
   reichen). Kein Ort/Notiz/Teilnehmer. Kalender-Kürzel („@Arbeit“) erst bei Bedarf.
   **Erinnerung:** wie Kalli heute (Standardliste, Alarm nur mit Uhrzeit, „!“ am Ende = dringend).
5. **Uneindeutiges:** Uhrzeiten wörtlich im 24-h-Format („7 Uhr“ = 07:00, „halb drei“ = 02:30);
   „morgens/nachmittags/abends“ verschieben. Wochentag = heute → heute, wenn die Zeit noch kommt,
   sonst nächste Woche. Uhrzeit ohne Datum, schon vorbei → morgen. „nächsten Montag“ = kommender
   Montag. „Wochenende“ = kommender Samstag. Datum + Uhrzeit verschmelzen zu einem Zeitpunkt; zwei
   echte Daten → erstes gewinnt, Vorschau gelb „Prüfen“. Nichts erkannt → Erinnerung ohne Datum,
   Vorschau sagt es.
6. **Titel:** Zeitangaben, Randfüllwörter („am“, „um“, „bis“) und Signalwörter raus, Rest wörtlich.
   Leer → kein Speichern, „Bitte einen Titel eingeben“. **⌘Z** in den ~1,5 s nach dem Speichern löscht
   den Eintrag über Kalli (Kennung aus Kallis Antwort). Nur Deutsch.
7. **Rahmen:** Schalter „Schnelleingabe“ in Gnotchi, **ab Werk aus**; beim Einschalten Kalli-Prüfung.
   **Kalli erscheint zuerst**; neues Gnotchi + altes Kalli → „Kalli bitte aktualisieren“.
   Erkennung als reines Modul (ohne EventKit/UI), fertig erst wenn alle Testfälle grün.
   Großes Kalender-Fenster (Cupola „View all“) ist **nicht** Teil davon, eigene Klärung, eher Kalli.

## Testfälle (Bezug: Do 19.11.2026, 14:30)

| Eingabe | Art | Zeitpunkt | Titel |
|---|---|---|---|
| Zahnarzt Do 15 Uhr | Termin | Do 19.11. 15:00 | Zahnarzt |
| Zahnarzt morgen um 15 Uhr | Termin | Fr 20.11. 15:00 | Zahnarzt |
| Call mit Lena übermorgen 9:30 | Termin | Sa 21.11. 09:30 | Call mit Lena |
| Meeting am 3.12. um 14 Uhr | Termin | Do 03.12. 14:00 | Meeting |
| Meeting am 3. Dezember 14:00 | Termin | Do 03.12. 14:00 | Meeting |
| Kino mit Jonas Freitag 20 Uhr | Termin | Fr 20.11. 20:00 | Kino mit Jonas |
| nächsten Montag Steuerberater 11 Uhr | Termin | Mo 23.11. 11:00 | Steuerberater |
| heute 18 Uhr Sport | Termin | Do 19.11. 18:00 | Sport |
| 9 Uhr Sport | Termin | Fr 20.11. 09:00 | Sport |
| Müll rausbringen morgen früh | Erinnerung | Fr 20.11. (Vorschlag 08:00, offen) | Müll rausbringen |
| Rechnung zahlen bis 30.11. | Erinnerung | Mo 30.11., ohne Uhrzeit | Rechnung zahlen |
| in 2 Stunden Tom anrufen | Termin | Do 19.11. 16:30 | Tom anrufen |
| erinnere mich in 2 Stunden Tom anzurufen | Erinnerung | Do 19.11. 16:30, Alarm | Tom anzurufen |
| in 3 Tagen Paket abholen | Erinnerung | So 22.11., ohne Uhrzeit | Paket abholen |
| Mittwoch halb drei nachmittags Friseur | Termin | Mi 25.11. 14:30 | Friseur |
| Mittwoch halb drei Friseur | Termin | Mi 25.11. **02:30** (wörtlich, Regel 5) | Friseur |
| Geburtstag Mama 12.01.2027 | Erinnerung | Di 12.01.2027, ohne Uhrzeit | Geburtstag Mama |
| Weihnachtsfeier 18.12. 19:00 | Termin | Fr 18.12. 19:00 | Weihnachtsfeier |
| Termin Dienstag 8 Uhr | Termin | Di 24.11. 08:00 | Termin |
| Flug am Sonntag um 7:15 | Termin | So 22.11. 07:15 | Flug |
| Flug am Sonntag um 7 Uhr abends | Termin | So 22.11. 19:00 | Flug |
| Teams-Call 16:30 | Termin | Do 19.11. 16:30 | Teams-Call |
| Teams-Call 16:30 bis 17:15 | Termin | 16:30–17:15 | Teams-Call |
| nächste Woche Mittwoch Vertrag prüfen | Erinnerung | Mi 25.11., ohne Uhrzeit | Vertrag prüfen |
| am Wochenende Fahrrad reparieren | Erinnerung | Sa 21.11., ohne Uhrzeit | Fahrrad reparieren |
| Steuer abgeben ! | Erinnerung | ohne Datum, dringend | Steuer abgeben |
| morgen 15 Uhr | — | — | kein Speichern, „Bitte einen Titel eingeben“ |

Offen beim Bauen (keine Produktentscheidung, nur Messung): „morgen früh“ ohne Uhrzeit — Erinnerung
mit Datum ohne Alarm oder 08:00? Vorschlag: ohne Uhrzeit, Vorschau zeigt „morgen früh → ohne Uhrzeit“.
„Mittwoch halb drei Friseur“ ist nach Regel 5 bewusst 02:30 — die Vorschau zeigt das; ein gelbes
„Prüfen“ bei Uhrzeiten zwischen 0 und 6 Uhr ist eine billige Absicherung (beim Bauen vorschlagen).

## Sicherheitsentwurf G61 – Rückkanal am `kalli.sock`

Erweiterung von G26. Bisher: Kalli → Gnotchi (`nextEvent`), Gnotchi → Kalli nur `ok`.

- **Prüfung unverändert beidseitig** vor dem ersten Byte (`LOCAL_PEERTOKEN` → Audit-Token →
  `SecCodeCheckValidity`, Developer ID, Team LTKJ6Z2VYB, Kennungen `com.kalli.app` / `dev.mwlr.gnotchi`).
- **Neue Nachrichten Gnotchi → Kalli** (Rahmen wie G21: 4 Byte Länge + JSON ≤ 4 KB):
  `{"v":2,"create":{"id":"<UUID>","kind":"event|reminder","title":"…","start":<s>|null,"end":<s>|null,"allDay":bool,"urgent":bool}}`
  und `{"v":2,"undo":{"id":"<UUID>"}}`.
- **Antwort Kalli → Gnotchi:** `{"v":2,"result":{"id":"<UUID>","ok":true}}` oder mit `"error":"…"`.
- **Kalli prüft jede Anfrage selbst** (vertraut Gnotchi nicht blind): Titel 1–200 Zeichen, keine
  Steuerzeichen; `kind` nur die zwei Werte; Zeitpunkte zwischen heute −1 Tag und +5 Jahre;
  `end > start`, Dauer ≤ 24 h; höchstens 20 Anlagen pro Minute.
- **Undo nur für eigene, frische Einträge:** Kalli merkt sich `id → EventKit-Kennung` nur im Speicher,
  höchstens 30 s und nur für Einträge, die über den Socket angelegt wurden. Fremde oder ältere
  Kennungen → Fehler. Kalli löscht also nie etwas, das nicht gerade über diesen Weg entstand.
- **Versionsprüfung:** `v:1`-Kalli antwortet nicht auf `create` → Gnotchi meldet nach 1 s Zeitlimit
  „Kalli bitte aktualisieren“.
- **Protokoll:** nur Art und Ergebnis, nie der Titel (`privacy: .private`).
- Nach dem Bau: `/code-audit` auf beide Diffs.

## Umfang

- **Kalli:** Rückkanal am Socket, `QuickEvent.save` (Standardkalender, Dauer), Undo-Speicher, Tests.
- **Gnotchi:** reines Erkennungsmodul `QuickEntryParser` + Tests (Tabelle oben), Eingabezeile +
  Vorschau, Kürzel, Plus-Knopf, Tasten-Ring-Taste, Schalter, Fehlertexte, README/Hilfe/CHANGELOG.
