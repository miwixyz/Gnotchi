# SwiftTerm (eingespielt)

- Quelle: https://github.com/migueldeicaza/SwiftTerm
- Version: v1.99.3, Commit 282c3c3a932b55c129628876b70f37d993af1615 (Stand 2026-11-24)
- Lizenz: MIT (`LICENSE`, mehrere Urheber, Powerline-Symbole von Ryan L McIntyre)
- Übernommen: `Sources/SwiftTerm/` ohne `Documentation.docc`, `iOS/` und `Apple/Metal/Shaders.metal`
- **Erzeugt, nicht aus dem Repository:** `SwiftTermBuildInfo.swift` und `SwiftTermTerminfo.swift` schreibt das Build-Plugin
  `SwiftTermBuildInfoPlugin` des Pakets. Es läuft hier nicht (kein Paket, kein Plugin, kein fremder Code beim Bauen).
  Die Dateien stammen aus einem Lauf von `swift build --target SwiftTerm` auf genau diesem Commit.
- Nur das Hilfsprogramm **Gnotchi Terminal** kompiliert den Ordner, nie Gnotchi selbst (docs/SECURE-DESIGN.md G65).
- **Keine Änderungen am Quelltext.** Zwischenablage (OSC 52) und Links überschreibt `GnotchiTerminal/GuardedTerminalView.swift`
  in einer Unterklasse; das geht ohne Eingriff, weil der Quelltext im selben Modul liegt.

## Update-Verfahren

1. Neues Tag klonen, `diff -r` gegen `Sources/`, Änderungen an `LocalProcess.swift`, `Pty.swift`, `MacLocalTerminalView.swift`,
   `TerminalLinkOpening.swift`, `UntrustedTerminalLink.swift`, `KittyClipboard*.swift` lesen (Prozessstart, Zwischenablage, Links).
2. `swift build --target SwiftTerm` im Klon, die zwei erzeugten Dateien unter `.build/plugins/outputs/…/Generated/` übernehmen.
3. Ordner ersetzen, Version und Commit hier eintragen, `make test` und die Messliste in `specs/2026-11-24-gnotchi-terminal.md`.
