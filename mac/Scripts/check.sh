#!/bin/bash
# Build and test gate. Must be green before any commit.
#
#   ./Scripts/check.sh
#
# Warnings are treated as failures: strict concurrency warnings in particular are
# real bugs waiting to happen, and this project has already had two.
#
# The policy itself, including the one narrow OpenGL exception, is in
# Scripts/lib/warnings.sh — shared so the release build bundle.sh produces is held
# to the same standard as the debug build gated here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=lib/warnings.sh
. "$ROOT/Scripts/lib/warnings.sh"

echo "==> Building"
BUILD_LOG="$(swift build 2>&1)" || { echo "$BUILD_LOG"; exit 1; }

check_build_warnings "$BUILD_LOG" || exit 1

# shellcheck source=lib/lines.sh
. "$ROOT/Scripts/lib/lines.sh"
echo "==> Line budget"
check_line_budget "$ROOT" || exit 1

# Every view that renders the player must actually be referenced by something.
#
# This exists because a refactor moved the full-window players into a computed
# property and nothing called it. A computed property nobody references still
# compiles, so the build stayed green, every test passed, and the video player
# simply stopped appearing. No test covers "is the player in the view tree", and
# the failure is invisible until someone presses Play.
echo "==> Wiring"
for symbol in overlays; do
	# `|| true`: grep exits 1 on no match, and `set -e` would abort the script
	# there — failing the build with no explanation, which is barely better than
	# the silent breakage this guard exists to catch.
	uses=$(grep -rn "^[[:space:]]*$symbol\$" Sources/Lumiere --include='*.swift' || true)
	if [ -z "$uses" ]; then
		echo "    FAIL: '$symbol' is defined but never rendered" >&2
		exit 1
	fi
done
if ! grep -rq "PlayerView(" Sources/Lumiere/Shell/ShellView+Overlays.swift; then
	echo "    FAIL: ShellView+Overlays no longer constructs PlayerView" >&2
	exit 1
fi
echo "    player overlays are referenced"

# Same class of breakage as the player above: a view that nothing constructs still
# compiles, and no test covers "is it on screen". Each pair is a view and the file
# that must build it.
for pair in \
	"SeasonPosterShelf:Sources/Lumiere/Detail/SeasonEpisodeList.swift" \
	"SeasonEpisodeList:Sources/Lumiere/Detail/DetailView.swift"
do
	symbol="${pair%%:*}"
	host="${pair##*:}"
	if ! grep -q "$symbol(" "$host"; then
		echo "    FAIL: $host no longer constructs $symbol" >&2
		exit 1
	fi
done
echo "    season shelves are referenced"

echo "==> Testing"
swift run LumiereTests
