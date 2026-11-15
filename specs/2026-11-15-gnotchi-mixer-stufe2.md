# Gnotchi – Mixer Stufe 2: Regler je App über Prozess-Taps

Stand 2026-11-15, **Entwurf mit Sicherheitsfragen (`rafter-secure-design`), noch nicht gebaut.** Michael: „Mixer Stufe 2“ (15.11.),
nach Stufe 1 (Meeting-Leiser) und dem Mixer-Popover (0.30.0). Ziel: Der Mixer-Reiter bekommt für **jede** App mit Ton einen
Regler, nicht nur für Spotify und Musik (Browser, FaceTime, Teams, …). Grundlage: Spike und Messläufe
`2026-11-15-gnotchi-lautstaerkemixer-meeting-leiser.md` („Stand Spike“, Anforderungen), `tools/tap-probe.swift`.

## Heute (Stand 5c65612)

- Mixer-Zeile je App: Name, Gerät mit Übertragungsart, Regler **nur** für Spotify/Musik (AppleScript, wenn erlaubt).
- Gemessen am MacBook: Prozess-Taps (`AudioHardwareCreateProcessTap`, Geräte-Tap, privates Aggregat-Gerät) tragen: Spotify, Apple
  Music, YouTube in Helium, 0 Aussetzer, 23,3 ms Latenz, <0,35 % CPU, Hörtest sauber, Umleiten auf anderes Gerät belegt.
  **Aus dem Terminal gemessen** – das gilt nicht für Gnotchi selbst (Regel D).

## Was gebaut würde

1. **Tap-Motor `AppVolumeTap`:** je App ein Tap (alle ihre Audio-Prozesse, Geräte-Tap auf dem Gerät, auf dem sie spielt) und ein
   privates Aggregat-Gerät; ein Audio-Rückruf kopiert den Eingang mit Verstärkung `g` (0…1) auf den Ausgang desselben Geräts.
2. **Regler je App** im Mixer für alle Zeilen. Spotify/Musik behalten den AppleScript-Weg (kein Tap nötig, keine neue Freigabe).
3. **Einstellung** „Lautstärke je App (Audio-Aufnahme)“, **ab Werk aus**; erst beim Einschalten wird die Freigabe erklärt.

## Sicherheitsentscheidungen (Vorschlag)

**A. Die Freigabe.** Prozess-Taps brauchen die Freigabe „Audio-Aufnahme“ (TCC, `NSAudioCaptureUsageDescription`). Sie erlaubt Gnotchi,
**den Ton jeder App mitzuhören**. Das ist die schwerste Freigabe, die Gnotchi je angefragt hätte (bisher: Automation für Spotify/Musik,
Kamera für den Spiegel). Deshalb: **ab Werk aus, erst auf Wunsch, nie automatisch.** Der Dialog erscheint beim ersten Ziehen eines
App-Reglers; der Einstellungstext sagt vorher, was die Freigabe bedeutet. Der Text in der Info.plist nennt nur den Zweck.
Wird sie verweigert: Regler bleiben aus, kein erneutes Fragen in Schleife, Hinweis in den Einstellungen.

**B. Leiser und lauter, mit Begrenzer (Michael 15.11.: „auch lauter“).** Verstärkung 0…2 (0 bis 200 %). **Weichbegrenzer** im Rückruf, nur
oberhalb von 0,8: unterhalb unverändert, darüber gleitend auf höchstens 1,0 (`tanh`-Knie), damit nichts hart übersteuert (Apple Music hatte
Eingangsspitzen von 1,037). Bei g ≤ 1 läuft der Ton **ohne** Begrenzer (nur Multiplikation), so bleibt „leiser“ bitgenau skaliert.
Grenze: Lauter als das Quellmaterial gibt es nur mit Verzerrung bei sehr lauten Titeln; der Begrenzer mildert das, ersetzt aber keine Lautheit.

**C. Der Tap lebt nur, solange er etwas tut.** Ein Tap existiert **nur**, solange der Regler dieser App **nicht auf 100 % steht**
(oder der Meeting-Leiser sie senkt). Bei 100 % wird er sofort zerstört, die App spielt wieder direkt. Folge: Im Normalzustand greift Gnotchi
**keinen** Ton ab, auch mit eingeschalteter Einstellung. Die Freigabe wird nur beim Ziehen gebraucht.

