#!/bin/bash
# Installs Lumiere into /Applications.
#
#   ./Scripts/install.sh            build release, then install
#   ./Scripts/install.sh --no-build install whatever is already in build/
#
# Nothing in the plan covered this, which is why the app only ever ran from
# build/Lumiere.app by absolute path. A media player you cannot launch from
# Spotlight or the Dock is not finished.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Lumiere.app"
DEST="/Applications/Lumiere.app"

if [ "${1:-}" != "--no-build" ]; then
	echo "==> Building release"
	"$ROOT/Scripts/bundle.sh" release
fi

if [ ! -d "$APP" ]; then
	echo "No $APP. Run ./Scripts/bundle.sh release first." >&2
	exit 1
fi

# A release bundle carries libmpv inside it; a debug one does not, and installing
# one leaves /Applications holding an app that cannot play most of a real library
# on any Mac without Homebrew.
#
# This is a hard failure rather than the warning it used to be. As a warning it did
# not work: `--no-build` against a stale debug bundle printed it, scrolled past in
# the install output, and put a broken app in /Applications anyway. A warning that
# does not stop the thing it is warning about is just a log line.
if [ ! -d "$APP/Contents/Frameworks" ]; then
	if [ "${LUMIERE_ALLOW_NO_MPV:-}" = "1" ]; then
		echo "    warning: no Contents/Frameworks — needs Homebrew's mpv" >&2
		echo "    installing anyway because LUMIERE_ALLOW_NO_MPV=1" >&2
	else
		echo "Refusing to install: $APP has no Contents/Frameworks, so libmpv is" >&2
		echo "not vendored and playback will fail without Homebrew's mpv." >&2
		echo >&2
		echo "  ./Scripts/install.sh                 build release, then install" >&2
		echo "  ./Scripts/bundle.sh release          build the standalone bundle first" >&2
		echo "  LUMIERE_ALLOW_NO_MPV=1 ...           install it anyway" >&2
		exit 1
	fi
fi

# Refuse to replace a running copy. Overwriting the bundle out from under a live
# process gives it half-swapped dylibs and a crash with no obvious cause.
#
# `pgrep -x` on the executable name, not `-f` on its path. `-f` matches the whole
# command line of every process, so any shell, editor or grep that merely mentions
# the path counted as "Lumiere is running" — including this script's own tooling.
# The failure is worse than a false alarm: it refuses the install, prints a message
# that is not true, and leaves you looking for an app that is not open.
if pgrep -x Lumiere >/dev/null 2>&1; then
	echo "Lumiere is running. Quit it first." >&2
	exit 1
fi

if [ -d "$DEST" ]; then
	echo "==> Replacing $DEST"
	rm -rf "$DEST"
else
	echo "==> Installing to $DEST"
fi

# ditto rather than cp: it preserves the resource forks and extended attributes
# that make up a signed bundle, and cp -R quietly breaks the signature.
ditto "$APP" "$DEST"

# The signature has to be re-applied after the copy — ditto disturbs the seal —
# and the Finder needs a nudge or it keeps showing the generic icon from its cache.
#
# Same named-identity logic as bundle.sh, and it has to be: this line used to
# hard-code ad-hoc independently of that one, so fixing bundle.sh's signing step
# alone did nothing — every install silently re-signed ad-hoc right after, undoing
# it. The `|| true` that used to swallow this step's errors is also why that went
# unnoticed; a failed re-sign here now stops the script instead of shipping a
# broken bundle silently.
SIGNING_IDENTITY="Lumiere Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
	codesign --force --deep --sign "$SIGNING_IDENTITY" "$DEST"
else
	codesign --force --deep --sign - "$DEST"
fi
touch "$DEST"

# `touch` alone does not do it. The bundle carries a complete Lumiere.icns — all ten
# sizes, 16 through 512@2x — and Info.plist names it correctly, yet Finder and the
# Dock kept drawing the generic bundle icon. The reason is that Launch Services
# caches an app's icon against its bundle id, and reinstalling to the same path with
# the same id leaves that cache authoritative; a modification date is not what it
# invalidates on. Re-registering the bundle is what actually replaces the entry.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
	"$LSREGISTER" -f "$DEST"
	# The Dock reads its own icon cache, so it needs telling separately. It relaunches
	# itself immediately and this is not disruptive.
	killall Dock >/dev/null 2>&1 || true
fi

echo "==> Done"
echo "    $DEST ($(du -sh "$DEST" | awk '{print $1}'))"
echo "    open -a Lumiere"
