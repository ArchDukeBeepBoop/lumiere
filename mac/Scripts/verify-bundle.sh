#!/bin/bash
# Refuses a bundle that cannot launch. Run by bundle.sh (release) and
# install.sh; exits non-zero with the reason.
#
#   ./Scripts/verify-bundle.sh <path/to/App.app>
#
# 1. Every library reference inside the bundle resolves to a file inside it,
#    and none still points into Homebrew — the gap that shipped brotli 1.2.0
#    without libbrotlicommon and stopped Lumiere in dyld at launch.
# 2. The code signature is whole.
# 3. The binary actually starts: `--smoke-test` loads every linked library,
#    creates and destroys an mpv core, and exits before any window opens.
set -euo pipefail

APP="$1"
NAME="$(basename "$APP" .app)"
BIN="$APP/Contents/MacOS/$NAME"
FRAMEWORKS="$APP/Contents/Frameworks"
FAIL=0

complain() { echo "    ✗ $*" >&2; FAIL=1; }

machos=("$BIN")
if [ -d "$FRAMEWORKS" ]; then
	for f in "$FRAMEWORKS"/*.dylib; do [ -e "$f" ] && machos+=("$f"); done
fi

for f in "${machos[@]}"; do
	dir="$(dirname "$f")"
	while read -r dep; do
		[ -z "$dep" ] && continue
		case "$dep" in
			/usr/local/*|/opt/homebrew/*)
				complain "$(basename "$f") still links Homebrew: $dep" ;;
			@rpath/*)
				n="${dep#@rpath/}"
				[ -e "$FRAMEWORKS/$n" ] || [ -e "$dir/$n" ] || complain "$(basename "$f") needs $n, which is not in the bundle" ;;
			@loader_path/*)
				[ -e "$dir/${dep#@loader_path/}" ] || complain "$(basename "$f") needs $dep, which is not in the bundle" ;;
			@executable_path/*)
				[ -e "$(dirname "$BIN")/${dep#@executable_path/}" ] || complain "$(basename "$f") needs $dep, which is not in the bundle" ;;
		esac
	done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
done

if ! codesign --verify --deep --strict "$APP" 2>/tmp/verify-bundle-sign.txt; then
	complain "signature does not verify: $(head -1 /tmp/verify-bundle-sign.txt)"
fi

# Never launch a build that has no self-test mode: it would open its real
# window, library and all, until the timer stopped it. Older builds get the
# library checks above and nothing more.
if [ $FAIL -eq 0 ] && ! grep -q "smoke test passed" "$BIN"; then
	echo "    (no --smoke-test in this build; launch not attempted)"
elif [ $FAIL -eq 0 ]; then
	# Off Homebrew's paths, so a library the bundle forgot cannot be borrowed
	# from /usr/local and hide the hole. Bounded: a hang is a failure too.
	if ! OUT="$(env -i HOME="$HOME" DYLD_FALLBACK_LIBRARY_PATH=/usr/lib \
		/usr/bin/perl -e 'alarm 30; exec @ARGV' "$BIN" --smoke-test 2>&1)"; then
		complain "the app did not start: $(echo "$OUT" | grep -m1 -E 'Library not loaded|Reason|error' || echo "$OUT" | tail -1)"
	elif ! echo "$OUT" | grep -q "smoke test passed"; then
		complain "the app started but did not report back: $(echo "$OUT" | tail -1)"
	fi
fi

if [ $FAIL -ne 0 ]; then
	echo "==> $NAME.app FAILED verification — not shipping it" >&2
	exit 1
fi
echo "==> $NAME.app verified: ${#machos[@]} binaries resolve, signature whole, launches"
