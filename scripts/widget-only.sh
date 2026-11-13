#!/bin/sh
# widget-only.sh — genau EINE Gnotchi-Kopie meldet das Schreibtisch-Widget an (0.26.0, G49).
#
# Warum (13.11.): macOS meldet jede gebaute Gnotchi.app mit Widget an – Build-Ordner, /tmp-Testkopien, beiseitegelegte
# Altfassungen – und startete das Widget aus einer alten Zwischenkopie ohne Zugriff auf die App-Gruppe: Cover fehlte,
# Messpunkte blieben stumm, eine Runde Fehlersuche. Danach gilt nur noch die übergebene Kopie.
#
# Aufruf: sh scripts/widget-only.sh /Pfad/zu/Gnotchi.app   (von dev-signed.sh und install-signed.sh)
set -eu
[ -d "${1:-}" ] || { echo "✗ widget-only.sh: App fehlt: ${1:-}" >&2; exit 1; }
keep=$(cd "$1" && pwd -P)
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

for a in "$project_dir"/build*/Build/Products/*/Gnotchi.app /private/tmp/gnotchi-test.*/*.app \
         /private/tmp/gnotchi-install.*/*.app /Applications/Gnotchi.app; do
    [ -d "$a" ] || continue
    real=$(cd "$a" && pwd -P)
    [ "$real" = "$keep" ] && continue
    [ -d "$real/Contents/PlugIns/GnotchiWidget.appex" ] || continue
    pluginkit -r "$real/Contents/PlugIns/GnotchiWidget.appex" 2>/dev/null || echo "  (pluginkit -r ohne Erfolg: $real)"
    "$LSR" -u "$real" 2>/dev/null || echo "  (lsregister -u ohne Erfolg: $real)"
done
"$LSR" -f "$keep"
pluginkit -a "$keep/Contents/PlugIns/GnotchiWidget.appex"

# Wirkung prüfen, nicht den Schritt (Regel 7): genau diese eine Anmeldung.
reg=$(pluginkit -m -p com.apple.widgetkit-extension -v -A 2>/dev/null | grep 'dev.mwlr.gnotchi.widget' | awk -F'\t' '{print $NF}')
if [ "$reg" != "$keep/Contents/PlugIns/GnotchiWidget.appex" ]; then
    echo "✗ Widget angemeldet unter: ${reg:-nichts} (erwartet nur $keep)" >&2
    exit 1
fi
pkill -f 'GnotchiWidget.appex/Contents/MacOS/GnotchiWidget' 2>/dev/null || true   # alter Widget-Prozess, startet neu
echo "✓ Widget nur aus $keep"
