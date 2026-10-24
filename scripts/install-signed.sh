#!/bin/sh
# install-signed.sh — signierte Testfassung nach /Applications (zum Ausprobieren vor einem Release).
#
# Warum: Die Testkopien liegen unter /tmp (macOS leert das beim Neustart), und der
# Autostart (SMAppService) braucht einen festen Ort. Release-Build, mit Developer ID und
# Hardened Runtime signiert (gleiche Identität wie die Testkopien; TCC bindet Freigaben an
# Kennung + Team, nicht an den Pfad).
#
# Aufruf:  sh scripts/install-signed.sh   (oder: make install)
set -eu
cd "$(dirname "$0")/.."
# Eigene, frisch angelegte Logdatei im (gitignorierten) build-dev/ statt eines festen /tmp-Namens
# (Security-Review 18.10., B5: ein fremder Prozess könnte /tmp/<fester Name> vorab als Symlink anlegen).
mkdir -p build-dev
LOG=$(mktemp "build-dev/install-build.XXXXXX")
if ! make build CONFIG=Release DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi
IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

STAGE=$(mktemp -d /tmp/gnotchi-install.XXXXXX)
ditto build-dev/Build/Products/Release/Gnotchi.app "$STAGE/Gnotchi.app"
# Build-Nummer wie release.sh (Anzahl Commits). Sonst trägt die lokale Fassung Build 1 und
# Sparkle bietet das letzte Release als „Update“ an — das wäre ein Rückschritt (Seam, 09.10.).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$STAGE/Gnotchi.app/Contents/Info.plist"
# Von innen nach außen, ohne --deep (Sparkle rät davon ab; Seam, Rafter-Fund F3): Sparkles
# Hilfsprogramme behalten ihre eigenen Berechtigungen, nur die App bekommt Gnotchis.
SPK="$STAGE/Gnotchi.app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$STAGE/Gnotchi.app/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
        --sign "$IDENTITY" "$part"
done
# Medien-Adapter (G2/G12): eigene Teile von innen nach außen signieren, ohne Gnotchis Berechtigungen.
for part in "$STAGE/Gnotchi.app/Contents/MacOS/MediaRemoteAdapterTestClient" \
            "$STAGE/Gnotchi.app/Contents/Frameworks/MediaRemoteAdapter.framework"; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$part"
done
# Hilfsprogramm „Gnotchi Mitteilungen“ (0.6.0, G28): ohne Berechtigungen. Unsigniert startete Gnotchi es nie
# (Signaturprüfung vor dem Start) – Review 22.10.
HELPER="$STAGE/Gnotchi.app/Contents/Library/LoginItems/Gnotchi Mitteilungen.app"
if [ -d "$HELPER" ]; then
    for part in "$HELPER"/Contents/MacOS/*.dylib; do
        [ -e "$part" ] || continue
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$part"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$HELPER"
fi
# Ab 0.11.0 (G38): Profil einbetten + Berechtigungen mit ausgeschriebener App-Kennung (scripts/profile.sh).
. scripts/profile.sh
gnotchi_embed_profile "$STAGE/Gnotchi.app"
gnotchi_expanded_entitlements Gnotchi/Resources/Gnotchi.entitlements "$STAGE/Gnotchi.entitlements"
codesign --force --options runtime --timestamp \
    --entitlements "$STAGE/Gnotchi.entitlements" --sign "$IDENTITY" "$STAGE/Gnotchi.app"
codesign --verify --deep --strict "$STAGE/Gnotchi.app"

osascript -e 'quit app id "dev.mwlr.gnotchi"' || echo "  (Gnotchi lief nicht)"
sleep 1
# Alte Fassung nicht löschen, sondern beiseite legen (bleibt unter /tmp liegen).
if [ -e /Applications/Gnotchi.app ]; then
    mv /Applications/Gnotchi.app "$STAGE/Gnotchi-alt.app"
fi
ditto "$STAGE/Gnotchi.app" /Applications/Gnotchi.app
open /Applications/Gnotchi.app
echo "✓ /Applications/Gnotchi.app ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Gnotchi.app/Contents/Info.plist))"
