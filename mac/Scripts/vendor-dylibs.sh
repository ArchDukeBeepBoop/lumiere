#!/bin/bash
# Copy a dylib and its full Homebrew dependency closure into an .app bundle,
# rewriting install names to @rpath so the result runs without Homebrew.
#
#   ./Scripts/vendor-dylibs.sh <path/to/App.app> <path/to/lib.dylib>
#
# Only Homebrew libraries are followed. System libraries under /usr/lib and
# /System are left alone — they are always present.
#
# A dependency can be named two ways, and both are followed:
#   - an absolute Homebrew path, /usr/local/opt/x/lib/libx.1.dylib;
#   - @rpath/libx.1.dylib, resolved through the *referencing* library's own
#     LC_RPATH entries (usually @loader_path/../lib).
# Only the first was handled until 2026-10-20, when brotli 1.2.0 started naming
# libbrotlicommon by @rpath. It was never copied, and Lumiere died in dyld at
# launch with "Lumiere cannot be opened because of a problem". See
# Scripts/verify-bundle.sh, which now refuses any bundle with a hole in it.
set -euo pipefail

APP="$1"
ROOT_LIB="$2"
FRAMEWORKS="$APP/Contents/Frameworks"
BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"

mkdir -p "$FRAMEWORKS"
# Where each copied library came from, for resolving its @rpath references.
ORIGINS="$(mktemp)"
trap 'rm -f "$ORIGINS"' EXIT

realpath_of() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }

is_homebrew() {
	case "$1" in
		/usr/local/*|/opt/homebrew/*) return 0 ;;
		*) return 1 ;;
	esac
}

# Prints the absolute file an @rpath/@loader_path dependency of $1 refers to,
# by the referencing library's own rpaths, or nothing when it cannot be found.
resolve_relative() {
	local lib="$1" dep="$2" dir name rp candidate
	dir="$(dirname "$lib")"
	case "$dep" in
		@loader_path/*) candidate="$dir/${dep#@loader_path/}"; [ -e "$candidate" ] && realpath_of "$candidate"; return 0 ;;
		@rpath/*) name="${dep#@rpath/}" ;;
		*) return 0 ;;
	esac
	while read -r rp; do
		[ -z "$rp" ] && continue
		rp="${rp/@loader_path/$dir}"
		candidate="$rp/$name"
		if [ -e "$candidate" ]; then realpath_of "$candidate"; return 0; fi
	done < <(otool -l "$lib" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}')
	# Homebrew keeps sibling libraries side by side.
	[ -e "$dir/$name" ] && realpath_of "$dir/$name"
	return 0
}

# Every dependency of $1 that belongs in the bundle, as absolute real paths.
bundle_deps() {
	local lib="$1" dep resolved
	while read -r dep; do
		[ -z "$dep" ] && continue
		if is_homebrew "$dep"; then
			realpath_of "$dep"
		else
			resolved="$(resolve_relative "$lib" "$dep")"
			[ -n "$resolved" ] && is_homebrew "$resolved" && echo "$resolved"
		fi
	done < <(otool -L "$lib" | tail -n +2 | awk '{print $1}')
	return 0
}

# macOS ships bash 3.2, which has no associative arrays — the seen-set is a
# delimited string instead. Using `declare -A` here is what silently skipped the
# whole vendoring step on the first release build.
QUEUE=("$(realpath_of "$ROOT_LIB")")
SEEN=""
COUNT=0

# An index rather than shifting the array: under `set -u`, bash 3.2 treats the
# expansion of an emptied array as an unbound variable and aborts.
HEAD=0
while [ $HEAD -lt ${#QUEUE[@]} ]; do
	REAL="${QUEUE[$HEAD]}"
	HEAD=$((HEAD + 1))
	NAME="$(basename "$REAL")"
	case "$SEEN" in *"|$NAME|"*) continue ;; esac
	SEEN="$SEEN|$NAME|"
	COUNT=$((COUNT + 1))

	cp -f "$REAL" "$FRAMEWORKS/$NAME"
	printf '%s\t%s\n' "$NAME" "$REAL" >> "$ORIGINS"
	chmod u+w "$FRAMEWORKS/$NAME"
	install_name_tool -id "@rpath/$NAME" "$FRAMEWORKS/$NAME" 2>/dev/null || true

	while read -r DEP; do
		[ -n "$DEP" ] && QUEUE+=("$DEP")
	done < <(bundle_deps "$REAL")
done

# Rewrites every bundle-bound reference in $1 to @rpath/<copied file name>.
# The source library is consulted for @rpath references, because the copy's
# rpaths point back into Homebrew.
relink() {
	local target="$1" source="$2" dep real
	while read -r dep; do
		[ -z "$dep" ] && continue
		if is_homebrew "$dep"; then
			real="$(realpath_of "$dep")"
		else
			real="$(resolve_relative "$source" "$dep")"
			[ -n "$real" ] && is_homebrew "$real" || continue
		fi
		install_name_tool -change "$dep" "@rpath/$(basename "$real")" "$target" 2>/dev/null || true
	done < <(otool -L "$target" | tail -n +2 | awk '{print $1}')
	return 0
}

# Second pass: every vendored lib points at its siblings by the name it was
# copied under — libbrotlicommon.1.2.0.dylib, not the symlink name it asked for.
for LIB in "$FRAMEWORKS"/*.dylib; do
	SOURCE="$(awk -F'\t' -v n="$(basename "$LIB")" '$1==n{print $2; exit}' "$ORIGINS")"
	relink "$LIB" "${SOURCE:-$LIB}"
	# The Homebrew rpaths mean nothing inside the bundle; the bundle's own does.
	while read -r RP; do
		[ -n "$RP" ] && install_name_tool -delete_rpath "$RP" "$LIB" 2>/dev/null || true
	done < <(otool -l "$LIB" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}')
	install_name_tool -add_rpath "@loader_path" "$LIB" 2>/dev/null || true
done

# And the executable itself.
relink "$BIN" "$BIN"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

echo "    vendored $COUNT dylibs into $FRAMEWORKS"
