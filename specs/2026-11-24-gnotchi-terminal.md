# Gnotchi – Terminalfenster (Entwurf, Sicherheitsentwurf G65)

Stand 2026-11-24 (Mac mini). Anlass: Michael, 24.11.: „Ein Terminalfenster wäre noch schön.“ Auf Rückfrage gewählt:
**eigenes Fenster mit echter Shell** (nicht nur Knopf für Terminal.app, nicht nur Anzeige in der Insel).

## Was Michael bekommt

- Knopf **„Terminal“** im Fuß des Menüleisten-Popovers (neben Einstellungen, Hilfe, Updates, Beenden). Er öffnet ein normales,
  verschiebbares Fenster mit einer Login-Shell (zsh) in `~`. Mehrere Fenster möglich (⌘N), jedes mit eigener Shell.
- Schalter in Einstellungen → Allgemein: **„Terminal-Fenster anbieten“**, ab Werk **aus** (wie Schnelleingabe und Stream Deck:
  ein Fenster mit Shell ist keine Funktion, die ungefragt da sein soll). Aus = kein Knopf, nichts startet.
- Kopieren/Einsetzen (⌘C/⌘V), Suchen (⌘F), Schriftgröße (⌘+ / ⌘−), Auswahl per Maus, Scrollen, Links nur mit ⌘-Klick.
- Schließen mit laufendem Programm (außer der Shell) fragt zuerst. Ohne laufendes Programm schließt es sofort.

## Warum die Insel selbst es nicht kann

Das Insel-Fenster ist nie aktiv und nimmt keine Tastatur an (`IslandPanel`, **G1** verbietet globale Tasten-Beobachter). Tippen in
der Insel scheidet damit aus. Ein eigenes Fenster hat diese Beschränkung nicht, bringt aber eine Shell mit Nutzerrechten ins Spiel
(unten, G65).

## Aufbau

- **Eigenes Hilfsprogramm „Gnotchi Terminal“** (`dev.mwlr.gnotchi.terminal`, `Contents/Helpers/Gnotchi Terminal.app`), gleiches
  Muster wie „Gnotchi Claude“ und „Gnotchi Mitteilungen“. **Keine Entitlements, keine Sandbox, kein Socket zu Gnotchi.**
  Gnotchi startet es nur per `NSWorkspace.openApplication` aus dem eigenen Bundle, nach einer Signaturprüfung.
- **Grund für die Trennung:** Die Shell erbte sonst als Kindprozess Gnotchis Freigaben (Kamera, Apple Events, App-Gruppe,
  Schlüsselbund-Gruppe). Seam hat dieselbe Frage bei E17 so entschieden. Beim Helfer ist der „verantwortliche Prozess“ der Helfer
  selbst; macOS fragt für Ordner wie Dokumente oder Schreibtisch unter **„Gnotchi Terminal“** nach, nicht unter Gnotchi.
  **Zu messen (Regel 6/D):** `tools/responsible-pid.swift` an einer echten Shell des Helfers, Gegenprobe Gnotchi selbst.
- **Terminalemulator: SwiftTerm v1.99.3** (Miguel de Icaza, MIT, Commit siehe `Vendor/SwiftTerm/VENDOR.md`), **als Quelltext
  eingespielt, kein Paket**: Die Regel „genau EINE Paket-Abhängigkeit (Sparkle)“ bleibt, wie beim Medien-Adapter. Kompiliert wird
  er **nur im Helfer**, nie in Gnotchi. Das Build-Plugin des Pakets entfällt; die zwei erzeugten Dateien
  (`SwiftTermBuildInfo.swift`, `SwiftTermTerminfo.swift`) liegen fest im Vendor-Ordner. Nicht eingespielt: Dokumentation,
  Metal-Shader, Beispiele, Fuzzer, Termcast.
- Eigener Code im Helfer (`GnotchiTerminal/`): App-Delegate und Menü, Fensterverwaltung, Unterklasse von
  `LocalProcessTerminalView` (die Standard-Zwischenablage- und Linkpfade werden **überschrieben**, siehe G65), und
  `TerminalRules.swift` mit den reinen, testbaren Regeln (Shell wählen, Umgebung bauen, Titel säubern, „läuft noch etwas?“).

## Nicht Teil dieser Stufe

Tabs, Sitzungswiederherstellung, Profile/Farbschemata, Kürzel zum Öffnen aus beliebiger App, Anzeige in der Insel, Aufnahme-Sperre
(G58 gilt der Insel; ein Terminalfenster ist ein normales Fenster und erscheint in Bildschirmfreigaben wie Terminal.app).

## Zu messen vor „fertig“

1. Shell startet, `echo $0` zeigt `-zsh`, `pwd` = Home, PATH enthält Homebrew (kommt aus `.zprofile`, nicht aus Gnotchi).
2. Responsible-PID der Shell = Helfer, nicht Gnotchi (`tools/responsible-pid.swift`).
3. Fenster zu mit laufendem `sleep 100` fragt; ohne laufendes Programm nicht; nach dem Schließen kein verwaister `zsh`.
4. OSC 52 gelesen/geschrieben: `printf '\e]52;c;?\a'` liefert nichts, Zwischenablage bleibt unverändert.
5. Gnotchi ohne Schalter: kein Knopf, kein Helferprozess. Schalter aus während Fenster offen: Fenster bleiben (nie Shell töten).
6. Signierter Build: Helfer einzeln gültig signiert, hardened runtime, **ohne** Entitlements (`codesign -d --entitlements`).
7. Selbsttest `make test`, ZIP-Bündel enthält den Helfer, `scripts/release.sh`-Prüfungen kennen ihn.
