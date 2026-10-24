#!/bin/sh
# profile.sh — Provisioning-Profil und ausgeschriebene Berechtigungen für das Signieren von Hand
# (dev-signed.sh, install-signed.sh). Wird eingelesen: `. scripts/profile.sh`.
#
# Warum (0.11.0, G38): Die Schlüsselbund-Gruppe `keychain-access-groups` ist eine Berechtigung, die nur
# ein eingebettetes Provisioning-Profil freigibt (Apple TN3137). Fehlt das Profil, beendet macOS die App
# beim Start (amfid -413, Lehre Tippi v2.3.0). Der Release-Weg (archive + exportArchive) bettet es selbst
# ein; beim Signieren von Hand müssen wir das tun – und `$(AppIdentifierPrefix)` selbst ausschreiben,
# weil nur Xcode solche Variablen ersetzt.
#
# Das Profil („Mac Team Direct Provisioning Profile: dev.mwlr.gnotchi“, Developer ID) legt Xcode beim
# Export an. Einmal je Mac: `make profile`.

GNOTCHI_TEAM="LTKJ6Z2VYB"
GNOTCHI_APP_ID="${GNOTCHI_TEAM}.dev.mwlr.gnotchi"

# Gibt den Pfad des neuesten gültigen Developer-ID-Profils für Gnotchi aus, sonst Abbruch mit Anleitung.
gnotchi_profile_path() {
    python3 -I - "$GNOTCHI_APP_ID" <<'PY'
import glob, os, plistlib, subprocess, sys, datetime
want = sys.argv[1]
best = None
dirs = [os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
        os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")]
for d in dirs:
    for f in glob.glob(os.path.join(d, "*.provisionprofile")):
        try:
            raw = subprocess.run(["security", "cms", "-D", "-i", f], capture_output=True, check=True).stdout
            p = plistlib.loads(raw)
        except Exception:
            continue
        ent = p.get("Entitlements", {})
        if ent.get("com.apple.application-identifier") != want:
            continue
        if "ProvisionedDevices" in p:          # Entwicklungsprofil (nur registrierte Macs) – nicht für Developer ID
            continue
        exp = p.get("ExpirationDate")
        if exp is None or exp <= datetime.datetime.now():
            continue
        if best is None or exp > best[0]:
            best = (exp, f)
if best is None:
    sys.exit(1)
print(best[1])
PY
}

# Schreibt nach $2 die Berechtigungen aus $1 mit ausgeschriebener App-Kennung, dazu die Schlüssel, die
# Xcode beim Signieren mit Profil selbst einsetzt (application-identifier, team-identifier).
gnotchi_expanded_entitlements() {   # $1 = Quelle, $2 = Ziel
    sed "s/\$(AppIdentifierPrefix)/${GNOTCHI_TEAM}./g" "$1" > "$2"
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${GNOTCHI_APP_ID}" "$2" >/dev/null
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${GNOTCHI_TEAM}" "$2" >/dev/null
    plutil -lint "$2" >/dev/null || { echo "✗ Berechtigungen ungültig: $2" >&2; return 1; }
    if grep -q 'AppIdentifierPrefix' "$2"; then echo "✗ Variable nicht ersetzt in $2" >&2; return 1; fi
}

# Bettet das Profil in die App ein; Abbruch mit Anleitung, wenn keines da ist.
gnotchi_embed_profile() {   # $1 = App-Pfad
    profile=$(gnotchi_profile_path) || {
        echo "✗ Kein Developer-ID-Profil für ${GNOTCHI_APP_ID}. Einmal je Mac: make profile" >&2
        return 1
    }
    cp "$profile" "$1/Contents/embedded.provisionprofile"
}
