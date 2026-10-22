#!/usr/bin/env bash
# release.sh — signiertes, notarisiertes Gnotchi-ZIP, GitHub-Release, signierter Appcast.
#
# Übernommen von Seam (2026-10-18), dort von Kalli (scripts/release.sh, seit v0.4.0 erprobt
# und am 2026-09-27 auditiert). Die Kommentare zu den einzelnen Schritten erklären, warum
# jeder Prüfpunkt existiert; die Vorfälle dahinter stammen aus Kalli, Tippi und Seam.
#
# Developer-ID-Signatur ist bei Gnotchi doppelt wichtig: Gnotchi startet den Medien-Adapter
# nur aus einem Bundle mit Michaels Team-Signatur (docs/SECURE-DESIGN.md G2), und die
# Automation-Freigabe für Spotify/Musik hängt an Kennung + Team.
#
# Aufruf:
#   make release                 # bauen, notarisieren, veröffentlichen
#   PUBLISH=0 make release       # alles außer dem GitHub-Release
#
# Voraussetzungen auf dem Mac, der released:
#   - Developer-ID-Zertifikat im Schlüsselbund
#   - notarytool-Profil (gesucht: gnotchi-notary, notary, kalli-notary, tippi-notary)
#   - Sparkle-EdDSA-Schlüssel im Login-Schlüsselbund (derselbe wie Kalli/Tippi)

set -euo pipefail
cd "$(dirname "$0")/.."

APP="Gnotchi"
BUNDLE="${APP}.app"
DIST="dist"
PUBLISH="${PUBLISH:-1}"
# Bevorzugt ein projekteigenes Profil; faellt auf ein vorhandenes zurueck, damit
# dieses oeffentliche Script keinen fremden Projektnamen als Pflichtwert vorgibt.
# Welches genommen wurde, wird gemeldet — ein stiller Rueckfall waere eine
# Ueberraschung beim Debuggen.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# release.env ist optional und enthält keine Geheimnisse — nur den Namen des
# Zertifikats und des Schlüsselbund-Profils. Die Zugangsdaten selbst liegen im
# Schlüsselbund, nicht in einer Datei.
# Wird als Shell-Code eingelesen: dort NUR Variablenzuweisungen (DEVELOPER_ID,
# NOTARY_PROFILE). Gitignoriert, rein lokal (Rafter-Fund F4).
[ -f release.env ] && . ./release.env

fail() { echo "✗ $*" >&2; exit 1; }
step() { echo ""; echo "▶ $*"; }

# Nur 0 oder 1. `[ "$PUBLISH" -eq 0 ]` war bei "no", "false" oder "0 " ein
# Vergleichsfehler — und damit FALSCH, also wurde veröffentlicht (Audit-Fund
# K-S2, 2026-09-27). Früh prüfen (nach release.env, das PUBLISH setzen könnte),
# nicht erst nach Build und Notarisierung.
case "${PUBLISH}" in
    0|1) ;;
    *) fail "PUBLISH muss 0 oder 1 sein, ist aber '${PUBLISH}'" ;;
esac

# ---------------------------------------------------------------------------
# 0. Vorbedingungen. Alle messen, keine annehmen.
# ---------------------------------------------------------------------------
step "[0/10] Vorbedingungen"

command -v gh >/dev/null || fail "gh fehlt — brew install gh"
command -v xcodegen >/dev/null || fail "xcodegen fehlt — brew install xcodegen"

# Ein Release aus einem verschmutzten Baum ist nicht reproduzierbar: Das
# Artefakt enthält Änderungen, die in keinem Commit stehen.
# `git status --porcelain` statt `git diff`: Auch UNGETRACKTE Dateien landen
# im Build (xcodegen nimmt jede .swift unter Gnotchi/ auf) — `git diff` sah sie
# nicht (Audit-Fund K-S3, 2026-09-27). Ignorierte Dateien (build/, dist/,
# release.env) zeigt porcelain nicht an; die sind in Ordnung.
[ -z "$(git status --porcelain)" ] \
    || fail "Arbeitsbaum ist nicht sauber (auch ungetrackte Dateien zählen). Erst committen, dann releasen."

