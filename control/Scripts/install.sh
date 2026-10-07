#!/bin/bash
# Build a release bundle and put it in /Applications.
#
# /Applications rather than ~/Applications because SMAppService registers a
# login item against the bundle's location, and an app that moves loses its
# approval — which reads as the checkbox silently switching itself off.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# --no-build installs what is already in build/ — ship-all builds first, while
# the server is still running, so the swap below is the only downtime.
if [ "${1:-}" != "--no-build" ]; then
	"$ROOT/Scripts/bundle.sh" release
fi

DEST="/Applications/LumiereControl.app"
echo "==> Installing to $DEST"
# Stop a running copy first: replacing the bundle under a live process leaves it
# running from a deleted inode, which then answers for a version that no longer
# exists on disk.
pkill -f "LumiereControl.app/Contents/MacOS/LumiereControl" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$ROOT/build/LumiereControl.app" "$DEST"
echo "==> Installed. Open it from /Applications, or:"
echo "    open $DEST"
