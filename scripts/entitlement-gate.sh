#!/usr/bin/env bash
# entitlement-gate.sh — Berechtigungs-Positivliste für ALLEN eingebetteten Code (SECURE-DESIGN G12).
#
# Von release.sh eingelesen (`. scripts/entitlement-gate.sh`). Einzeln als Trockenlauf gegen ein
# fertiges Bundle (prüft nur den eingebetteten Code, nicht die App selbst – ein unsignierter
# `make build` hat dort keine Berechtigungen):
#   bash scripts/entitlement-gate.sh build/Build/Products/Release/Gnotchi.app
#
# Warum rekursiv (Security-Review 18.10., B2): Die alte Schleife sah nur Contents/MacOS/* und die
# oberste Ebene von Contents/Frameworks/*.framework. Sparkles XPC-Dienste (Downloader, Installer),
# Updater.app und Autoupdate liegen tiefer und blieben ungeprüft. Jetzt: jedes Bundle (.app, .xpc,
# .framework, .appex, .bundle, .plugin) und jede lose Mach-O-Datei unter Contents/, ohne Symlinks.

# Geduldet überall: was Xcode beim Export mit Profil selbst einsetzt.
GATE_TOLERATED="com.apple.application-identifier com.apple.developer.team-identifier"

# Erlaubte Berechtigungen je eingebettetem Teil (Pfad relativ zur App). Alles, was hier nicht steht,
# darf KEINE haben (Adapter-Framework und Test-Programm laufen unter /usr/bin/perl).
# Sparkle: gemessen 18.10. an Sparkle 2.10.0, wie es ausgeliefert wird (Release-Build, vor dem
# Signieren): Downloader.xpc, Installer.xpc, Updater.app ohne; Autoupdate nur
# com.apple.application-identifier (ohnehin geduldet). Neue Sparkle-Fassung → neu messen, hier
# eintragen.
gate_allowed_for() {   # $1 = Pfad relativ zur App
    case "$1" in
        Contents/Frameworks/Sparkle.framework) echo "" ;;
        Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle) echo "" ;;
        Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate) echo "" ;;
        Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app*) echo "" ;;
        Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc*) echo "" ;;
        Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc*) echo "" ;;
        *) echo "" ;;
    esac
}

gate_fail() {
    if declare -F fail >/dev/null; then fail "$@"; else echo "✗ $*" >&2; exit 1; fi
}

# Alle Code-Teile unter Contents/ (ohne die App-Programmdatei selbst), sortiert, je Zeile ein Pfad.
gate_nested_code() {   # $1 = App-Pfad
    python3 - "$1" <<'PY'
import os, sys
app = os.path.abspath(sys.argv[1])
main_exe = os.path.join(app, "Contents", "MacOS", os.path.basename(app)[:-4])
bundle_ext = (".app", ".xpc", ".framework", ".appex", ".bundle", ".plugin")
macho = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xfe\xed\xfa\xcf"}
found = []
for root, dirs, files in os.walk(os.path.join(app, "Contents"), followlinks=False):
    for d in list(dirs):
        p = os.path.join(root, d)
        if os.path.islink(p):
            dirs.remove(d)
        elif d.endswith(bundle_ext):
            found.append(p)
    for f in files:
        p = os.path.join(root, f)
        if os.path.islink(p) or p == main_exe:
            continue
        with open(p, "rb") as fh:
            if fh.read(4) in macho:
                found.append(p)
print("\n".join(os.path.relpath(p, app) for p in sorted(found)))
PY
}

gate_entitlement_keys() {   # $1 = Pfad
    codesign -d --entitlements - --xml "$1" 2>/dev/null | python3 -c '
import plistlib, sys
raw = sys.stdin.buffer.read()
print("\n".join(sorted(plistlib.loads(raw).keys())) if raw.strip() else "")
' || gate_fail "Berechtigungen von $1 nicht lesbar"
}

gate_check() {   # $1 = Pfad, $2 = Anzeigename, $3 = erlaubte Schlüssel
    local key keys unexpected=""
    # Erst einlesen, dann prüfen: Ein Fehler in `$(…)` innerhalb von `for` bliebe sonst still.
    keys="$(gate_entitlement_keys "$1")" || gate_fail "Berechtigungen von $2 nicht lesbar"
    for key in ${keys}; do
        case " $3 ${GATE_TOLERATED} " in
            *" ${key} "*) ;;
            *) unexpected="${unexpected} ${key}" ;;
        esac
    done
    [ -z "${unexpected}" ] || gate_fail "Unerwartete Berechtigungen in $2:${unexpected} (SECURE-DESIGN G12)"
}

# Prüft jeden eingebetteten Code-Teil; setzt GATE_COUNT auf die Anzahl.
gate_check_nested() {   # $1 = App-Pfad
    local rel
    GATE_COUNT=0
    while IFS= read -r rel; do
        [ -n "${rel}" ] || continue
        gate_check "$1/${rel}" "${rel}" "$(gate_allowed_for "${rel}")"
        GATE_COUNT=$((GATE_COUNT + 1))
    done < <(gate_nested_code "$1")
    [ "${GATE_COUNT}" -gt 0 ] || gate_fail "Kein eingebetteter Code gefunden – Bundle-Aufbau unerwartet"
}

# Trockenlauf: direkt aufgerufen statt eingelesen.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ -d "${1:-}" ] || { echo "Aufruf: $0 <Pfad/Gnotchi.app>" >&2; exit 2; }
    gate_nested_code "$1" | sed 's/^/  · /'
    gate_check_nested "$1"
    echo "✓ ${GATE_COUNT} eingebettete Code-Teile, keine unerwarteten Berechtigungen"
fi
