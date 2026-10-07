#!/bin/bash
# What happened, from the logs — the server's overnight routine and the app's
# speed — without opening either app.
#
#   ./Scripts/report.sh [hours]    default: the last 24 hours of the server
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOURS="${1:-24}"
SLOG="$HOME/Library/Application Support/LumiereServer/logs/lumiered.log"

echo "== Server, last ${HOURS} h"
if [ ! -f "$SLOG" ]; then
    echo "  no server log yet"
else
    SINCE=$(date -v-"${HOURS}"H +%Y-%m-%dT%H:%M:%S)
    { [ -f "$SLOG.1" ] && cat "$SLOG.1"; cat "$SLOG"; } | python3 -c '
import re, sys
since = sys.argv[1]
checks = [
    ("Backup written",           r"msg=\"backup written\""),
    ("Backup failed",            r"msg=\"backup failed"),
    ("Restore rehearsal passed", r"msg=\"restore rehearsal passed\""),
    ("Restore rehearsal FAILED", r"newest backup could not be restored"),
    ("Library shrank overnight", r"library shrank overnight"),
    ("Subtitles fetched",        r"subtitles: queue.*state=done"),
    ("Subtitles not found",      r"subtitles: queue.*state=failed"),
    ("Scans",                    r"msg=\"scan"),
    ("Repairs made",             r"msg=\"repair: "),
    ("Startup repairs",          r"startup repair complete"),
    ("Repairs undone",           r"repair undone"),
    ("Collection changes",       r"msg=\"container: "),
    ("Collection members found", r"memberships recovered from Jellyfin"),
    ("Collections filled",       r"filled from film series"),
    ("Errors",                   r"level=ERROR"),
]
counts = {name: 0 for name, _ in checks}
last_error = ""
repairs = []
for line in sys.stdin:
    m = re.match(r"time=(\S+)", line)
    if not m or m.group(1)[:19] < since:
        continue
    for name, pattern in checks:
        if re.search(pattern, line):
            counts[name] += 1
            if name == "Errors":
                last_error = line.strip()[:160]
            if name == "Repairs made":
                what = re.search(r"msg=\"repair: ([^\"]+)\"(.*)", line)
                if what:
                    repairs.append(what.group(1) + " " + what.group(2).strip()[:60])
for name, _ in checks:
    flag = "  !" if counts[name] and any(w in name for w in ("FAILED", "failed", "shrank", "Errors")) else "   "
    print(f"{flag} {name}: {counts[name]}")
if last_error:
    print("    last error:", last_error)
for r in repairs[-8:]:
    print("    repair:", r)
' "$SINCE"
fi

echo "== App"
"$HERE/timings.sh" | sed 's/^/  /'
