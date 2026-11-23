# transform-probe

Messprogramm für „Umwandeln“ (`specs/2026-11-23-gnotchi-ablage-umwandeln.md`, G63). Liest einen Ordner mit Bildern und PDFs und
misst Zeit, Größe, Speicherspitze und Ortsdaten beim Umwandeln (JPEG 0,85, lange Seite 2048/1280/800 px, zu einem PDF).

```bash
cd tools/transform-probe && swiftc -O probe.swift -o /tmp/transform-probe && /tmp/transform-probe "<ordner mit eigenen Dateien>"
```

Gibt **nur Zahlen** aus (keine Dateinamen), schreibt nie in den Quellordner, räumt seinen Wegwerf-Ordner auf.
Ergebnisse gehören in den Vault, nicht in dieses öffentliche Repo.
