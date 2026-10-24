#!/bin/bash
# The bundled libraries, pinned. A release build compares what it just
# vendored against Scripts/dylibs.lock and stops if Homebrew has changed any of
# them — added, removed or rebuilt — instead of shipping whatever is installed
# that day. That is how brotli 1.2.0 arrived unreviewed and broke launch.
#
#   ./Scripts/dylib-lock.sh check  <App.app>   fail on any difference
#   ./Scripts/dylib-lock.sh update <App.app>   accept what is there now
set -euo pipefail

MODE="$1"
APP="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/Scripts/dylibs.lock"
CURRENT="$(mktemp)"
trap 'rm -f "$CURRENT"' EXIT

# The record vendor-dylibs.sh wrote: each library by the Homebrew file it
# was copied from, so the lock is about what Homebrew built, not about how
# this Mac then relinked and signed it.
MANIFEST="$APP/Contents/Resources/vendored-dylibs.txt"
[ -f "$MANIFEST" ] || { echo "    $MANIFEST is missing — not a release bundle" >&2; exit 1; }
sort "$MANIFEST" > "$CURRENT"

case "$MODE" in
	update)
		cp "$CURRENT" "$LOCK"
		echo "==> dylibs.lock updated: $(wc -l < "$LOCK" | tr -d ' ') libraries"
		;;
	check)
		if [ ! -f "$LOCK" ]; then
			# A fresh clone has none: the lock records one Mac's Homebrew. Warn,
			# and let whoever builds there review and pin their own.
			echo "    warning: no dylibs.lock — review the bundle, then ./Scripts/dylib-lock.sh update <App.app>" >&2
			exit 0
		fi
		if ! diff -u "$LOCK" "$CURRENT" > /tmp/dylibs.diff; then
			echo "==> The bundled libraries changed since they were last reviewed:" >&2
			grep -E '^[+-][^+-]' /tmp/dylibs.diff | sed 's/^/    /' >&2
			echo "    Review them (brew info, release notes), then accept with:" >&2
			echo "    ./Scripts/dylib-lock.sh update build/Lumiere.app" >&2
			exit 1
		fi
		echo "==> bundled libraries match dylibs.lock"
		;;
esac
