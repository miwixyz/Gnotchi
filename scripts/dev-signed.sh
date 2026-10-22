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

# Eigene, frisch angelegte Logdatei im (gitignorierten) build-dev/ statt eines festen /tmp-Namens
# (Security-Review 18.10., B5: ein fremder Prozess könnte /tmp/<fester Name> vorab als Symlink anlegen).
mkdir -p build-dev
LOG=$(mktemp "build-dev/dev-build.XXXXXX")
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi

SRC="build-dev/Build/Products/Debug/Gnotchi.app"
DEST_DIR=$(mktemp -d /tmp/gnotchi-test.XXXXXX)
APP="$DEST_DIR/Gnotchi.app"
ditto "$SRC" "$APP"
# Build-Nummer wie release.sh (Commit-Zahl), vor dem Signieren. Mit der Debug-Nummer 1 hielt Sparkle
# das veröffentlichte Release für neuer und spielte es über die Testkopie (20.10.: 0.2.0 → 0.1.0).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"

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
# 2c. Hilfsprogramm „Gnotchi Mitteilungen“ (0.6.0, G28): ohne Berechtigungen, eigene Kennung. Erst seine
# ausgelagerten Debug-Dylibs, dann das Paket. Developer ID ist Pflicht: Gnotchi startet es nur signaturgeprüft,
# beide Seiten prüfen sich am Socket, und die Bedienungshilfen-Freigabe hängt an dieser Signatur.
HELPER="$APP/Contents/Library/LoginItems/Gnotchi Mitteilungen.app"
if [ -d "$HELPER" ]; then
    for part in "$HELPER"/Contents/MacOS/*.dylib; do
        [ -e "$part" ] || continue
        codesign --force --options runtime --sign "$IDENTITY" "$part"
    done
    codesign --force --options runtime --sign "$IDENTITY" "$HELPER"
fi
# 3. Die App zuletzt, als einzige mit Gnotchis Berechtigung (Apple Events).
codesign --force --options runtime \
    --entitlements Gnotchi/Resources/Gnotchi.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p build-test
ln -sfn "$APP" build-test/Gnotchi.app

# Laufende Version freundlich beenden: Nur so kommt willTerminate an und Gnotchi stoppt den
# perl-Kindprozess. Erst nach 3 s ohne Ende hart (pkill) – dann kann perl verwaisen
# (killOrphans findet ihn nur unter demselben Pfad, jede Testkopie hat einen neuen).
if pgrep -x Gnotchi >/dev/null; then
    osascript -e 'tell application id "dev.mwlr.gnotchi" to quit' >/dev/null 2>&1 || true
    i=0
    while pgrep -x Gnotchi >/dev/null && [ "$i" -lt 30 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    pkill -x Gnotchi || true
fi
sleep 1
open "$APP" --args "$@"
echo "✓ Testversion gestartet: $APP"