**D. Nie stumm hängen lassen (wie G52/G53).** Solange der Tap das Original stumm schaltet (`mutedWhenTapped`), hängt der Ton der App an
unserem Audio-Rückruf. Fällt der aus (Gerätewechsel, Fehler, Absturz), muss die App wieder hörbar werden:
- Tap und Aggregat-Gerät gehören dem Prozess: **Beenden oder Absturz zerstört sie** (gemessen: nach Ende des Messprogramms war alles normal).
- Gerätewechsel (AirPods ein/aus, Ausgang umgestellt): Tap **sofort zerstören**, dann neu aufbauen; schlägt das fehl, bleibt die App unverändert
  laut, nicht still.
- Jede Fehlermeldung beim Aufbau (`AudioHardwareCreateProcessTap` ≠ noErr, fehlende Freigabe: liefert macOS Nullen statt Fehler → Kontrolle
  über Pegel) führt zu: kein Tap, App unverändert, Hinweis in der Zeile. **Nie** „Erfolg“ melden, wenn Stille ankommt.

**E. Daten.** Ton und Pegel bleiben **im Arbeitsspeicher**, werden nie in eine Datei geschrieben, nie ins Netz gesendet, nie protokolliert
(Protokoll nur: Anzahl, OSStatus, Übertragungsart – nie App- oder Gerätename, nie Pegel). Der Rückruf kopiert Puffer und multipliziert;
er hält nichts länger als einen Puffer. Gespeichert wird **nichts** außer dem Schalter selbst.

**F. Kein neuer Prozess, kein Netz, keine Berechtigungsausweitung sonst.** Kein Sandbox-Ausbruch, kein Hilfsprogramm, keine Bedienungshilfen.
**Zu messen:** ob Gnotchi (Hardened Runtime, ohne Sandbox) zusätzlich die Berechtigung `com.apple.security.device.audio-input` braucht.
Wenn ja: `scripts/entitlement-gate.sh` und die Positivliste (G12) anpassen und die Berechtigung in README/SECURE-DESIGN begründen.

## Vertrauensgrenzen und Datenfluss

```
[App, z. B. Browser]  ┆  Core Audio (Prozess-Tap)  ┆  [Gnotchi: Rückruf, g × Puffer]  →  [Aggregat-Gerät, privat]  →  [echtes Ausgabegerät]
        Ton (PCM)                                         nur Arbeitsspeicher                     Ton (PCM)
```
Grenzen: (1) App → Core Audio (macOS entscheidet nach Freigabe), (2) Core Audio → Gnotchi-Rückruf (Echtzeit-Thread), (3) Gnotchi → Aggregat-Gerät.
Nichts verlässt den Prozess.

## STRIDE für diesen Entwurf

- **S (Spoofing):** Gnotchi greift nur Prozesse ab, die der Nutzer im Mixer sieht (Zeilen aus `kAudioProcessPropertyIsRunningOutput`). Ein Programm, das
  sich wie eine bekannte App nennt, kann dadurch nur seinen **eigenen** Ton leiser bekommen. Kein Fremdziel durch Eingaben von außen: die Prozess-IDs
  kommen aus Core Audio, nicht aus Nutzer- oder Netzdaten.
- **T (Tampering):** Verstärkung wird auf 0…1 begrenzt (Regler und gespeicherte Werte). Der Tap-Motor akzeptiert nur Prozessobjekte aus der
  aktuellen Liste. Ein manipuliertes Aggregat-Gerät: privat (`IsPrivate`), nur im eigenen Prozess sichtbar.
- **R (Repudiation):** Kein Protokoll mit Inhalt. Protokoll nur: „Tap angelegt/entfernt (Art, Status)“. Der Nutzer sieht den Zustand in der Zeile
  (Symbol „leiser durch Gnotchi“).
- **I (Information disclosure):** Das ist das Hauptrisiko: **Gnotchi hört mit, solange ein Tap läuft.** Gegenmaßnahmen: ab Werk aus; Tap nur bei
  Regler < 100 %; Ton nie speichern, nie senden, nie protokollieren; Rückruf ohne Analyse (kein Pegel, kein Spektrum; der Spike-Pegelmesser
  **nicht** in die App); keine Anzeige von Titeln oder Inhalten aus dem Ton. Ein Fehler, der Inhalt in ein Protokoll schriebe, wäre ein 🔴 Fund.