# Der Feed (SUFeedURL) liest main. Ein Release von einem anderen Zweig oder einem
# ungepushten Stand fände die App nie (Rafter-Fund F1, 2026-10-08).
#
# HOTFIX=1 (0.2.1, 21.10.): Release von einem gepushten Zweig `release/*`, wenn main schon
# unveröffentlichte Funktionen trägt. Der Appcast wird dann NICHT committet, sondern bleibt als
# Datei liegen → von Hand auf main übernehmen (Ablauf: Release-Profil gnotchi.md, Abschnitt Hotfix).
BRANCH="$(git branch --show-current)"
git remote get-url origin >/dev/null 2>&1 || fail "Kein Remote 'origin'"
if [ "${HOTFIX:-0}" = "1" ]; then
    case "${BRANCH}" in release/*) ;; *) fail "HOTFIX=1 nur auf einem Zweig release/* (jetzt: ${BRANCH})";; esac
    git fetch -q origin "${BRANCH}" || fail "git fetch origin ${BRANCH} fehlgeschlagen — Zweig gepusht?"
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/${BRANCH}")" ] \
        || fail "HEAD ist nicht gleich origin/${BRANCH}. Erst pushen, dann releasen."
else
    [ "${BRANCH}" = "main" ] || fail "Nicht auf main — der Update-Feed liest main"
    git fetch -q origin main || fail "git fetch origin main fehlgeschlagen"
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
        || fail "HEAD ist nicht gleich origin/main. Erst pushen, dann releasen."
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
[ -n "${VERSION}" ] || fail "MARKETING_VERSION nicht in project.yml gefunden"
TAG="v${VERSION}"

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
    && fail "Tag ${TAG} existiert schon. Version in project.yml anheben."

grep -q "\[${VERSION}\]" CHANGELOG.md \
    || fail "CHANGELOG hat keinen Abschnitt [${VERSION}]"

# Das Zertifikat wird GEPRÜFT, nicht vorausgesetzt. Ohne diese Zeile fällt der
# Fehler erst nach dem Archivieren auf — oder gar nicht, weil xcodebuild
# stillschweigend ad-hoc signiert und das Ergebnis erst auf dem anderen Mac
# scheitert.
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
[ -n "${DEVELOPER_ID}" ] || fail "Kein 'Developer ID Application'-Zertifikat im Schlüsselbund"

if [ -n "${NOTARY_PROFILE}" ]; then
    xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
        || fail "notarytool-Profil '${NOTARY_PROFILE}' antwortet nicht. Anlegen: xcrun notarytool store-credentials"
else
    for candidate in gnotchi-notary notary kalli-notary tippi-notary; do
        if xcrun notarytool history --keychain-profile "${candidate}" >/dev/null 2>&1; then
            NOTARY_PROFILE="${candidate}"
            break
        fi
    done
    [ -n "${NOTARY_PROFILE}" ] || fail "Kein notarytool-Profil gefunden (gesucht: gnotchi-notary, notary, kalli-notary, tippi-notary). Anlegen: xcrun notarytool store-credentials, oder NOTARY_PROFILE=... setzen"
fi

echo "  ✓ Version ${VERSION} · Tag ${TAG} frei · Baum sauber"
echo "  ✓ Zertifikat: ${DEVELOPER_ID}"
echo "  ✓ notarytool-Profil: ${NOTARY_PROFILE}"

# ---------------------------------------------------------------------------
# 1. Doku-Gate — derselbe Prüfer wie bei `make install`
# ---------------------------------------------------------------------------
step "[1/10] Doku-Gate und Datenschutz-Gate"
bash scripts/docs-gate.sh
# Keine echten Hördaten im ausgelieferten Stand (G16). `make release` prüft das schon über
# `make lint`, aber dieses Skript lässt sich auch direkt aufrufen.
sh scripts/privacy-gate.sh || fail "Datenschutz-Gate nicht bestanden (siehe oben)"

# ---------------------------------------------------------------------------
# 2. Tests
# ---------------------------------------------------------------------------
# Ein Release, das die Tests nicht laeuft, ist ein Release ohne Abnahme. Sie
# brauchen unter einer Sekunde — es gibt keinen Grund, sie zu ueberspringen.
step "[2/10] Tests"
# Signiert wie das Release: Ein ad-hoc signierter Test-Host waere eine zweite
# TCC-Identitaet fuer dev.mwlr.gnotchi. Siehe Makefile-Kommentar am test-Ziel.
make gen >/dev/null   # Projekt + Package.resolved VOR den Tests (Rafter-Fund F2)
xcodebuild -project "${APP}.xcodeproj" -scheme "${APP}" \
    -destination 'platform=macOS' \
    -derivedDataPath ./build \
    -onlyUsePackageVersionsFromResolvedFile \
    -allowProvisioningUpdates \
    test >/dev/null 2>&1 \
    || fail "Tests fehlgeschlagen. Ursache mit 'make test' ansehen."
echo "  ✓ alle Tests bestanden"

# ---------------------------------------------------------------------------
# 3. Bauen: archive + exportArchive, NICHT `build`
# ---------------------------------------------------------------------------
# Lehre aus Tippi v2.3.0: Manuelles Signieren ohne Profil-Angabe bettet gar
# kein Provisioning-Profil ein. Das bleibt unsichtbar, solange die App keine
# Entitlements hat — sobald doch, killt amfid sie beim Start mit -413 "No
# matching profile found". Der Export-Pfad lässt Xcode das
# "Mac Team Direct"-Profil holen, das auf jedem Mac gilt statt nur auf
# registrierten.
#
# Gnotchi trägt genau eine Berechtigung (Apple Events, G12) und keine Sandbox.
# Der Export-Pfad ist trotzdem der richtige Weg: er trägt, sobald jemand eine
# profilpflichtige Berechtigung ergänzt.
BUILD_NUMBER="$(git rev-list --count HEAD)"
step "[3/10] Release-Build, Hardened Runtime (Build ${BUILD_NUMBER})"

for old in build/Gnotchi.xcarchive build/export "${DIST}"; do [ -e "$old" ] && mv "$old" "$(mktemp -d /tmp/gnotchi-old.XXXXXX)/"; done
mkdir -p "${DIST}"
make gen >/dev/null   # docs + xcodegen + Package.resolved (Sparkle auf Commit-SHA)

xcodebuild \
    -project "${APP}.xcodeproj" \
    -scheme "${APP}" \
    -configuration Release \
    -derivedDataPath ./build \
    -archivePath "./build/${APP}.xcarchive" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    -onlyUsePackageVersionsFromResolvedFile \
    -allowProvisioningUpdates \
    archive >/dev/null

# Hat Xcode beim Bauen still neu aufgelöst? Dann weicht die Datei im Projekt ab.
cmp -s Package.resolved "${APP}.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \
    || fail "Package.resolved wurde beim Bauen verändert — Sparkle ist nicht die festgelegte Fassung"

xcodebuild -exportArchive \
    -archivePath "./build/${APP}.xcarchive" \
    -exportPath ./build/export \
    -exportOptionsPlist scripts/exportOptions-developer-id.plist \
    -allowProvisioningUpdates >/dev/null

APP_PATH="build/export/${BUNDLE}"
[ -d "${APP_PATH}" ] || fail "Export hat kein ${BUNDLE} erzeugt"

# ---------------------------------------------------------------------------
# 3. Signatur prüfen — messen, nicht glauben
# ---------------------------------------------------------------------------
step "[4/10] Signatur prüfen"
SIGN_INFO="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1)"
echo "${SIGN_INFO}" | grep -q "Authority=Developer ID Application" \
    || fail "Nicht mit Developer ID signiert. Ein ad-hoc signiertes Release würde auf dem anderen Mac scheitern."
echo "${SIGN_INFO}" | grep -q "flags=.*runtime" \
    || fail "Hardened Runtime fehlt — Apple würde die Notarisierung ablehnen"
echo "${SIGN_INFO}" | grep -q "TeamIdentifier=LTKJ6Z2VYB" \
    || fail "Falsches Team in der Signatur (erwartet LTKJ6Z2VYB)"
# G12 maschinell (Seam-Muster E8, Code-Audit 09.10., S3): Positivliste statt „leer“.
# - App: GENAU com.apple.security.automation.apple-events (AppleScript-Rückfall, G7) und
#   com.apple.security.device.camera (Spiegel, ab 0.5.0, G27).
# - JEDER eingebettete Code-Teil, rekursiv (Sparkles XPC-Dienste, Updater.app, Autoupdate,
#   Adapter-Framework, Test-Programm …): nur, was scripts/entitlement-gate.sh für ihn erlaubt –
#   für alle derzeit nichts (Security-Review 18.10., B2: vorher nur die oberste Ebene geprüft).
# - Überall geduldet: was Xcode beim Export mit Profil selbst einsetzt
#   (com.apple.application-identifier, com.apple.developer.team-identifier). Alles andere,
#   auch get-task-allow oder eine Hardened-Runtime-Ausnahme wie disable-library-validation,
#   bricht das Release ab.
# Geparst mit Python/plistlib statt grep (ugrep-Lehre, siehe Appcast-Prüfung unten).
. scripts/entitlement-gate.sh
gate_check "${APP_PATH}" "${BUNDLE}" "com.apple.security.automation.apple-events com.apple.security.device.camera"
gate_entitlement_keys "${APP_PATH}" | grep -qx "com.apple.security.automation.apple-events" \
    || fail "Apple-Events-Berechtigung fehlt in der App — der Spotify/Musik-Rückfall (G7) ginge nicht"
gate_entitlement_keys "${APP_PATH}" | grep -qx "com.apple.security.device.camera" \
    || fail "Kamera-Berechtigung fehlt in der App — der Spiegel (G27) zeigte unter der Hardened Runtime kein Bild"
gate_check_nested "${APP_PATH}"
NESTED="${GATE_COUNT}"
[ -d "${APP_PATH}/Contents/Frameworks/MediaRemoteAdapter.framework" ] \
    || fail "MediaRemoteAdapter.framework fehlt im Bundle"
[ -x "${APP_PATH}/Contents/MacOS/MediaRemoteAdapterTestClient" ] \
    || fail "MediaRemoteAdapterTestClient fehlt im Bundle"
# 0.6.0 (G28): Hilfsprogramm für Mitteilungen – da, eigene Kennung, gültig mit Developer ID signiert (Gnotchi startet
# es nur nach dieser Prüfung). Berechtigungen prüft gate_check_nested oben (keine erlaubt).
HELPER_APP="${APP_PATH}/Contents/Library/LoginItems/Gnotchi Mitteilungen.app"
[ -d "${HELPER_APP}" ] || fail "Gnotchi Mitteilungen.app fehlt im Bundle"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${HELPER_APP}/Contents/Info.plist")" = "dev.mwlr.gnotchi.mitteilungen" ] \
    || fail "Hilfsprogramm hat die falsche Kennung"
codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "LTKJ6Z2VYB" and identifier "dev.mwlr.gnotchi.mitteilungen"' "${HELPER_APP}" \
    || fail "Hilfsprogramm nicht gültig mit Developer ID signiert"
echo "  ✓ Developer ID (Team LTKJ6Z2VYB) + Hardened Runtime"
echo "  ✓ Berechtigungen: App nur Apple Events, ${NESTED} eingebettete Teile ohne"

# ---------------------------------------------------------------------------
# 4. Notarisieren
# ---------------------------------------------------------------------------
# Notarisiert wird ein ZIP, geheftet wird an die .app: Ein Ticket lässt sich
# nicht an ein ZIP heften. Deshalb zweimal packen — einmal zum Einreichen,
# einmal danach mit Ticket.
step "[5/10] Bei Apple einreichen (dauert meist 1–3 Minuten)"
ditto -c -k --keepParent "${APP_PATH}" "${DIST}/notarize.zip"

xcrun notarytool submit "${DIST}/notarize.zip" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${DIST}/notarization.json"

STATUS="$(/usr/bin/plutil -extract status raw -o - "${DIST}/notarization.json")"
if [ "${STATUS}" != "Accepted" ]; then
    cat "${DIST}/notarization.json"
    fail "Notarisierung: ${STATUS}"
fi
echo "  ✓ Notarisierung angenommen"

# ---------------------------------------------------------------------------
# 5. Ticket anheften und unabhängig gegenprüfen
# ---------------------------------------------------------------------------
step "[6/10] Ticket anheften"
xcrun stapler staple "${APP_PATH}" >/dev/null
xcrun stapler validate "${APP_PATH}" >/dev/null || fail "Ticket ist nicht angeheftet"

# spctl urteilt so, wie Gatekeeper es auf dem anderen Mac tun wird. Das ist die
# eigentliche Prüfung — alles davor ist die eigene Behauptung.
SPCTL="$(spctl --assess --type execute -vv "${APP_PATH}" 2>&1 || true)"
echo "${SPCTL}" | grep -q "accepted" \
    || { echo "${SPCTL}"; fail "Gatekeeper lehnt die App ab"; }
echo "  ✓ Gatekeeper akzeptiert (source: $(echo "${SPCTL}" | awk -F'=' '/source/ { print $2 }'))"

# ---------------------------------------------------------------------------
# 6. Endgültiges ZIP
# ---------------------------------------------------------------------------
step "[7/10] ZIP packen und ALS AUSGELIEFERTES ARTEFAKT pruefen"
ZIP="${DIST}/${APP}-${VERSION}.zip"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP}"
rm -f "${DIST}/notarize.zip"
echo "  ✓ ${ZIP} ($(du -h "${ZIP}" | cut -f1))"

# Der Schritt davor prueft den Build VOR dem Packen — das ist die eigene
# Behauptung. Was zaehlt, ist das ZIP, das der andere Mac laedt: auspacken und
# Gatekeeper noch einmal fragen.
#
# Warum das hier steht (2026-09-22): Der erste Lauf meldete "Gatekeeper
# akzeptiert" und das heruntergeladene Bundle wurde trotzdem abgelehnt —
# "a sealed resource is missing or invalid". Ursache war nicht das Artefakt,
# sondern die Entpack-Methode in der Anleitung (`unzip` statt `ditto`).
# Ein Gate, das eine Stufe vor der Auslieferung prueft, findet das nie.
VERIFY_DIR="$(mktemp -d)"
ditto -x -k "${ZIP}" "${VERIFY_DIR}/"
[ -d "${VERIFY_DIR}/${BUNDLE}" ] || fail "Das ZIP enthaelt kein ${BUNDLE}"
xcrun stapler validate "${VERIFY_DIR}/${BUNDLE}" >/dev/null \
    || fail "Im ausgelieferten ZIP ist kein Notarisierungs-Ticket angeheftet"
SHIPPED="$(spctl --assess --type execute -vv "${VERIFY_DIR}/${BUNDLE}" 2>&1 || true)"
echo "${SHIPPED}" | grep -q "accepted" \
    || { echo "${SHIPPED}"; fail "Gatekeeper lehnt das ausgelieferte ZIP ab"; }
rm -rf "${VERIFY_DIR}"
echo "  ✓ Ausgeliefertes ZIP: $(echo "${SHIPPED}" | awk -F'=' '/source/ { print $2 }')"

if [ "${PUBLISH}" = "0" ]; then
    echo ""
    echo "🛑 PUBLISH=0 — kein GitHub-Release. Artefakt liegt in ${ZIP}"
    exit 0
fi

# ---------------------------------------------------------------------------
# 7. GitHub-Release
# ---------------------------------------------------------------------------
step "[8/10] GitHub-Release ${TAG}"
# Release-Notizen aus dem CHANGELOG-Abschnitt dieser Version — eine Quelle,
# nicht zwei, die auseinanderlaufen.
awk -v v="[${VERSION}]" '
    $0 ~ "^## \\" v { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
' CHANGELOG.md > "${DIST}/notes.md"
[ -s "${DIST}/notes.md" ] || fail "Keine Release-Notizen für ${VERSION} aus dem CHANGELOG gelesen"

git tag -a "${TAG}" -m "${APP} ${VERSION}"
git push origin "${TAG}"
gh release create "${TAG}" "${ZIP}" \
    --title "${APP} ${VERSION}" \
    --notes-file "${DIST}/notes.md"

# ---------------------------------------------------------------------------
# 8. Am Remote gegenprüfen, nicht lokal
# ---------------------------------------------------------------------------
# Ein lokal erfolgreicher Ablauf sagt nichts darüber, was tatsächlich
# veröffentlicht ist. Gefragt wird deshalb GitHub.
step "[9/10] Veröffentlichung am Remote prüfen"
ASSET="$(gh release view "${TAG}" --json assets --jq '.assets[].name' 2>/dev/null || true)"
[ -n "${ASSET}" ] || fail "Release ${TAG} hat auf GitHub kein Asset"
echo "  ✓ ${TAG} veröffentlicht, Asset: ${ASSET}"

# ---------------------------------------------------------------------------
# 10. Appcast erzeugen, signieren, GEGENLESEN, veröffentlichen
# ---------------------------------------------------------------------------
# Die Werkzeuge kommen aus der FESTGELEGTEN Sparkle-Version, die auch in der App
# steckt — nicht aus einem handplatzierten Ordner unbekannter Herkunft.
#
# Und es gibt hier kein `2>/dev/null`: Ein Appcast, der still nicht signiert
# wurde, heißt entweder "niemand kann updaten" oder — schlimmer — "etwas geht
# ungeprüft durch". Beides muss laut scheitern.
step "[10/10] Appcast erzeugen und signieren"

SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "${SPARKLE_BIN}/generate_appcast" ] \
    || fail "generate_appcast fehlt unter ${SPARKLE_BIN} — wurde das Paket aufgelöst? (make build)"

# Nur das aktuelle Archiv liegt in dist/; der Appcast enthält damit einen
# Eintrag. Sparkle braucht nur den neuesten. generate_appcast liest eine vorhandene
# appcast.xml ein und behält deren Einträge (v0.2.0, 20.10.: Prüfung unten fand 0.1.0
# daneben) – darum frisch erzeugen. Die alten Fassungen stehen in der Git-Geschichte.
rm -f appcast.xml
"${SPARKLE_BIN}/generate_appcast" "${DIST}" \
    --download-url-prefix "https://github.com/miwixyz/Gnotchi/releases/download/${TAG}/" \
    --link "https://github.com/miwixyz/Gnotchi" \
    -o appcast.xml \
    || fail "generate_appcast fehlgeschlagen"

# Nachlesen statt glauben. Geparst wird mit Python, nicht mit grep: Auf diesem
# Mac ist `grep` auf ugrep gemappt, dessen Regex-Verhalten abweicht — eine
# stille Fehlextraktion waere hier besonders teuer.
python3 - "$VERSION" "$TAG" <<'PY' || fail "Appcast-Pruefung fehlgeschlagen"
import re, sys
version, tag = sys.argv[1], sys.argv[2]
xml = open("appcast.xml", encoding="utf-8").read()
m = re.search(r'sparkle:edSignature="([^"]+)"', xml)
if not m:                      sys.exit("Der Appcast traegt keine EdDSA-Signatur")
# Genau vergleichen, nicht als Teilstring (Security-Review 18.10., B12): „0.1.1“ enthielte „0.1.1“ auch
# in „10.1.10“. Sparkle 2 schreibt ein Element, ältere Fassungen ein Attribut – beides lesen.
shorts = [a or b for a, b in re.findall(
    r'<sparkle:shortVersionString>\s*([^<]*?)\s*</sparkle:shortVersionString>|sparkle:shortVersionString="([^"]*)"', xml)]
if not shorts:                 sys.exit("Der Appcast nennt keine sparkle:shortVersionString")
if any(s != version for s in shorts):
                               sys.exit(f"Der Appcast nennt {shorts}, erwartet genau {version}")
if f"releases/download/{tag}/" not in xml:
                               sys.exit(f"Die Download-URL zeigt nicht auf {tag}")
open(".appcast-sig", "w").write(m.group(1))
PY

# KRYPTOGRAFISCHE Gegenpruefung: Passt die Signatur im Appcast zum ARCHIV, das
# ausgeliefert wird? Das ist die Frage, auf die es ankommt.
#
# (Kalli-Lehre 2026-09-22: `sign_update --verify appcast.xml` prueft etwas ANDERES, naemlich
# die Feed-Signatur. Die verlangt Gnotchi von Anfang an zusaetzlich, Pruefung direkt danach.)
APPCAST_SIG="$(cat .appcast-sig)"
rm -f .appcast-sig
"${SPARKLE_BIN}/sign_update" --verify "${ZIP}" "${APPCAST_SIG}" \
    || fail "Die Signatur im Appcast passt NICHT zum ausgelieferten Archiv"
echo "  ✓ Appcast-Signatur gegen das ausgelieferte Archiv verifiziert"

# Feed-Signatur (Code-Audit 09.10., S1): Die App verlangt sie (SURequireSignedFeed). Fehlt sie,
# nähme Gnotchi KEIN Update an. Darum hart prüfen, bevor der Appcast veröffentlicht wird.
"${SPARKLE_BIN}/sign_update" --verify appcast.xml \
    || fail "Der Appcast trägt keine gültige Feed-Signatur, Gnotchi würde ihn ablehnen"
echo "  ✓ Feed-Signatur des Appcasts verifiziert"

# Der Appcast liegt IM REPO, nicht in einem Gist: Jede Änderung daran ist damit
# ein öffentlicher, datierter Commit. Billigste Manipulationserkennung, die zu
# haben ist.
if [ "${HOTFIX:-0}" = "1" ]; then
    cp appcast.xml "${TMPDIR:-/tmp}/gnotchi-appcast-${TAG}.xml"
    git checkout -- appcast.xml
    echo "  ⏸️  HOTFIX: Appcast NICHT committet. Signiert und geprüft liegt er unter"
    echo "     ${TMPDIR:-/tmp}/gnotchi-appcast-${TAG}.xml"
    echo "     → ZU TUN: git switch main && cp <Datei> appcast.xml && git commit -m 'Appcast für ${TAG}' && git push"
    exit 0
fi
git add appcast.xml
if git diff --cached --quiet -- appcast.xml; then
    echo "  ℹ️  Appcast unverändert — kein Commit nötig"
else
    git commit -q -m "Appcast für ${TAG}"
    git push -q origin main
    echo "  ✓ appcast.xml committet und gepusht"
fi

# Zum Schluss: Sieht der Feed unter der URL so aus, wie die App ihn erwartet?
# raw.githubusercontent.com cacht kurz — ein Fehlschlag hier ist kein Abbruch,
# aber er wird gesagt statt verschwiegen.
FEED="https://raw.githubusercontent.com/miwixyz/Gnotchi/main/appcast.xml"
# Erst in eine Datei laden, dann als DATEN parsen – keine Pipe von curl in einen Interpreter
# (Rafter R-33E2F, 18.10.: dort ein Fehlalarm, der Feed wurde nie ausgeführt; so ist es auch
# für den Leser eindeutig).
FEED_TMP="$(mktemp "${TMPDIR:-/tmp}/gnotchi-feed.XXXXXX")"
if curl -fsS --netrc-file /dev/null -o "${FEED_TMP}" "${FEED}" 2>/dev/null && python3 -c '
import re, sys
xml = open(sys.argv[2], encoding="utf-8").read()
shorts = [a or b for a, b in re.findall(
    r"<sparkle:shortVersionString>\s*([^<]*?)\s*</sparkle:shortVersionString>|sparkle:shortVersionString=\"([^\"]*)\"", xml)]
sys.exit(0 if sys.argv[1] in shorts else 1)
' "${VERSION}" "${FEED_TMP}"; then
    echo "  ✓ Feed unter ${FEED} nennt ${VERSION}"
else
    echo "  ⚠️  Feed nennt ${VERSION} noch nicht — raw.githubusercontent cacht bis zu 5 Min."
    echo "     → ZU TUN: in ein paar Minuten prüfen: curl -s ${FEED} | grep ${VERSION}"
fi
rm -f "${FEED_TMP}"

echo ""
echo "✅ ${APP} ${VERSION} released."
echo ""
echo "→ ZU TUN auf dem anderen Mac:"
echo "     gh release download --repo miwixyz/Gnotchi --pattern '*.zip'   # ohne Tag = neuestes"
echo "     ditto -x -k ${APP}-${VERSION}.zip . && mv ${BUNDLE} /Applications/ && open /Applications/${BUNDLE}"
echo ""
echo "   WICHTIG: ditto, nicht unzip. unzip zerstoert die Bundle-Metadaten"
echo "   eines signierten .app — Gatekeeper meldet dann 'a sealed resource is"
echo "   missing or invalid' und die App sieht beschaedigt aus."
echo ""
echo "   Kein Xcode nötig. Gnotchi selbst braucht keine Bedienungshilfen-Freigabe; nur wer die"
echo "   Mitteilungen einschaltet, erteilt sie dem Hilfsprogramm „Gnotchi Mitteilungen“."
echo "   macOS fragt sonst höchstens nach Automation für Spotify/Musik und beim Spiegel nach der Kamera."
