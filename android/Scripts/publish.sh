#!/bin/zsh
# Builds one of the three apps and places it beside the Mac's server, where every
# installed copy of that app finds it under Settings › Install Update.
#
#   ./Scripts/publish.sh          the TV's (app.lumiere.android, the projector)
#   ./Scripts/publish.sh quest    the Quest's, under android/quest
#   ./Scripts/publish.sh phone    the phone's, under android/phone
#
# Each app reads only its own folder (see Updater), so a phone is never offered the
# TV's app. The version number is the build's minute, so each build is newer than the last.
set -e
cd "$(dirname "$0")/.."
FLAVOR=${1:-tv}
case "$FLAVOR" in
	tv) SUB="" ;;
	phone|quest) SUB="/$FLAVOR" ;;
	*) echo "usage: publish.sh [tv|phone|quest]" >&2; exit 2 ;;
esac
TASK="assemble${(C)FLAVOR}Release"
./gradlew -q "$TASK" testDebugUnitTest
DEST="$HOME/Library/Application Support/LumiereServer/android$SUB"
mkdir -p "$DEST"
APK=app/build/outputs/apk/$FLAVOR/release/app-$FLAVOR-release.apk
AAPT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"*/aapt | tail -1)
CODE=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
NAME=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
# Written beside, then moved: an app asking mid-copy never sees half a file.
cp "$APK" "$DEST/lumiere.apk.part" && mv "$DEST/lumiere.apk.part" "$DEST/lumiere.apk"
# The fingerprint the app checks the download against before installing.
SHA=$(shasum -a 256 "$DEST/lumiere.apk" | awk '{print $1}')
printf '{"VersionCode": %d, "VersionName": "%s", "Sha256": "%s"}\n' "$CODE" "$NAME" "$SHA" > "$DEST/version.json"
echo "==> Published $NAME ($CODE) for the $FLAVOR app to find"
