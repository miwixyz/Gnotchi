#!/bin/sh
# Bild-Testkopie (G45): Debug-Build mit EIGENER Kennung dev.mwlr.gnotchi.bild, eigenem Datenordner
# („Gnotchi Bild“) und Befehlskanal, dazu das signierte Steuerprogramm build-dev/gnotchictl.
#
# Warum eigene Kennung: Die Bildschirmaufnahme-Freigabe hängt an Kennung + Signatur. Mit der echten Kennung
# hätte auch das veröffentlichte Gnotchi die Freigabe. Das echte Gnotchi läuft währenddessen einfach weiter.
#
#   sh scripts/bild-test.sh            → bauen, signieren, starten
#   build-dev/gnotchictl status        → Zustand
#   build-dev/gnotchictl snapshot einstellungen
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
BUNDLE_ID="dev.mwlr.gnotchi.bild"

mkdir -p build-dev
LOG=$(mktemp "build-dev/bild-build.XXXXXX")
if ! make build DERIVED=build-dev >"$LOG" 2>&1; then
    grep -E 'error:' "$LOG" | sort -u | head -8
    echo "✗ Build fehlgeschlagen — Log: $LOG" >&2
    exit 1
fi
SRC="build-dev/Build/Products/Debug/Gnotchi.app"
DEST_DIR=$(mktemp -d /tmp/gnotchi-bild.XXXXXX)
APP="$DEST_DIR/Gnotchi Bild.app"
ditto "$SRC" "$APP"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Gnotchi Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Gnotchi Bild" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$PLIST"

IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || { echo "✗ Kein Developer-ID-Zertifikat im Schlüsselbund" >&2; exit 1; }

# Eingebettete Teile wie in dev-signed.sh, ohne eigene Berechtigungen.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in "$SPK"/XPCServices/*.xpc "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --preserve-metadata=entitlements --sign "$IDENTITY" "$part"
done
for part in "$APP/Contents/MacOS/MediaRemoteAdapterTestClient" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" \
            "$APP"/Contents/MacOS/*.dylib; do
    [ -e "$part" ] || continue
    codesign --force --options runtime --sign "$IDENTITY" "$part"
done
for helper in "$APP/Contents/Library/LoginItems/Gnotchi Mitteilungen.app" "$APP/Contents/Helpers/Gnotchi Claude.app"; do
    [ -d "$helper" ] || continue
    for part in "$helper"/Contents/MacOS/*.dylib; do
        [ -e "$part" ] || continue
        codesign --force --options runtime --sign "$IDENTITY" "$part"
    done
    codesign --force --options runtime --sign "$IDENTITY" "$helper"
done

# App: KEINE Berechtigungen (G45). Fensterbilder brauchen weder Apple Events noch Kamera, und die Schlüsselbund-Gruppe
# gehört dev.mwlr.gnotchi (bräuchte dessen Profil). Folge: Musik-Rückfall, Spiegel und verschlüsselter
# Zwischenablage-Verlauf gehen in der Kopie nicht – gewollt, sie soll nichts steuern und keine echten Daten haben.
ENT="$DEST_DIR/GnotchiBild.entitlements"
cat > "$ENT" <<'PLISTEND'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLISTEND
codesign --force --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# Steuerprogramm: nur mit dieser Kennung + Developer ID nimmt die Kopie Befehle an.
swiftc -O tools/gnotchictl.swift -o build-dev/gnotchictl
codesign --force --options runtime -i dev.mwlr.gnotchi.ctl --sign "$IDENTITY" build-dev/gnotchictl

# Fester Ort ~/Applications statt /tmp (gemessen 28.10.): Apps unter /tmp findet macOS nicht über ihre Kennung –
# die Systemeinstellungen nahmen „Gnotchi Bild“ auf, zeigten es aber nie an („Failed to find application for
# bundle_id“). Gleiche Kennung + gleiche Signatur am selben Ort → die Freigabe bleibt über Neubauten erhalten.
INSTALLED="$HOME/Applications/Gnotchi Bild.app"
# Alte Bild-Kopie beenden (nur sie – nach Kennung, nie nach Prozessname: das echte Gnotchi heißt genauso).
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
i=0
while pgrep -f "Gnotchi Bild.app/Contents/MacOS/Gnotchi$" >/dev/null && [ "$i" -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
mkdir -p "$HOME/Applications"
[ -d "$INSTALLED" ] && mv "$INSTALLED" "$DEST_DIR/alt.app"
ditto "$APP" "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED"
open "$INSTALLED"
echo "✓ Bild-Testkopie gestartet: $INSTALLED"
echo "  Erster Lauf auf einem Mac: Systemeinstellungen → Datenschutz & Sicherheit → Aufnahme von Bildschirm &"
echo "  Systemaudio → „Gnotchi Bild“ einschalten (nicht „Gnotchi“), dann dieses Skript erneut starten."
echo "  Steuern: build-dev/gnotchictl status | snapshot einstellungen|hilfe | appearance light|dark|system"
