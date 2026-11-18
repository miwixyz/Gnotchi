# Gnotchi – Stream Deck: Qotti-Kontingent als Anzeige-Taste

Stand 2026-11-17, **Entwurf, nichts gebaut, nichts committet.** Auftrag: prüfen, ob die Claude-/Codex-Limits aus Qotti als reine
Anzeige-Taste ins bestehende Plugin `GnotchiDeck` passen (kein zweites Plugin). Grundlagen: `specs/2026-11-17-gnotchi-stream-deck-plus.md`
(G59), `specs/2026-10-20-gnotchi-0.3.0-qotti.md` (G22).

## Urteil

**Geht ohne Umbau**, mit vier kleinen Ergänzungen (unten). Konfidenz: hoch für den Datenweg (Code gelesen, Datei:Zeile), mittel für
die Darstellung auf Neo und Plus (Tastenbild und Leiste sind gebaut, aber nicht mit Prozentbalken gemessen → M-Q2).

Warum es ohne Umbau geht:

1. **Die Werte kommen schon an einer Stelle an, von der `deck.sock` sie mitsenden kann.** Qotti (`GnotchiBridge.payload`) sendet über
   distnoted nur 5-h-Prozent, Reset (Unix-Sekunden) und Zustand je Anbieter. `QottiLink.apply` legt sie in `ActivityModel.quota`
   (`QottiLink.Snapshot`: `claude`/`codex`, je `percent`, `resetAt`, `state`). `DeckLink` hält dieselbe `ActivityModel`-Instanz
   (`init(activity:)`), kann `activity.quota` also direkt lesen. Kein zweiter Empfänger, kein neuer Weg von Qotti zu Gnotchi,
   **Qotti bleibt unverändert** (kein Release, keine Rafter-Frage).
2. **Das Datenmodell ist schon das kleinste mögliche.** Mehr als Prozent, Reset und Zustand hat Gnotchi nie: Woche, Konto, Plan,
   E-Mail, Token und Fehlertexte gehen weder von Qotti an Gnotchi noch kommen sie in `QottiLink` an (G22). Was das Plugin sehen kann,
   ist eine Teilmenge dessen, was die Insel zeigt.
3. **Das Vertrauensmodell (Peer + Eltern geprüft, feste Befehle, nur ein Absender) bleibt unverändert.** Es kommt kein neuer
   Befehl in Gegenrichtung dazu. Neu ist nur eine zweite Art von Rückmeldung (Gnotchi → Plugin).

## Was dazukommt (die vier Ergänzungen)

| # | Wo | Was |
|---|---|---|
| 1 | `DeckWire` | neue Rückmeldung `Quota` + `encode`/`parseQuota`; `quota` als zulässiger `watch`-Eintrag |
| 2 | `DeckLink` | bei `watch` mit `quota`: Stand aus `activity.quota` senden, nur bei Änderung; Zeitablauf von QottiLink (5 Min.) wird als „leer“ weitergegeben |
| 3 | `GnotchiDeck` | `GnotchiSocket.readIncoming` unterscheidet zwei Nachrichtenarten; neue Aktion „Kontingent“ im Manifest, Rendern |
| 4 | Tests + Docs | `DeckTests` (Wire), Plugin-Version hoch, G59a in `SECURE-DESIGN.md`, HILFE/CHANGELOG |

**Wichtigste Falle (gelesen in `GnotchiDeck/GnotchiSocket.swift`, `readIncoming`):** Das Plugin schließt die Verbindung bei jeder
Nachricht, die `parseStatus` nicht versteht („ungültige Nachricht“). Ein Plugin 0.36 würde bei einer unbekannten Quota-Nachricht
also trennen und dauernd neu verbinden. Deshalb **sendet Gnotchi Quota nur an ein Plugin, das sie per `watch` angefordert hat**
(`"watch":["quota", …]`). Ein altes Plugin kennt den Eintrag nicht und bekommt nie eine solche Nachricht. Zusätzlich gilt der
bestehende Hinweis „Plugin aktualisieren“ (`hello`-Version).

## Darstellung

Neue Aktion `dev.mwlr.gnotchi.deck.quota`, „Kontingent“, `Controllers: ["Encoder", "Keypad"]` (Aktionen nur für Regler zeigt
Stream Deck 7.6.1 gar nicht an, G59 Stufe 1). Einstellung „Anbieter“: **Claude / Codex / beide**.

