# Gnotchi – Bildtext-Suche und „Text aus Bild kopieren“ (2026-11-14)

Anlass: Tool-Check Hikidashi (Vault `04 Ressourcen/KI-Wissen/Hikidashi – Bildtext-Suche …`), Michael 14.11.:
Texterkennung in Bildern gewünscht. Sicherheitsentwurf per `rafter-secure-design` vor dem Code → neue Regel **G50**
in `docs/SECURE-DESIGN.md`.

## Was gebaut wird

1. Bild-Einträge im Verlauf (Art `.image`, dazu `.file` mit mitkopiertem Bild wie G40/0.15.1) bekommen einmalig
   eine lokale Texterkennung (Apple Vision, `VNRecognizeTextRequest`, `.accurate`, `de-DE`, `en-US`, `es-ES`).
2. Die Suche findet Bilder über den erkannten Text.
3. Kontextmenü eines Bildes in der Seitenansicht: „Text aus Bild kopieren“ (nur, wenn Text erkannt wurde). Vorschau
   und Notch-Kacheln bewusst noch nicht.
4. Schalter „Text in Bildern erkennen“ im Reiter Zwischenablage, ab Werk **an**.

## Sicherheitsentwurf (Antworten auf `rafter-secure-design`, Abschnitt Data Storage + Ingestion + STRIDE)

**Klassifikation.** Erkannter Text ist *abgeleiteter Inhalt* aus Fremddaten (G40) und hat dieselbe Einstufung wie
der Bildinhalt: kann Zugangsdaten (abfotografierter Schlüssel), Personendaten, Kundendaten enthalten.

**Speicher – entschieden.** Neues optionales Feld `ClipEntry.sealedOCR: Data?` (CloudKit-tauglich, leichte
Migration). AES-GCM mit dem Verlauf-Schlüssel, Nonce je Feld, AAD = Datensatz-ID wie alle Felder (G38). Klartext nur
im Speicher (`ocrTexts`), solange Gnotchi läuft; nie ein Klartext-Index auf der Platte.
- `nil` = noch nicht erkannt. Chiffrat von `""` = erledigt ohne verwertbaren Text → wird nicht erneut gerechnet.
  Das gilt auch für **kein Text** und **Vision-/Dekodierfehler**: sonst würde jedes textlose oder kaputte Bild bei
  jedem Start neu gerechnet (Akku, Vorfall 0.17.1).
- Höchstens 20 000 Zeichen gespeichert, Rest abgeschnitten.
- **Verworfen:** bei jedem Start neu rechnen statt speichern (kein Feld) – kostet bei 92 Bildern grob 45–90 s Rechenzeit
  je Start (Akku). **Verworfen:** Klartext wie Hikidashi (`verlauf.json`) – widerspricht G38.
- Restrisiko (hingenommen): Chiffratlänge verrät die ungefähre Textlänge, wie bei Titel und Inhalt.

**Geheimnisse – entschieden.** Vor dem Speichern läuft der ganze Text, jede erkannte Zeile **und** jedes Stück einer
Zeile (getrennt an Leerraum, `=`, `:`, `,`, `;` und Anführungszeichen) durch `SecretDetector.kind(of:)`. Trifft eines,
wird **kein** Text gespeichert (Chiffrat von `""`), das Bild bleibt wie es ist. Grund: Die G43-Regel „nur ganze Kopie“
passt für Bilder nicht – ein Bildschirmfoto mit Schlüssel ist immer längerer Text, oft `API_KEY=sk-…`. Fehlalarm
kostet hier nur die Durchsuchbarkeit dieses einen Bildes, nicht den Eintrag. Protokoll nur Anzahl.
**Restrisiko (ehrlich, hingenommen):** Ein Schlüssel, den das Bild über zwei Zeilen umbricht, oder den die
Texterkennung verliest (0/O, l/1), passt auf kein Muster und wird durchsuchbar gespeichert – verschlüsselt, nur in
Gnotchis Suche. Ein abfotografierter Schlüssel kann also auftauchen; der Filter fängt nur die sauber gelesenen.

**Nie erkannt:** Tresor-Einträge (G39, Inhalt ohnehin nicht im Speicher), erkannte Geheimnisse (G43). Suche über
Bildtext gilt nur für `!isVault && secretKind == nil`.

**Parser-Fläche.** Keine neue: Bilddaten sind die schon gespeicherten G37-Formate, dekodiert per ImageIO wie die
Vorschaubilder (G40). Vor Vision wird per `CGImageSourceCreateThumbnailAtIndex` auf höchstens 2 560 px Kantenlänge
(≈ 4 MP) verkleinert – begrenzt Speicher und Rechenzeit. Die verwiesene Datei bei `.file` wird nie gelesen.

**Rechenlast (Vorfall 0.17.1).** Nie im Öffnen-Pfad. Eine serielle Hintergrund-Aufgabe (`Task.detached(priority:
.background)`), ein Bild nach dem anderen, nur Einträge mit `sealedOCR == nil`. Angestoßen nach dem Start und je
neuem Bild (dieselben Stellen wie `ClipThumbnails.prewarm`). Läuft schon eine Aufgabe, wird nicht doppelt gestartet.

**Netz, Prozesse, Berechtigungen.** Keine. Vision rechnet auf dem Gerät; kein neuer Entitlement, kein Socket.

**Löschen.** Eintrag löschen/Verlauf löschen/Zurücksetzen nimmt das Feld mit dem Datensatz mit, `forget` leert den
Speicher-Cache. Schalter aus → alle `sealedOCR` werden gelöscht (kürzeste Aufbewahrung), Suche ignoriert Bildtext;
wieder an → neu erkennen.

**Protokoll (G8).** Nur Anzahl und Dauer („Bildtext: 12 Bilder in 8 400 ms, 1 ohne Text gespeichert“), nie Text,
Länge je Bild oder Quell-App. Vision-Fehler ohne `error`-Text (Tippi-Befund 27.09.: Fragmente in der Meldung).

**„Text aus Bild kopieren“.** Schreibt nur `public.utf8-plain-text`. Wie jede eigene Kopie wird sie nicht erneut in
den Verlauf aufgenommen (`lastChange`). Kein Rendern, keine Links öffnen.

**STRIDE.**
- *S* nicht berührt (keine neue Identität/Grenze).
- *T* Präpariertes Bild als Fremddatum → nur ImageIO + Vision im Prozess, Ergebnis reiner Text, nie ausgeführt oder
  gerendert. Vision-Absturz durch Bild: gleiche Fläche wie Vorschaubild (G40).
- *R* nicht berührt.
- *I* Bildtext ist durchsuchbar und damit sichtbarer als vorher (Suche zeigt das Bild). Gegenmaßnahmen: Geheimnis-Zeilen
  → nicht gespeichert; Tresor nie; `sharingType = .none` unverändert; verschlüsselt auf der Platte.
- *D* Riesenbild / viele Bilder → Verkleinern, seriell, `.background`, einmal je Eintrag; Textlänge gedeckelt.
- *E* nicht berührt (keine neue Rechte, nichts ausgeführt).

## Abnahme

- Unit-Tests: Verschlüsselung/Laden des Felds, Suche findet Bild über Text, Tresor/Geheimnis nie, Geheimnis-Zeile →
  leerer Text gespeichert, Schalter aus löscht Felder, kein Doppelstart.
- Messung am System mit `scripts/bild-test.sh` (eigene Kennung, nicht Michaels Verlauf): Dauer je Bild, Öffnen der
  Liste bleibt schnell.
