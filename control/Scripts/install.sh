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
# Quit, don't kill. A quit runs applicationWillTerminate, which sends the
# server SIGTERM; pkill skipped that, leaving the old server running from a
# binary this script is about to delete — answering on 8098 as a version that
# no longer exists on disk. Then wait for the server itself to let go of the
# database and the port before anything is replaced (CLAUDE.md: quit before
# install). The kill is only a fallback for a controller that will not quit.
osascript -e 'tell application id "com.lumiere.control" to quit' 2>/dev/null || true
for _ in $(seq 1 30); do
	pgrep -f "LumiereControl.app/Contents/(MacOS/LumiereControl|Resources/lumiered)" >/dev/null || break
	sleep 0.5
done
pkill -f "LumiereControl.app/Contents/MacOS/LumiereControl" 2>/dev/null || true
pkill -TERM -f "LumiereControl.app/Contents/Resources/lumiered" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
cp -R "$ROOT/build/LumiereControl.app" "$DEST"
echo "==> Installed. Open it from /Applications, or:"
echo "    open $DEST"
