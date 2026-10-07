#!/bin/bash
# How fast the home screen has been, read from the app's log — no need to
# open the app. See Diagnostics.swift for where the log lives.
#
#   ./Scripts/timings.sh [days]     default: everything in the log
set -euo pipefail
LOG="$HOME/Library/Logs/Lumiere/lumiere.log"
[ -f "$LOG" ] || { echo "No log yet — it starts filling the next time Lumiere runs."; exit 0; }
SINCE=""
if [ -n "${1:-}" ]; then
    SINCE=$(date -u -v-"${1}"d +%Y-%m-%dT%H:%M:%S)
fi
{ [ -f "$LOG.1" ] && cat "$LOG.1"; cat "$LOG"; } | python3 -c '
import re, sys
since = sys.argv[1]
home, card, reasons = [], [], {}
for line in sys.stdin:
    stamp = line.split(" ", 1)[0]
    if since and stamp < since:
        continue
    m = re.search(r"\[home\] (.+?) — .* in ([0-9.]+)s", line)
    if m:
        home.append(float(m.group(2)))
        reasons.setdefault(m.group(1), []).append(float(m.group(2)))
    m = re.search(r"\[home\] card updated ([0-9]+) ms", line)
    if m:
        card.append(float(m.group(1)))
def summary(name, xs, unit):
    if not xs:
        print(f"{name}: none recorded"); return
    xs = sorted(xs)
    pick = lambda q: xs[min(len(xs) - 1, int(q * len(xs)))]
    print(f"{name}: {len(xs)} — median {pick(.5):.2f}{unit}, 90th {pick(.9):.2f}{unit}, worst {xs[-1]:.2f}{unit}")
summary("Home rebuilds", home, " s")
summary("Ticked card to screen", card, " ms")
if reasons:
    print("Slowest causes (median):")
    for reason, xs in sorted(reasons.items(), key=lambda r: -sorted(r[1])[len(r[1]) // 2])[:5]:
        xs = sorted(xs)
        print(f"  {xs[len(xs) // 2]:.2f} s  {reason}  ({len(xs)}×)")
' "$SINCE"
