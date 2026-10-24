#!/bin/bash
# A brand-new server, end to end, against the fixture videos: first account,
# a library from a folder, a scan, browsing, a byte-range stream, and the
# security behaviour a release must keep (the throttle, the first-account
# rule). Never touches the real library: its own data dir and port.
#
#   ./Scripts/e2e-server.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
PORT=18198
BASE="http://127.0.0.1:$PORT"
H='X-Emby-Authorization: MediaBrowser Client="e2e", Device="e2e", DeviceId="e2e", Version="1"'
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT

fail() { echo "    ✗ $*" >&2; exit 1; }

mkdir -p "$WORK/media/Films"
for f in sample_h264.mkv sample_hevc_ac3.mkv; do
	mkdir -p "$WORK/media/Films/${f%.mkv} (2020)"
	cp "$HERE/mac/fixtures/$f" "$WORK/media/Films/${f%.mkv} (2020)/${f%.mkv} (2020).mkv"
done

(cd "$HERE/server" && go build -o "$WORK/lumiered" ./cmd/lumiered)
"$WORK/lumiered" -data "$WORK/data" -addr "127.0.0.1:$PORT" > "$WORK/log" 2>&1 &
PID=$!
for _ in $(seq 1 50); do curl -sf "$BASE/System/Info/Public" >/dev/null && break; sleep 0.2; done

curl -s "$BASE/Lumiere/Setup" | grep -q '"NeedsAccount":true' || fail "a new server does not ask for its first account"
TOKEN="$(curl -s -H "$H" -X POST "$BASE/Lumiere/Setup/Account" -d '{"Username":"e2e","Password":"e2e-password"}' \
	| python3 -c 'import sys,json; print(json.load(sys.stdin)["AccessToken"])')" || fail "first account"
A="X-Emby-Token: $TOKEN"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" -X POST "$BASE/Lumiere/Setup/Account" -d '{"Username":"x","Password":"x-password"}')
[ "$code" = 409 ] || fail "a second first account was allowed ($code)"

curl -sf -H "$A" -X POST "$BASE/Lumiere/Libraries" \
	-d "{\"Name\":\"Films\",\"CollectionType\":\"movies\",\"Paths\":[\"$WORK/media/Films\"]}" >/dev/null || fail "create library"
for _ in $(seq 1 100); do
	curl -s -H "$A" "$BASE/Library/Refresh/Status" | grep -q '"Running":false' && break; sleep 0.3
done
COUNT=$(curl -s -H "$A" "$BASE/Items?Recursive=true&IncludeItemTypes=Movie" | python3 -c 'import sys,json; print(json.load(sys.stdin)["TotalRecordCount"])')
[ "$COUNT" = 2 ] || fail "the scan found $COUNT films, not 2"
ID=$(curl -s -H "$A" "$BASE/Items?Recursive=true&IncludeItemTypes=Movie" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Items"][0]["Id"])')
BYTES=$(curl -s -H "$A" -r 0-1023 "$BASE/Videos/$ID/stream?static=true" | wc -c | tr -d ' ')
[ "$BYTES" = 1024 ] || fail "a byte-range stream returned $BYTES bytes"

# The traversal that a subtitle language once allowed is refused.
code=$(curl -s -o /dev/null -w '%{http_code}' -H "$A" -X POST \
	"$BASE/Items/$ID/RemoteImages/Download?type=../../escape&imageurl=https://image.tmdb.org/x.jpg")
[ "$code" = 400 ] || fail "an artwork kind with a path in it was accepted ($code)"

# Guessing passwords is throttled.
for _ in 1 2 3 4 5 6; do
	curl -s -o /dev/null -H "$H" -X POST "$BASE/Users/AuthenticateByName" -d '{"Username":"e2e","Pw":"wrong"}'
done
code=$(curl -s -o /dev/null -w '%{http_code}' -H "$H" -X POST "$BASE/Users/AuthenticateByName" -d '{"Username":"e2e","Pw":"e2e-password"}')
[ "$code" = 429 ] || fail "password guessing was not throttled ($code)"

echo "==> End to end: account, library, scan ($COUNT films), stream, and the guards all hold"
