#!/bin/sh
# privacy-gate.sh — keine echten Hördaten im Repo (docs/SECURE-DESIGN.md G16).
#
# Warum es das gibt (2026-10-18): Ein echter Now-Playing-Mitschnitt (was Michael gehört hat)
# landete in spike/, echte Titel in Tests und Spezifikation. Die Historie musste mit
# git filter-repo umgeschrieben werden. Ein Vorsatz („vor dem Einchecken umschreiben“) hat das
# nicht verhindert, deshalb dieses Gate. Es läuft an drei Stellen:
#   make lint           → sh scripts/privacy-gate.sh            (Index + ungetrackte Dateien)
#   scripts/release.sh  → sh scripts/privacy-gate.sh            (vor dem Bauen)
#   .githooks/pre-commit→ sh scripts/privacy-gate.sh --staged   (nur, was gerade committet wird)
#
# Geprüft wird bewusst nur, was sich ohne Raten prüfen lässt:
#   (a) Pfade: nichts mit „mitschnitt“ oder „capture“ im Namen, keine .jsonl außerhalb von spike/;
#       jede Datei in spike/ trägt in Zeile 1 das Wort SYNTHETISCH.
#   (b) Testdaten: Eine Datei unter GnotchiTests/ mit einer Now-Playing-Zeile ("payload" und
#       "title" in derselben Zeile) braucht in den ersten 10 Zeilen den Kommentar // SYNTHETISCH.
# Ob ein Titel echt ist, kann kein Skript wissen. Die Markierung ist eine bewusste Unterschrift:
# wer sie setzt, hat die Daten umgeschrieben.
#
# Kein Übergehen per Variable: Eine falsch markierte Datei umbenennen oder markieren ist der Weg.

set -u
cd "$(dirname "$0")/.." || exit 1

MODE=all
[ "${1:-}" = "--staged" ] && MODE=staged

LIST=$(mktemp "${TMPDIR:-/tmp}/gnotchi-privacy.XXXXXX") || exit 1
trap 'rm -f "$LIST"' EXIT

# Pfade sammeln, eine Zeile je Datei, ohne Oktal-Maskierung von Umlauten.
if [ "$MODE" = staged ]; then
    git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMR > "$LIST" || exit 1
else
    { git -c core.quotePath=false ls-files
      git -c core.quotePath=false ls-files --others --exclude-standard; } > "$LIST" || exit 1
fi

# Inhalt so lesen, wie er committet wird: im --staged-Modus aus dem Index, sonst aus dem Arbeitsbaum.
content() {
    if [ "$MODE" = staged ]; then
        git show ":$1" 2>/dev/null
    elif [ -f "$1" ]; then
        cat "$1"
    fi
}

FAIL=0
bad() { printf '  ✗ %s\n    → ZU TUN: %s\n' "$1" "$2"; FAIL=1; }

echo "▶ Datenschutz-Gate ($MODE)"

while IFS= read -r f; do
    [ -n "$f" ] || continue
    lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')

    # (a) Pfade
    case "$lower" in
        *mitschnitt*|*capture*)
            bad "$f: Name deutet auf einen Mitschnitt" \
                "Datei aus dem Repo nehmen (git rm --cached \"$f\") und nach /tmp legen. Messdaten nie in einen Repo-Ordner."
            continue ;;
    esac
    case "$f" in
        spike/*)
            if ! content "$f" | head -n 1 | grep -q 'SYNTHETISCH'; then
                bad "$f: Zeile 1 trägt nicht das Wort SYNTHETISCH" \
                    "Nur erfundene Daten nach spike/. Echte Werte umschreiben, dann als Zeile 1 eintragen (siehe spike/README.md)."
            fi
            continue ;;
        *.jsonl|*.JSONL)
            bad "$f: .jsonl außerhalb von spike/" \
                "Strom-Mitschnitte gehören nach /tmp. Erfundene Beispiele nach spike/ mit SYNTHETISCH-Zeile."
            continue ;;
    esac

    # (b) Testdaten mit Now-Playing-Zeilen
    case "$f" in
        GnotchiTests/*)
            if content "$f" | grep -q -E '"payload".*"title"|"title".*"payload"'; then
                if ! content "$f" | head -n 10 | grep -q '// SYNTHETISCH'; then
                    bad "$f: enthält Now-Playing-Zeilen mit \"title\", aber keinen Kommentar // SYNTHETISCH oben" \
                        "Titel, Interpreten, Alben und IDs erfinden, dann in den ersten 10 Zeilen: // SYNTHETISCH – erfundene Beispieldaten, keine echten Hördaten"
                fi
            fi ;;
    esac
done < "$LIST"

if [ "$FAIL" -ne 0 ]; then
    echo "🚫 Datenschutz-Gate nicht bestanden. Hintergrund: docs/SECURE-DESIGN.md G16."
    exit 1
fi
echo "✅ Datenschutz-Gate bestanden: $(grep -c . "$LIST" | tr -d ' ') Datei(en) geprüft"
exit 0
