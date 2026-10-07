#!/bin/zsh
# Builds the release and places it beside the Mac's server, where every
# installed copy finds it under Settings › This Device › Install Update.
# The version number is the build's minute, so each build is newer than the last.
set -e
cd "$(dirname "$0")/.."
./gradlew -q assembleRelease testDebugUnitTest
DEST="$HOME/Library/Application Support/LumiereServer/android"
mkdir -p "$DEST"
APK=app/build/outputs/apk/release/app-release.apk
AAPT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"*/aapt | tail -1)
CODE=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
NAME=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
cp "$APK" "$DEST/lumiere.apk"
printf '{"VersionCode": %d, "VersionName": "%s"}\n' "$CODE" "$NAME" > "$DEST/version.json"
echo "==> Published $NAME ($CODE) for the Android app to find"
