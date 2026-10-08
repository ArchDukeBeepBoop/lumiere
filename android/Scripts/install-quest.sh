#!/bin/zsh
# Builds both Quest apps and installs them on the headset plugged into this Mac:
# the 2D window (app.lumiere.android.quest) and the spatial one
# (app.lumiere.android.spatial), then opens the spatial one in the headset.
# The headset must be in developer mode; accept "Allow USB debugging" in it.
#   Scripts/install-quest.sh          both apps
#   Scripts/install-quest.sh 2d       the 2D window only
#   Scripts/install-quest.sh spatial  the spatial app only
set -e
cd "$(dirname "$0")/.."
WHICH=${1:-both}

# The Android SDK: local.properties, then ANDROID_HOME, then Android Studio's place,
# then beside adb. With none, Google's command-line tools are fetched into Android
# Studio's place (about 1 GB with the platform), and their licences accepted.
SDK=$(sed -n 's/^sdk.dir=//p' local.properties 2>/dev/null || true)
[[ -d $SDK ]] || SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -d $SDK ]] || SDK="$HOME/Library/Android/sdk"
if [[ ! -d $SDK/platforms ]] && command -v adb >/dev/null; then
    BESIDE=$(cd "$(dirname "$(readlink -f "$(command -v adb)")")/.." && pwd)
    [[ -d $BESIDE/platforms ]] && SDK=$BESIDE
fi
if [[ ! -d $SDK/platforms ]]; then
    echo "==> No Android SDK found. Fetching Google's command-line tools into $SDK"
    mkdir -p "$SDK/cmdline-tools"
    curl -fL# -o /tmp/lumiere-cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
    rm -rf "$SDK/cmdline-tools/latest" && unzip -q /tmp/lumiere-cmdline-tools.zip -d "$SDK/cmdline-tools" && mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest"
    rm -f /tmp/lumiere-cmdline-tools.zip
fi
if [[ ! -d $SDK/platforms/android-36 || ! -d $SDK/platform-tools ]]; then
    MANAGER=$(ls "$SDK"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | head -1)
    [[ -n $MANAGER ]] || { echo "The SDK at $SDK has no sdkmanager. Open Android Studio › SDK Manager and install Android 16 (API 36)."; exit 1; }
    echo "==> Installing Android 16 (API 36), its build tools and platform tools"
    yes | "$MANAGER" --sdk_root="$SDK" --licenses >/dev/null
    "$MANAGER" --sdk_root="$SDK" "platforms;android-36" "build-tools;36.0.0" "platform-tools"
fi
grep -q '^sdk.dir=' local.properties 2>/dev/null || echo "sdk.dir=$SDK" >> local.properties
echo "==> Android SDK: $SDK"

java -version >/dev/null 2>&1 || { echo "Java isn't installed. Install it with: brew install openjdk@17 (or install Android Studio), then run this again."; exit 1; }

# A signing key, as Android Studio makes the first time: release builds are signed with it.
if [[ ! -f $HOME/.android/debug.keystore ]]; then
    mkdir -p "$HOME/.android"
    keytool -genkeypair -keystore "$HOME/.android/debug.keystore" -storepass android -keypass android \
        -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -validity 10000 >/dev/null 2>&1
fi

ADB=$(command -v adb || true)
[[ -z $ADB && -x "$SDK/platform-tools/adb" ]] && ADB="$SDK/platform-tools/adb"
[[ -z $ADB ]] && { echo "adb not found. Install Android Studio, or: brew install android-platform-tools"; exit 1; }

echo "==> Looking for the headset (put it on and accept Allow USB debugging)"
for i in {1..60}; do
    STATE=$("$ADB" get-state 2>/dev/null || true)
    [[ $STATE == device ]] && break
    [[ $i == 1 ]] && "$ADB" devices | grep -q unauthorized && echo "    waiting for you to allow USB debugging in the headset…"
    sleep 2
done
[[ $STATE == device ]] || { echo "No headset found. Check the cable carries data, and that developer mode is on."; exit 1; }
echo "    found $("$ADB" shell getprop ro.product.model | tr -d '\r')"

TASKS=()
[[ $WHICH == both || $WHICH == 2d ]] && TASKS+=(assembleQuestRelease)
[[ $WHICH == both || $WHICH == spatial ]] && TASKS+=(:quest:assembleRelease)
echo "==> Building ${TASKS[*]}"
./gradlew -q "${TASKS[@]}"

if [[ $WHICH == both || $WHICH == 2d ]]; then
    echo "==> Installing the 2D window"
    "$ADB" install -r app/build/outputs/apk/quest/release/app-quest-release.apk
fi
if [[ $WHICH == both || $WHICH == spatial ]]; then
    echo "==> Installing the spatial app (about 116 MB)"
    "$ADB" install -r quest/build/outputs/apk/release/quest-release.apk
    echo "==> Opening it in the headset"
    "$ADB" shell am start -n app.lumiere.android.spatial/.LumiereSpace >/dev/null
fi
echo "==> Done. Both are under Library › Unknown Sources in the headset."
