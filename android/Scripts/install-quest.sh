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

ADB=$(command -v adb || true)
[[ -z $ADB && -x "$HOME/Library/Android/sdk/platform-tools/adb" ]] && ADB="$HOME/Library/Android/sdk/platform-tools/adb"
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
