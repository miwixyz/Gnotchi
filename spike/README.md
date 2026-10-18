# spike/ – nur SYNTHETISCHE Daten

Hier liegen Beispiele des Adapter-Stroms, damit Aufbau und Felder nachvollziehbar sind.
Alles darin ist **erfunden**: Titel, Interpreten, Alben, Werbetitel und IDs. Aufbau, Zahlen und
Zeitpunkte stammen aus einer Messung, die Inhalte nicht.

## Die Regel

- **Messdaten nur nach `/tmp`, nie in einen Repo-Ordner.** Ein Mitschnitt zeigt, was jemand hört
  und sieht. Das ist privat.
- Ein Beispiel kommt erst hierher, wenn jeder Inhalt umgeschrieben ist.
- Jede Datei in `spike/` trägt in **Zeile 1 das Wort `SYNTHETISCH`**. Bei `.jsonl` als eigene
  erste Zeile:

  ```
  {"_hinweis":"SYNTHETISCH – erfundene Beispieldaten, keine echten Hördaten"}
  ```

  Diese Zeile hat kein `payload`. Wer die Datei einliest, überspringt sie wie jede andere Zeile
  ohne `payload`.

## Wer das prüft

`scripts/privacy-gate.sh`, bei `make lint`, vor jedem Commit (`make hooks` einmal ausführen) und
vor jedem Release. Es lehnt ab:

- Dateien mit „mitschnitt“ oder „capture“ im Namen, egal wo,
- `.jsonl` außerhalb von `spike/`,
- Dateien in `spike/` ohne `SYNTHETISCH` in Zeile 1,
- Testdateien mit Now-Playing-Zeilen (`"payload"` und `"title"`) ohne `// SYNTHETISCH` oben.

Ob ein Titel echt ist, weiß das Skript nicht. Die Markierung ist deine Unterschrift, dass er es
nicht ist. Hintergrund: [docs/SECURE-DESIGN.md](../docs/SECURE-DESIGN.md), G16.