**Neo (Taste, ein Anbieter je Taste):** Titel oben „Claude“, Zeichen unten als Bild mit Prozent und Balken (`setImage`, wie die
Symbole in `tools/deck-icons.swift`). Zweite Zeile: „zurück in 1 Std. 5 Min.“ bleibt weg (Taste zu klein) – dafür drei Zustände
über Farbe/Symbol, passend zu den Warnstufen aus `QottiLink.evaluate`:

| Zustand | Anzeige |
|---|---|
| < 80 % | Prozent, Balken Schiefer-Iris (#98A9E1) |
| ≥ 80 % | Prozent, Balken warm (Stufe 1) |
| ≥ 95 % | Prozent, Balken rot (Stufe 2) |
| `throttled` | „gedrosselt“, Warnsymbol |
| `stale` (Qotti meldet Fehler, Stand alt) | Prozent gedimmt + „alt“ |
| kein Wert (Qotti aus / 5 Min. still / Einstellung „Qotti-Kontingent anzeigen“ aus) | „Qotti aus“, Hinweis in der Taste, nie eine alte Zahl |

**Plus (Regler, Leiste 200 × 100):** „beide“ zeigt zwei Zeilen („Claude 42 % · zurück in 1 Std.“ / „Codex 17 %“), je Zeile Balken.
Mit einem Anbieter: wie Neo, dazu Reset-Text als Lauftext (vorhandener `TrackImage`/`Marquee`). Der Reset-Text wird im Plugin aus
`resetAt` gerechnet (kein Verkehr je Minute; Takt nur, solange sichtbar, wie beim Lauftext).

**Bedienung: keine.** Drücken, Drehen und Tippen tun nichts (kein neuer Befehl). Das ist Absicht und der Kern der Sicherheits-
aussage: Die Aktion kann ausschließlich anzeigen.

## Datenumfang (Gnotchi → Plugin)

```json
{"v":1,"quota":{"claude":{"percent":42,"resetAt":1763400000,"state":"ok"},"codex":{"percent":17,"state":"throttled"}}}
```

- Je Anbieter genau `percent` (0…100), `resetAt` (Unix-Sekunden, optional, nur plausibel wie `QottiLink`), `state` (`ok|stale|throttled`).
- Kein Anbieter vorhanden: `{"v":1,"quota":null}`.
- **Nicht gesendet:** Woche, Plan, Konto, E-Mail, Token, Fehlertexte, Qottis Version – Gnotchi hat sie auch nicht.
- Rahmen passt in `maxFrame` (4096) mit großem Abstand. Gesendet bei Änderung und beim `watch`, nie im Takt.
- Das Plugin prüft die Form erneut (`parseQuota`: Zahl ohne Bool, endlich, 0…100 begrenzt, `state` aus Positivliste, sonst Anbieter
  verworfen) und **schließt bei unlesbarer Nachricht wie bisher**.

## Sicherheitsergänzung zu G59 (Vorschlag G59a)

Vertrauensmodell: **keine Änderung** an Peer-Prüfung, Eltern-Prüfung, Befehlsliste, Grenzen oder Einstellung „Stream Deck“.

- **Gegenrichtung:** Es wird kein Befehl ergänzt. `DeckWire.parse` bleibt unverändert, einziger Zusatz ist `quota` als zulässiger
  Eintrag in `watch` (Muster `isValidApp` lässt „quota“ ohnehin zu; `DeckController` muss ihn **ausfiltern**, damit er nicht als
  Bundle-ID in `statuses()` landet – sonst entstünde eine Pseudo-App „quota“ im Mixer-Pfad).
- **Informationsfluss (neu, bewusst):** Prozent und Reset zweier KI-Anbieter gehen an Elgatos Stream-Deck-App (Arbeitsspeicher, wie
  die Titel in G59 Punkt 6). Es verrät Nutzungsintensität, keine Inhalte. Begrenzung: nur an das geprüfte Plugin, nur wenn eine
  Quota-Aktion sichtbar ist (`watch`), nur Prozent/Reset/Zustand.
- **Konto- und Token-Daten:** nicht vorhanden und nicht herleitbar (Schlüsselmenge fest, Test unten).
- **Plugin-Ausgabe:** wie G59 Punkt 6 – nie Prozente, Zeiten oder Anbieternamen auf stdout/stderr, nur feste Zustandstexte.
- **Protokoll Gnotchi (G8):** weiter nur „verbunden/getrennt“, nie Werte.
- **Schalter:** Aus ist, wer „Stream Deck“ oder „Qotti-Kontingent anzeigen“ ausschaltet; in beiden Fällen zeigt die Taste „aus“.
  Qotti sendet ohnehin nur bei laufendem Gnotchi mit eingeschaltetem Schalter – die Taste kann Qotti nicht „wecken“.
- **STRIDE-Rest:** S/T/E unverändert (nur geprüftes Plugin, feste Form, keine Rechte); I s. oben; D: eine Nachricht je Änderung,
  QottiLink wertet höchstens 1/s aus; R: nicht relevant.

## Offene Stellen (Entscheidung Michael, bevor gebaut wird)

1. **Gnotchi muss laufen und der Schalter „Qotti-Kontingent anzeigen“ an sein** (ab Werk an). Wer Qotti ohne Gnotchi nutzt, hat keine
   Taste – das ist der Preis dafür, dass Qotti nicht angefasst wird. Ich halte das für richtig.
2. **Neo/Plus-Layout:** eine Aktion für beide Geräte (wie „App-Lautstärke“ auf Taste und Regler) oder zwei? Empfehlung: eine, so ist
   es auch in den mitgelieferten Profilen (`tools/deck-profiles.py`) nur eine Zeile mehr.
3. **Profile:** Die automatisch installierten Profile `gnotchi-plus` / `gnotchi-neo` bekämen einen Platz. Textposition steckt im
   Profil (G59-Stand 17.11.) → frisch installieren, kein Update in vorhandene Profile.

## Messpunkte

- **M-Q1 – Datenweg:** Mit `tools/fake-qotti.swift` (Werte `ok`, `warnung`, `kaputt`) ein Quota-Frame am echten Plugin ankommen
  lassen; mit einem zweiten, unsignierten Mithörer am `deck.sock` prüfen, dass er abgewiesen wird (wie M2). Erwartung: Frame enthält
  genau die Schlüssel `v`, `quota`, `claude`/`codex`, `percent`, `resetAt`, `state`.
- **M-Q2 – Darstellung:** Balken und Prozent auf **Neo-Taste** und **Plus-Leiste** (Michael, Auge): lesbar bei 80 %, 95 %, gedrosselt,
  „Qotti aus“. Hier liegt die mittlere Konfidenz.
- **M-Q3 – altes Plugin:** Plugin 0.36 mit neuem Gnotchi: kein Trennen-Neuverbinden-Zyklus (Frame wird nie gesendet). Gemessen am
  Protokoll „Stream Deck: Plugin verbunden/getrennt“ über 5 Minuten.
- **M-Q4 – Zeitablauf:** Qotti beenden → nach 5 Min. (`QottiLink.staleAfter`) zeigt die Taste „Qotti aus“, nie die alte Zahl.
- **M-Q5 – kein Hördaten-/Konto-Leck:** `grep` über `~/Library/Logs/ElgatoStreamDeck/dev.mwlr.gnotchi.deck*.log` auf die letzten
  Prozentwerte und Anbieternamen: kein Treffer.
- **M-Q6 – keine Rückwirkung:** Aktion drücken/drehen/tippen löst nachweislich keinen Befehl aus (Zähler im Protokoll bleibt).

## Prüfung vor Release (Regeln)

`/code-audit` auf den Diff (Sicherheitsfläche: neue Nachrichtenart, `watch`-Eintrag, Plugin-Parser) · **Qotti nie an `rafter run`**,
und Qotti ändert sich hier gar nicht · `rafter run` auf Gnotchi nur als Zweitmeinung vor dem Release.

## Aufwand (grob)

Klein: ein Wire-Typ, eine Verzweigung in `DeckLink.push`, eine Aktion im Plugin samt Bildern und Manifest, Tests, G59a. Keine neue
Berechtigung, keine Qotti-Änderung, kein Umbau von `PeerSocketServer`.
