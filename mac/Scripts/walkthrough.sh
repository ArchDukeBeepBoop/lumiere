#!/bin/bash
# Screenshots of the views most changes touch, against the demo library, in
# the looks that matter. Never the real library: demo mode only.
#
#   ./Scripts/walkthrough.sh            shots in build/walkthrough, compared
#                                       against Tests/Baselines
#   ./Scripts/walkthrough.sh --record   make the current shots the baselines,
#                                       after a change that was meant to show
#
# Each shot is Lumiere's own window, captured by id, so nothing else on the
# screen is ever in it. A view that draws nothing fails the run — see
# Tools/window-shot.swift for why that check exists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/walkthrough"
BASE="$ROOT/Tests/Baselines"
RECORD=0
[ "${1:-}" = "--record" ] && RECORD=1
DIFF="$ROOT/build/image-diff"
APP="$ROOT/build/Lumiere.app/Contents/MacOS/Lumiere"
# Built first, always. It used whatever bundle was lying in build/ — the last
# install's — so a fix made since then was never in the pictures, and a run
# after one "failed" on the very thing that had been fixed.
echo "==> Building the app"
"$ROOT/Scripts/bundle.sh" release > /tmp/walkthrough-bundle.log 2>&1 \
    || { echo "  ✗ the app did not build — see /tmp/walkthrough-bundle.log"; exit 1; }
SHOT="$ROOT/build/window-shot"
D=com.lumiere.client
mkdir -p "$OUT"
[ -x "$APP" ] || { echo "No bundle. Run ./Scripts/bundle.sh release first." >&2; exit 1; }
swiftc -O "$ROOT/Tools/window-shot.swift" -o "$SHOT" 2>/dev/null
swiftc -O "$ROOT/Tools/image-diff.swift" -o "$DIFF" 2>/dev/null
mkdir -p "$BASE"

ORIG_THEME=$(defaults read $D appTheme 2>/dev/null || echo standard)
ORIG_CHROME=$(defaults read $D chromeStyle 2>/dev/null || echo liquid)
# Pinned to light: the baselines were recorded in light, and "auto" follows
# the Mac, so a Mac switched to dark mode failed every shot at 12% with
# nothing wrong. Put back afterwards like the theme.
ORIG_APPEARANCE=$(defaults read $D appearance 2>/dev/null || echo auto)
# And the sidebar closed, as the baselines have it: left open in the real app,
# it was in every shot and failed each one by eleven percent.
ORIG_SIDEBAR=$(defaults read $D showsSidebar 2>/dev/null || echo 0)
restore() {
    defaults write $D appTheme "$ORIG_THEME"; defaults write $D chromeStyle "$ORIG_CHROME"
    defaults write $D appearance "$ORIG_APPEARANCE"
    [ "$ORIG_SIDEBAR" = 1 ] && defaults write $D showsSidebar -bool true || defaults write $D showsSidebar -bool false
    pkill -9 -f "build/Lumiere.app/Contents/MacOS/Lumiere" 2>/dev/null || true
}
trap restore EXIT

FAILED=0
shot() { # name, then env assignments
    local name=$1; shift
    pkill -9 -f "build/Lumiere.app/Contents/MacOS/Lumiere" 2>/dev/null || true
    sleep 1
    # Launched outside this shell's job table, so killing it later is silent.
    (env LUMIERE_DEMO=1 "$@" "$APP" >/dev/null 2>&1 &)
    sleep "${SETTLE:-75}"
    local pid
    pid=$(pgrep -f "build/Lumiere.app/Contents/MacOS/Lumiere" | head -1)
    if ! "$SHOT" "$pid" "$OUT/$name.png" >/dev/null; then
        echo "  ✗ $name drew nothing (or no window)"; FAILED=1; return
    fi
    # A live view — the player, whose picture changes every frame — is only
    # checked for content. A baseline would fail on the frame, not the UI.
    case "$name" in *-live)
        echo "  ✓ $name (has content; not compared)"; return ;;
    esac
    # Baselines are kept small: 900 wide is plenty to compare at 256.
    sips -Z 900 "$OUT/$name.png" --out "$OUT/$name.small.png" >/dev/null
    if [ "$RECORD" = 1 ] || [ ! -f "$BASE/$name.png" ]; then
        cp "$OUT/$name.small.png" "$BASE/$name.png"
        echo "  ● $name recorded as the baseline"
    elif result=$("$DIFF" "$BASE/$name.png" "$OUT/$name.small.png"); then
        echo "  ✓ $name ($result)"
    else
        echo "  ✗ $name changed: $result — look at $OUT/$name.png; --record if meant"
        FAILED=1
    fi
}

defaults write $D appearance light
defaults write $D showsSidebar -bool false
for look in "standard solid" "paper liquid"; do
    set -- $look
    defaults write $D appTheme "$1"; defaults write $D chromeStyle "$2"
    echo "==> $1 + $2"
    shot "$1-$2-home"
    shot "$1-$2-series" LUMIERE_OPEN=series-1
    # A show with no seasons: its episodes must be listed, not "none cached".
    shot "$1-$2-seasonless" LUMIERE_OPEN=series-6
    shot "$1-$2-settings" LUMIERE_ROUTE=settings
    shot "$1-$2-health" LUMIERE_ROUTE=settings LUMIERE_SETTINGS=library "LUMIERE_SETTINGS_CARD=Library Health"
    # movie-2 is the demo's 4K HDR10 file, so this is the mpv path.
    SETTLE=${PLAYER_SETTLE:-80} shot "$1-$2-player-live" LUMIERE_PLAY=movie-2
done
echo "==> Shots in $OUT"
exit $FAILED
