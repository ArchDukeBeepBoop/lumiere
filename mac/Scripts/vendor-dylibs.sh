#!/bin/bash
# Copy a dylib and its full Homebrew dependency closure into an .app bundle,
# rewriting install names to @rpath so the result runs without Homebrew.
#
#   ./Scripts/vendor-dylibs.sh <path/to/App.app> <path/to/lib.dylib>
#
# Only /usr/local and /opt/homebrew paths are followed. System libraries under
# /usr/lib and /System are left alone — they are always present.
set -euo pipefail

APP="$1"
ROOT_LIB="$2"
FRAMEWORKS="$APP/Contents/Frameworks"
BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"

mkdir -p "$FRAMEWORKS"

is_vendorable() {
	case "$1" in
		/usr/local/*|/opt/homebrew/*) return 0 ;;
		*) return 1 ;;
	esac
}

# macOS ships bash 3.2, which has no associative arrays — the seen-set is a
# delimited string instead. Using `declare -A` here is what silently skipped the
# whole vendoring step on the first release build.
QUEUE=("$ROOT_LIB")
SEEN=""
COUNT=0

# An index rather than shifting the array: under `set -u`, bash 3.2 treats the
# expansion of an emptied array as an unbound variable and aborts.
HEAD=0
while [ $HEAD -lt ${#QUEUE[@]} ]; do
	LIB="${QUEUE[$HEAD]}"
	HEAD=$((HEAD + 1))

	# Resolve symlinks so libmpv.dylib and libmpv.2.dylib are one entry.
	REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$LIB")"
	NAME="$(basename "$REAL")"
	case "$SEEN" in *"|$NAME|"*) continue ;; esac
	SEEN="$SEEN|$NAME|"
	COUNT=$((COUNT + 1))

	cp -f "$REAL" "$FRAMEWORKS/$NAME"
	chmod u+w "$FRAMEWORKS/$NAME"
	install_name_tool -id "@rpath/$NAME" "$FRAMEWORKS/$NAME" 2>/dev/null || true

	while read -r DEP; do
		[ -z "$DEP" ] && continue
		is_vendorable "$DEP" || continue
		QUEUE+=("$DEP")
	done < <(otool -L "$REAL" | tail -n +2 | awk '{print $1}')
done

# Second pass: every vendored lib now points at its siblings via @rpath.
for LIB in "$FRAMEWORKS"/*.dylib; do
	while read -r DEP; do
		[ -z "$DEP" ] && continue
		is_vendorable "$DEP" || continue
		DEP_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DEP")"
		install_name_tool -change "$DEP" "@rpath/$(basename "$DEP_REAL")" "$LIB" 2>/dev/null || true
	done < <(otool -L "$LIB" | tail -n +2 | awk '{print $1}')
done

# And the executable itself.
while read -r DEP; do
	[ -z "$DEP" ] && continue
	is_vendorable "$DEP" || continue
	DEP_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$DEP")"
	install_name_tool -change "$DEP" "@rpath/$(basename "$DEP_REAL")" "$BIN" 2>/dev/null || true
done < <(otool -L "$BIN" | tail -n +2 | awk '{print $1}')

install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

echo "    vendored $COUNT dylibs into $FRAMEWORKS"
