#!/bin/zsh
# Builds the TV app (the tv flavor — app.lumiere.android, the projector) and places it beside the Mac's server, where every
# installed copy finds it under Settings › This Device › Install Update.
# The version number is the build's minute, so each build is newer than the last.
set -e
cd "$(dirname "$0")/.."
./gradlew -q assembleTvRelease testDebugUnitTest
DEST="$HOME/Library/Application Support/LumiereServer/android"
mkdir -p "$DEST"
APK=app/build/outputs/apk/tv/release/app-tv-release.apk
AAPT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"*/aapt | tail -1)
CODE=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p")
NAME=$("$AAPT" dump badging "$APK" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
cp "$APK" "$DEST/lumiere.apk"
# The fingerprint the app checks the download against before installing.
SHA=$(shasum -a 256 "$DEST/lumiere.apk" | awk '{print $1}')
printf '{"VersionCode": %d, "VersionName": "%s", "Sha256": "%s"}\n' "$CODE" "$NAME" "$SHA" > "$DEST/version.json"
echo "==> Published $NAME ($CODE) for the Android app to find"