- **D (Denial of service):** Aussetzer oder Stille durch einen hängenden Tap → siehe D oben (zerstören statt weiterlaufen). Rückruf in Echtzeit:
  keine Speicherzuweisung, keine Sperren, keine Aufrufe in Swift-Concurrency im Rückruf (`@unchecked Sendable`-Zähler wie im Spike genügt nicht für
  Produktion: Verstärkung als atomarer Wert). Zu viele Taps: höchstens 6 gleichzeitig, danach „Regler nicht verfügbar“.
- **E (Elevation of privilege):** Die Freigabe selbst ist die Erhöhung. Sie ist **für Gnotchi**, nicht für Hilfsprogramme. Kein Pfad, über den ein
  anderes Programm Gnotchi dazu bringt, Ton abzugreifen: Tap entsteht nur nach Klick im Mixer; Befehle von außen (Tippi, Kalli, Widget) erreichen den
  Tap-Motor nicht.

**Negativraum (stillschweigende Annahmen):** (1) macOS fragt die Freigabe pro App-Signatur, nicht pro Gerät – bei Updates mit gleicher Signatur
bleibt sie. (2) Kopiergeschütztes Audio kann bei Taps stumm oder verfälscht ankommen (nicht gemessen; Fernseh-/Streaming-Inhalte). (3) Bluetooth-
Geräte mit anderem Format als 48 kHz/Stereo: der Rückruf kopiert nach Kanalzahl, ob das für jedes Gerät stimmt, ist **nicht gemessen**.
(4) Eine App, die selbst Prozesse neu startet (Browser-Helfer), ändert die Prozessliste: Tap folgt der Liste (neu aufbauen).

## Entscheidungen, die ich Michael vorlege

1. **Ab Werk aus, Freigabe erst beim ersten Ziehen** (statt sofort beim Einschalten). Vorschlag: so.
2. ~~Nur leiser~~ **Entschieden (Michael): leiser und lauter, 0…200 % mit Weichbegrenzer.**
3. **Tap nur bei Regler ≠ 100 %.** Vorschlag: so (kleinste Dauer des Mithörens).
4. **Browser = eine Zeile.** Ein Tab lässt sich nicht trennen. Vorschlag: so, mit Hinweis.
5. **Meeting-Leiser auch für andere Apps?** Stufe 1 nur Spotify/Musik. Mit Taps könnte er beliebige Apps (auch Browser-Musik) senken.
   Vorschlag: **nicht in diesem Schritt**, erst wenn der Tap-Motor sich im Alltag bewährt hat.

## Zu messen beim Bau (in einer Gnotchi-Mess-Fassung, nicht im Terminal)

1. Erscheint der Dialog „Audio-Aufnahme“ für **Gnotchi** (Developer-ID-Testkopie), und mit welchem Text? Braucht es `device.audio-input`?
2. Verweigert → keine Schleife, sauberer Zustand, Hinweis.
3. Gerätewechsel mitten im Tap (AirPods ein/aus, Lautsprecher ↔ Teams-Gerät): Ton nie stumm hängen.
4. Mehrere Apps gleichzeitig (Spotify per AppleScript, Helium per Tap, Musik per Tap).
5. Bluetooth (Format), AirPlay, mono (Teams-Gerät, gemessen 1 Kanal).
6. Kopiergeschützter Inhalt (z. B. ein Streamingdienst im Browser): stumm oder verfälscht?
7. Gnotchi beenden/abstürzen lassen, während ein Tap läuft: App wieder hörbar.
8. CPU/Akku mit drei Taps (Aktivitätsanzeige).

## Aufwand

Mittel bis groß, *vermutlich* 2 Bausitzungen: Tap-Motor (Lebenszyklus, Gerätewechsel, Fehler) ist der fehleranfällige Teil; Oberfläche und
Einstellung klein; Mess-Fassung mit echter Freigabe braucht Michael vor Ort. Reine Teile getestet: Verstärkungs-Begrenzung, Zustandsmaschine
(an/aus je App), Fehlerpfade mit Attrappe; der echte Tap nur am echten System.

## Offen

Entscheidung 2 ist beantwortet („auch lauter“), 1, 3, 4, 5 gelten als Vorschlag, bis Michael widerspricht (Antwort auf die Sammelfrage:
„Wie oben, aber auch lauter“ = Ab Werk aus, Freigabe erst beim ersten Ziehen, Tap nur bei Regler ≠ 100 %, Ton nie gespeichert).
