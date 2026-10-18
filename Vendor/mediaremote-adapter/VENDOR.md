# mediaremote-adapter (eingespielt)

- Quelle: https://github.com/ungive/mediaremote-adapter
- Commit: 0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd (2026-10-17)
- Lizenz: BSD-3-Clause (`LICENSE`)
- Unverändert übernommen: `bin/`, `include/`, `src/`, `LICENSE`, `README.md`

## Update-Verfahren (docs/SECURE-DESIGN.md E17)

1. Neuen Commit klonen, `diff -r` gegen diesen Ordner, **jede** Änderung am Perl-Skript lesen.
2. Ordner ersetzen, SHA hier eintragen.
3. `make test` + Sichttest (Insel zeigt Spotify und einen Browser).
Die Signatur des Bundles deckt Skript und Framework ab; eine Prüfsumme muss nicht gepflegt werden.
