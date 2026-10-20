#!/bin/sh
# stop-selftest.sh — Sichttest-Werkzeug (0.1.1): hält den NÄCHSTEN Medien-Adapter-Selbsttest
# (`perl …/mediaremote-adapter.pl … test`) einer Testkopie mit SIGSTOP an. Gnotchi läuft dann
# ins 10-s-Zeitlimit, ohne dass der App-Code für den Test verändert wird (Diagnose darf die
# Messung nicht verändern). Wirkt nur auf Kopien unter /tmp/gnotchi-test.*, nie auf /Applications.
#
# Aufruf:  sh tools/stop-selftest.sh [max_sekunden=60] &   danach  make dev
# Ausgabe: PID des angehaltenen Prozesses (keine Titel, keine App-Namen).
set -eu
max=${1:-60}
pattern='^/usr/bin/perl (/private)?/tmp/gnotchi-test\.[^/]+/Gnotchi\.app/.*mediaremote-adapter\.pl .* test$'
end=$(( $(date +%s) + max ))
while [ "$(date +%s)" -lt "$end" ]; do
    pid=$(pgrep -f "$pattern" | head -1 || true)
    if [ -n "$pid" ]; then
        kill -STOP "$pid"
        echo "angehalten: pid $pid ($(date +%H:%M:%S))"
        exit 0
    fi
done
echo "kein Selbsttest gesehen in ${max}s" >&2
exit 1
