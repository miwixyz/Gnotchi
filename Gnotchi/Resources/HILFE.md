# Gnotchi – Hilfe

Gnotchi lebt in der Menüleiste (Symbol: Kapsel). Ein Klick darauf öffnet das Menü mit
Einstellungen, Hilfe, Update-Suche und Beenden.

## Was kommt: Musik in der Notch

**In Arbeit, in dieser Version noch nicht sichtbar.** Geplant ist eine Insel in der Notch des
MacBook, auf Bildschirmen ohne Notch eine Pille oben in der Mitte. Läuft Musik oder ein Video,
zeigt sie klein Cover und Pegel, beim Darüberfahren groß Titel, Interpret, Tasten und Fortschritt.
Gedacht für alle Quellen: Spotify, Musik und Browser wie Safari, Edge oder Helium.

Die Datenquelle dafür ist schon eingebaut und geprüft, die Insel selbst folgt.

## Nur eine Notch-App gleichzeitig

Zwei Apps, die über die Notch zeichnen (z. B. NotchNook, Boring Notch, Alcove), überdecken sich
gegenseitig. Erkennt Gnotchi eine solche App, steht oben im Menü und in den Einstellungen ein
Hinweis mit ihrem Namen. Dann eine der beiden beenden oder deren Notch-Anzeige ausschalten.
Gnotchi prüft das, während die Insel sichtbar ist, und liest dafür nur Lage und Ebene der Fenster
und den Namen der App – keine Fenstertitel, keine Inhalte.

## Einstellungen

- **Musik in der Notch:** schaltet die Insel ein oder aus. Ab Werk an. Wirkt, sobald die Insel
  da ist.
- **Aufklappen nach:** wie lange die Maus über der kleinen Insel bleiben muss, bis sie groß aufgeht
  (Sofort, 0,3 s, 0,6 s oder 1 s; ab Werk 0,6 s) – so stört ein flüchtiges Überfahren nicht.
- **Bei Anmeldung starten:** Gnotchi startet nach dem Anmelden. Meldet macOS „wartet auf deine
  Freigabe“, gib Gnotchi unter Systemeinstellungen → Allgemein → Anmeldeobjekte frei.

## Berechtigungen

Gnotchi braucht **keine Bedienungshilfen-Freigabe** und fragt auch nie danach.

Nur wenn macOS den systemweiten Zugriff auf die Wiedergabe sperrt, steuert Gnotchi Spotify und
Musik direkt. Spulen in Spotify läuft immer direkt, sonst springt die Zeit über Spotify Connect
zurück. Beim ersten Mal fragt macOS, ob Gnotchi diese App steuern darf. Erlauben oder später
ändern unter Systemeinstellungen → Datenschutz & Sicherheit → Automation.

Titel, Interpret und Cover bleiben im Speicher. Gnotchi speichert sie nicht, schreibt sie nicht
ins Protokoll und schickt sie nirgendwohin.

## Updates

„Nach Updates suchen …“ im Menü. Beim ersten Mal fragt Gnotchi, ob es selbst nach Updates suchen
darf. Findet es eines, steht es oben im Menü. Updates sind signiert, Gnotchi installiert nur, was
mit Michaels Schlüssel signiert ist.
