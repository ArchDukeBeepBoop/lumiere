#!/bin/bash
# Measures Lumiere's real memory cost against the project's budgets.
#
#   ./Scripts/measure-memory.sh [browsing|playback]
#
# Reports phys_footprint, not RSS. RSS counts shared, clean framework pages that
# are not this app's cost — on Lumiere the two differ by around 70 MB, and RSS is
# the number that made an earlier measurement look like a budget failure when it
# was not. phys_footprint is what Activity Monitor shows and what the memory
# pressure system acts on.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-browsing}"
SAMPLES=6
INTERVAL=5
APP="$ROOT/build/Lumiere.app/Contents/MacOS/Lumiere"
# Overridable so the sustained-playback run can point at a long 4K file without
# the short fixtures being replaced.
FIXTURES="${LUMIERE_FIXTURES:-$ROOT/fixtures}"

# Budgets from the plan.
BROWSING_BUDGET=180
PLAYBACK_BUDGET=400

if [ ! -x "$APP" ]; then
	echo "No app bundle. Run ./Scripts/bundle.sh release first." >&2
	exit 1
fi

pkill -9 -f "Lumiere.app/Contents/MacOS/Lumiere" 2>/dev/null || true
rm -f "${TMPDIR}lumiere-demo.db"* 2>/dev/null || true
sleep 1

case "$MODE" in
	browsing)
		# Home shelves only. The cheap case, kept as a floor to compare against.
		BUDGET=$BROWSING_BUDGET
		LAUNCH_ENV=(LUMIERE_DEMO=1)
		SETTLE=70
		;;
	library)
		# The case the plan states the budget against: a 1000-item library open in
		# a full grid. Seeding 1000 posters takes several minutes on first launch.
		BUDGET=$BROWSING_BUDGET
		LAUNCH_ENV=(LUMIERE_DEMO=1 LUMIERE_DEMO_MOVIES=1000 LUMIERE_ROUTE=library:demo-movies)
		SETTLE=420
		;;
	playback)
		# movie-2 maps to the 4K HDR10 HEVC fixture, so this is the mpv path.
		BUDGET=$PLAYBACK_BUDGET
		LAUNCH_ENV=(LUMIERE_DEMO=1 LUMIERE_PLAY=movie-2)
		SETTLE=75
		SAMPLES=6
		INTERVAL=5
		;;
	playback-long)
		# Sustained decode. The stock fixtures are 8 seconds, which measures
		# start-up rather than playback — and a footprint that only ever gets
		# sampled for 8 seconds cannot show a leak. Both playback memory bugs the
		# audit found were invisible until this mode existed.
		#
		# Point LUMIERE_FIXTURES at a directory whose sample_4k_hdr10.mkv is long:
		#   ffmpeg -stream_loop 90 -i fixtures/sample_4k_hdr10.mkv -c copy long.mkv
		BUDGET=$PLAYBACK_BUDGET
		LAUNCH_ENV=(LUMIERE_DEMO=1 LUMIERE_PLAY=movie-2)
		SETTLE=75
		SAMPLES=20
		INTERVAL=30
		;;
	*)
		echo "Unknown mode: $MODE (expected browsing, library or playback)" >&2
		exit 1
		;;
esac

echo "==> Launching in $MODE mode"
env "${LAUNCH_ENV[@]}" LUMIERE_FIXTURES="$FIXTURES" "$APP" >/dev/null 2>&1 &
APP_PID=$!

# The demo library seeds ~250 items and generates their artwork on first run, so
# an early sample measures the seeding rather than the app.
echo "    settling for ${SETTLE}s (demo seeding)"
sleep "$SETTLE"

if ! kill -0 "$APP_PID" 2>/dev/null; then
	echo "FAIL: the app exited before it could be measured" >&2
	exit 1
fi

# An app that launched and drew nothing is not a measurement. A demo run that
# silently refused to start once passed this script at a third of the real
# figure. Playback modes cover the window with video, so only browsing checks.
if [ "$MODE" != "playback" ] && [ "$MODE" != "playback-long" ]; then
	swiftc -O "$ROOT/Tools/window-shot.swift" -o "$ROOT/build/window-shot" 2>/dev/null
	if ! "$ROOT/build/window-shot" "$APP_PID" "${TMPDIR}lumiere-measure.png" >/dev/null; then
		kill -9 "$APP_PID" 2>/dev/null || true
		echo "FAIL: the window has no content — nothing here would be worth measuring" >&2
		exit 1
	fi
fi

echo "==> Sampling"
PEAK=0
FIRST=""
LAST=0
for _ in $(seq 1 "$SAMPLES"); do
	SAMPLE=$(footprint "$APP_PID" 2>/dev/null \
		| awk '/phys_footprint:/ {gsub(/[^0-9]/,"",$2); print $2}' | head -1)
	[ -z "$SAMPLE" ] && continue
	echo "    ${SAMPLE} MB"
	[ -z "$FIRST" ] && FIRST=$SAMPLE
	LAST=$SAMPLE
	[ "$SAMPLE" -gt "$PEAK" ] && PEAK=$SAMPLE
	sleep "$INTERVAL"
done

CATEGORIES=$(footprint "$APP_PID" 2>/dev/null | grep -E "CG raster|IOSurface|CG image" || true)
kill -9 "$APP_PID" 2>/dev/null || true

echo
echo "    peak phys_footprint: ${PEAK} MB (budget ${BUDGET} MB)"
# Drift over the sampling window is the leak signal: a steady climb across a long
# run means something is being retained per frame or per request.
[ -n "$FIRST" ] && echo "    drift over window: $((LAST - FIRST)) MB (first ${FIRST} → last ${LAST})"
[ -n "$CATEGORIES" ] && { echo "    largest categories:"; echo "$CATEGORIES" | sed 's/^/      /'; }

if [ "$PEAK" -gt "$BUDGET" ]; then
	echo "FAIL: over budget by $((PEAK - BUDGET)) MB"
	exit 1
fi
echo "PASS: ${BUDGET}-MB budget met with $((BUDGET - PEAK)) MB to spare"
