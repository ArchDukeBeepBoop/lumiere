#!/bin/bash
# Build and rule gate for LumiereControl. Green before any commit.
#
# The line rule is Lumiere's own script, sourced rather than copied: three
# projects, one rule, one place to change it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "==> Building"
swift build 2>&1 | tail -3

# shellcheck source=../../mac/Scripts/lib/lines.sh
. "$ROOT/../mac/Scripts/lib/lines.sh"
echo "==> Line budget"
check_line_budget "$ROOT"
echo "==> Tests"
swift run -q ControlTests
echo "==> Green"
