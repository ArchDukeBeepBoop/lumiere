#!/bin/bash
# Check, trial and install all three: the server, LumiereControl and Lumiere.
#
#   ./Scripts/ship-all.sh            everything
#   ./Scripts/ship-all.sh --no-open  install, but leave both apps closed
#   ./Scripts/ship-all.sh --force    install even if Lumiere is busy
#   ./Scripts/ship-all.sh --visual   screenshot checks too (opens the demo; private places only)
#
# The order every install has followed by hand, written down once:
#   1. every check green — the app's, the server's, the controller's
#   2. the server's startup and repair passes on a copy of the real library,
#      so a rule that meets the real data badly is caught before it runs on it
#   3. both apps quit — an install over a running app fails half-way
#   4. LumiereControl (which carries the server) first, then Lumiere
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPEN=1
FORCE=0
VISUAL=0
for arg in "$@"; do
    [ "$arg" = "--no-open" ] && OPEN=0
    [ "$arg" = "--force" ] && FORCE=1
    [ "$arg" = "--visual" ] && VISUAL=1
done
DB="$HOME/Library/Application Support/LumiereServer/library.db"

echo "==> Lumiere checks";        (cd "$HERE/mac" && ./Scripts/check.sh > /tmp/ship-app.log 2>&1) \
    || { tail -20 /tmp/ship-app.log; exit 1; }
echo "==> Server tests";          (cd "$HERE/server" && go vet ./... && go test -count=1 ./... > /tmp/ship-server.log 2>&1) \
    || { grep -v "^ok\|no test files" /tmp/ship-server.log | head -20; exit 1; }
echo "==> LumiereControl checks"; (cd "$HERE/control" && ./Scripts/check.sh > /tmp/ship-ctl.log 2>&1) \
    || { tail -20 /tmp/ship-ctl.log; exit 1; }
if [ -f "$DB" ]; then
    echo "==> Trial on a copy of the library"
    (cd "$HERE/server" && LUMIERE_TRIAL_DB="$DB" go test ./internal/trial -count=1 -v 2>&1 \
        | grep -E "→|FAIL|grew|fell|removed" ; exit "${PIPESTATUS[0]}")
fi

# Both apps built now, with the server still up. Building used to happen after
# the server was stopped, which kept the library offline for the six minutes
# the builds take — to the phone and the TV too — and read as a server that
# took six minutes to start. Now the server is down only for the swap.
echo "==> Building both apps (the server keeps running)"
(cd "$HERE/control" && ./Scripts/bundle.sh release > /tmp/ship-ctl-bundle.log 2>&1) \
    || { tail -20 /tmp/ship-ctl-bundle.log; exit 1; }
(cd "$HERE/mac" && ./Scripts/bundle.sh release > /tmp/ship-bundle.log 2>&1) \
    || { tail -20 /tmp/ship-bundle.log; exit 1; }

# Never over something being watched. A busy Lumiere is playing, syncing or
# prefetching; quitting it for an install once stopped a film mid-scene.
if [ "$FORCE" = 0 ] && PID=$(pgrep -x Lumiere); then
    CPU=$(ps -o %cpu= -p "$PID" | tr -d ' ' | cut -d. -f1)
    if [ "${CPU:-0}" -gt 10 ]; then
        echo "==> Holding: Lumiere is busy (${CPU}% CPU — playing or syncing)."
        echo "    Everything is checked; run again when it is idle, or with --force."
        exit 2
    fi
fi

# The screenshot checks, when asked for. They open the app on the demo
# library, so only where the screen may be seen — never by default.
if [ "$VISUAL" = 1 ]; then
    echo "==> Screenshot checks (demo library)"
    (cd "$HERE/mac" && ./Scripts/bundle.sh release > /tmp/ship-bundle.log 2>&1 \
        && ./Scripts/walkthrough.sh 2>&1 | grep -E "✓|✗|●"; exit "${PIPESTATUS[0]}") \
        || { echo "    screenshots changed or came up empty — see build/walkthrough"; exit 1; }
fi

# Whether the server was up, so it is brought back after the install even
# when the apps are left closed — an install should not take the library
# offline for other devices.
SERVER_WAS_UP=0
pgrep -x lumiered > /dev/null && SERVER_WAS_UP=1

echo "==> Quitting both apps"
osascript -e 'quit app "Lumiere"' -e 'quit app "LumiereControl"' 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x Lumiere > /dev/null || pgrep -x lumiered > /dev/null || break
    sleep 1
done
pkill -9 -x Lumiere 2>/dev/null || true
pkill -x lumiered 2>/dev/null || true

echo "==> Installing LumiereControl"; (cd "$HERE/control" && ./Scripts/install.sh --no-build > /tmp/ship-ctl-install.log 2>&1)
echo "==> Installing Lumiere";        (cd "$HERE/mac" && ./Scripts/install.sh --no-build > /tmp/ship-app-install.log 2>&1)

if [ "$OPEN" = 1 ]; then
    open -a LumiereControl
    sleep 5
    open -a Lumiere
elif [ "$SERVER_WAS_UP" = 1 ]; then
    # In the background: LumiereControl carries the server, and -g keeps its
    # window from coming forward.
    open -g -a LumiereControl
fi

# Not shipped until the server answers. A server that installs and then fails
# to start looks exactly like a successful install from here.
if [ "$OPEN" = 1 ] || [ "$SERVER_WAS_UP" = 1 ]; then
    # The loopback address, always. Reading the address from the log found
    # nothing when the log had been rotated since the last start, and under
    # `set -e` that ended this script silently, mid-install. The server always
    # listens on the loopback; the network address is extra.
    ADDR=127.0.0.1:8098
    for _ in $(seq 1 60); do
        curl -sf "http://$ADDR/System/Info/Public" > /dev/null && break
        sleep 1
    done
    if curl -sf "http://$ADDR/System/Info/Public" > /dev/null; then
        echo "==> Server answering at $ADDR"
    else
        echo "==> The server did not answer at $ADDR within a minute — see lumiered.log"
        exit 1
    fi
fi
echo "==> Shipped"
