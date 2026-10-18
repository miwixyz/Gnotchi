#!/bin/sh
# dev-signed.sh — Testversion bauen, mit Developer ID signieren und starten.
#
# Warum Developer ID (Lehre aus Kalli, 2026-09-29): TCC bindet Freigaben (bei Gnotchi:
# Automation für Spotify/Musik) an die Signatur, und Gnotchi startet den Medien-Adapter
# nur aus einem Bundle mit Michaels Team-Signatur (docs/SECURE-DESIGN.md G2). Ad hoc
# signiert bliebe die Insel leer.
# Signiert wird immer eine frische KOPIE unter /tmp: Ein so signiertes Paket
# schützt macOS gegen Änderungen, ein zweiter Build in denselben Ordner
# scheiterte bei Kalli mit „Operation not permitted“.
#
# Von innen nach außen, OHNE --deep (anders als Seam bis 0.6): `--deep --entitlements`
# hätte Gnotchis Berechtigung auch dem Test-Programm und dem Framework des Adapters
# gegeben — genau den Teilen, die unter /usr/bin/perl laufen. Eingebetteter Code bekommt
# KEINE Berechtigungen (G12), Sparkles Teile behalten ihre eigenen.
#
# Aufruf:  ./scripts/dev-signed.sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

LOG=/tmp/gnotchi-dev-build.log
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi

SRC="build-dev/Build/Products/Debug/Gnotchi.app"
DEST_DIR=$(mktemp -d /tmp/gnotchi-test.XXXXXX)
APP="$DEST_DIR/Gnotchi.app"
ditto "$SRC" "$APP"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

# 1. Sparkle: eigene Berechtigungen der Hilfsprogramme erhalten (wie install-signed.sh).
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --preserve-metadata=entitlements --sign "$IDENTITY" "$part"
done
# 2. Medien-Adapter: ohne Berechtigungen.
for part in "$APP/Contents/MacOS/MediaRemoteAdapterTestClient" \
            "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"; do
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done
# 2b. Debug-Build: Xcode lagert den App-Code in Gnotchi.debug.dylib (+ __preview.dylib) aus.
# Ohne eigene Signatur lädt dyld sie nicht (anderes Team als die App, gemessen 18.10.:
# Absturz beim Start „Library missing … different Team IDs“). Dylibs tragen keine Berechtigungen.
for part in "$APP"/Contents/MacOS/*.dylib; do
    [ -e "$part" ] || continue
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done
# 3. Die App zuletzt, als einzige mit Gnotchis Berechtigung (Apple Events).
codesign --force --options runtime \
    --entitlements Gnotchi/Resources/Gnotchi.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p build-test
ln -sfn "$APP" build-test/Gnotchi.app

pkill -x Gnotchi || true
sleep 1
open "$APP" --args "$@"
echo "✓ Testversion gestartet: $APP"
