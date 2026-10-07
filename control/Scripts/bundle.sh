#!/bin/bash
# Assemble LumiereControl.app, with the media server inside it.
#
# The server binary is bundled rather than installed on PATH. The controller then
# always runs the server it was built against — a stale lumiered answering
# today's client is a failure that looks like a bug in the app, and this makes
# that impossible rather than unlikely.
#
#   ./Scripts/bundle.sh            debug
#   ./Scripts/bundle.sh release    optimised
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/build/LumiereControl.app"
SERVER_SRC="$ROOT/../server"

cd "$ROOT"

echo "==> Building the controller ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/LumiereControl"

echo "==> Building the server"
if [ ! -d "$SERVER_SRC" ]; then
	echo "    cannot find the server at $SERVER_SRC" >&2
	exit 1
fi
# Built for this machine only. There is one deployment and it is this Mac.
(cd "$SERVER_SRC" && go build -o "$ROOT/build/lumiered" ./cmd/lumiered)

echo "==> Rendering the icon"
# Drawn from source at every size rather than downsampled from one. A 32px icon
# resampled from 1024 loses its stroke to antialiasing; drawn at 32 it survives,
# which is the size that actually appears in System Settings and the Finder list.
ICONS="$ROOT/build/icons"
rm -rf "$ICONS" && mkdir -p "$ICONS"
swiftc -O "$ROOT/Tools/RenderIcon.swift" "$ROOT/Sources/LumiereControl/IrisArt.swift" \
	-o "$ROOT/build/rendericon"
"$ROOT/build/rendericon" "$ICONS"

SET="$ROOT/build/LumiereControl.iconset"
rm -rf "$SET" && mkdir -p "$SET"
for pair in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
	set -- $pair
	cp "$ICONS/icon_$1.png" "$SET/icon_$2.png"
done
iconutil -c icns -o "$ROOT/build/LumiereControl.icns" "$SET"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/LumiereControl"
cp "$ROOT/build/lumiered" "$APP/Contents/Resources/lumiered"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/build/LumiereControl.icns" "$APP/Contents/Resources/LumiereControl.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing"
# Signed like Lumiere. SMAppService needs a signed bundle to register a login
# item at all; an unsigned one fails with a message that does not say so.
#
# The server too, by name: `--deep` signs nested *bundles*, and a bare
# executable in Resources is not one, so lumiered shipped unsigned. Signing
# it gives the application firewall a stable identity to remember an
# allowance against. It does not make loopback connects faster: the 14–76 ms
# per connect measured on the development Mac turned out to be its network
# extensions (LuLu, a VPN's transparent proxy, AdGuard) inspecting every new
# flow, and an allowance in Apple's own firewall changed nothing. Lumiere
# sidesteps it for video by opening files from disk.
# With the Mac's own signing identity where it has one, and the server under
# a fixed identifier. Ad-hoc signatures change with every build, so macOS
# took each install for a new program and asked again for the removable
# volume the library lives on; a stable identity is asked once and kept.
SIGNING_IDENTITY="Lumiere Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
	codesign --force --sign "$SIGNING_IDENTITY" --identifier com.lumiere.server "$APP/Contents/Resources/lumiered"
	codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
else
	codesign --force --sign - --identifier com.lumiere.server "$APP/Contents/Resources/lumiered"
	codesign --force --deep --sign - "$APP"
fi

echo "==> Done: $APP"
