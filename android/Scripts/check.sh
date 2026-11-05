#!/bin/zsh
# The gate: green before any commit. All three apps built as released, every app's
# unit tests, and Android Lint against its baseline (new findings fail; the recorded
# ones are paid down, never added to).
set -e
cd "$(dirname "$0")/.."
echo "==> Building the phone, TV and Quest apps"
./gradlew -q assemblePhoneRelease assembleTvRelease assembleQuestRelease
echo "==> Unit tests (all three apps)"
./gradlew -q testDebugUnitTest
echo "==> Lint (the Quest's and the TV's release builds)"
./gradlew -q lintQuestRelease lintTvRelease
echo "==> Green"
