#!/bin/bash
# Assemble the SwiftPM executable into a real Lumiere.app.
#
# This machine has Command Line Tools but no Xcode, so there is no xcodebuild to
# produce an app bundle. Everything xcodebuild would do — layout, Info.plist,
# dylib relocation, signing — happens here instead.
#
#   ./Scripts/bundle.sh            debug build
#   ./Scripts/bundle.sh release    optimised, with libmpv vendored into the bundle
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/Lumiere.app"
MPV_PREFIX="/usr/local/opt/mpv"

cd "$ROOT"

# shellcheck source=lib/warnings.sh
. "$ROOT/Scripts/lib/warnings.sh"

echo "==> Building ($CONFIG)"
# Held to the same warning policy check.sh applies to the debug build. This is the
# build that becomes the installed app, and until now it was the only one nothing
# inspected. `LUMIERE_ALLOW_WARNINGS=1` is the escape hatch for a bisect or a
# throwaway bundle; it is not for shipping.
BUILD_LOG="$(swift build -c "$CONFIG" 2>&1)" || { echo "$BUILD_LOG"; exit 1; }
if ! check_build_warnings "$BUILD_LOG"; then
	[ "${LUMIERE_ALLOW_WARNINGS:-}" = "1" ] || exit 1
	echo "    continuing anyway because LUMIERE_ALLOW_WARNINGS=1" >&2
fi
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lumiere"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Lumiere"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The icon. Regenerate with Scripts/make-icon.py if it is missing — an app with no
# icon gets the blank-page placeholder, which looks broken rather than unfinished.
echo "==> Rendering the icon"
# Compiled with the app's own IrisArt, so the Dock icon and the icon Settings
# draws are one geometry rather than two that agree until someone edits one.
ICONS="$ROOT/build/icons"
rm -rf "$ICONS" && mkdir -p "$ICONS"
swiftc -O "$ROOT/Tools/RenderIcon.swift" "$ROOT/Sources/Lumiere/Design/IrisArt.swift" \
	-o "$ROOT/build/rendericon"
"$ROOT/build/rendericon" "$ICONS"

SET="$ROOT/build/Lumiere.iconset"
rm -rf "$SET" && mkdir -p "$SET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
	set -- $pair
	cp "$ICONS/icon_$1.png" "$SET/icon_$2.png"
done
iconutil -c icns -o "$ROOT/Resources/Lumiere.icns" "$SET"

if [ -f "$ROOT/Resources/Lumiere.icns" ]; then
	cp "$ROOT/Resources/Lumiere.icns" "$APP/Contents/Resources/Lumiere.icns"
else
	echo "    warning: no Resources/Lumiere.icns — run ./Scripts/make-icon.py" >&2
fi

# Subtitle fonts, vendored so a styled subtitle looks the same on any machine.
# libass resolves font names against the system, so an unbundled font silently
# falls back to a default and the whole point of choosing a style is lost.
if [ -d "$ROOT/Resources/Fonts" ]; then
	mkdir -p "$APP/Contents/Resources/Fonts"
	cp "$ROOT/Resources/Fonts/"* "$APP/Contents/Resources/Fonts/"
	echo "    fonts: $(ls -1 "$APP/Contents/Resources/Fonts" | wc -l | tr -d " ") subtitle fonts"
fi

# SwiftPM emits resource bundles next to the binary; the app expects them inside
# Contents/Resources.
for bundle in "$(dirname "$BIN")"/*.bundle; do
	[ -e "$bundle" ] || continue
	cp -R "$bundle" "$APP/Contents/Resources/"
done

if [ "$CONFIG" = "release" ]; then
	echo "==> Vendoring libmpv"
	mkdir -p "$APP/Contents/Frameworks"
	# Copy libmpv and every Homebrew dylib it transitively needs, then rewrite the
	# install names so the app runs on a Mac without Homebrew.
	"$ROOT/Scripts/vendor-dylibs.sh" "$APP" "$MPV_PREFIX/lib/libmpv.dylib"
fi

# Ad-hoc signing (`--sign -`) derives the app's identity from the binary's own
# content hash, which changes on every rebuild — so macOS treats each build as a
# different app and any Keychain "Always Allow" grant is invalidated the moment the
# app is rebuilt. A named local identity keeps the signature constant across builds
# instead, so the grant actually holds. Falls back to ad-hoc if one has not been set
# up — see Scripts/make-signing-identity.sh.
SIGNING_IDENTITY="Lumiere Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
	echo "==> Signing ($SIGNING_IDENTITY)"
	codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
else
	echo "==> Signing (ad-hoc — run ./Scripts/make-signing-identity.sh for a stable identity)"
	codesign --force --deep --sign - "$APP"
fi

echo "==> Done: $APP"
du -sh "$APP" | awk '{print "    bundle size: " $1}'
