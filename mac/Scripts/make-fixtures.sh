#!/bin/bash
# Generates synthetic test media into fixtures/.
#
# These exist so the playback engines can be verified without a Jellyfin server
# and without touching any real media. Idempotent: existing files are left alone,
# so re-running is cheap.
#
#   ./Scripts/make-fixtures.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/fixtures"
mkdir -p "$OUT"

if ! command -v ffmpeg >/dev/null; then
	echo "ffmpeg not found. brew install ffmpeg" >&2
	exit 1
fi

DURATION="${FIXTURE_DURATION:-8}"

make() {
	local name="$1"; shift
	if [ -f "$OUT/$name" ]; then
		echo "    exists  $name"
		return
	fi
	echo "==> $name"
	ffmpeg -v error -y "$@" "$OUT/$name"
}

VIDEO=(-f lavfi -i "testsrc2=size=1280x720:rate=24:duration=$DURATION")
VIDEO4K=(-f lavfi -i "testsrc2=size=3840x2160:rate=24:duration=$DURATION")
AUDIO=(-f lavfi -i "sine=frequency=440:duration=$DURATION")

# The AVPlayer case: everything AVFoundation takes natively.
make sample_h264.mp4 "${VIDEO[@]}" "${AUDIO[@]}" \
	-c:v libx264 -pix_fmt yuv420p -c:a aac -shortest

# The mpv case by container alone — identical streams, Matroska wrapper.
make sample_h264.mkv "${VIDEO[@]}" "${AUDIO[@]}" \
	-c:v libx264 -pix_fmt yuv420p -c:a aac -shortest

# HEVC 10-bit: hardware decode path on this Mac.
make sample_hevc10.mkv "${VIDEO[@]}" "${AUDIO[@]}" \
	-c:v libx265 -pix_fmt yuv420p10le -tag:v hvc1 -c:a aac -shortest

# The mpv case by audio codec: AC3 in an MP4 is fine, but this pairs it with
# Matroska the way a real rip does.
make sample_hevc_ac3.mkv "${VIDEO[@]}" "${AUDIO[@]}" \
	-c:v libx265 -pix_fmt yuv420p -tag:v hvc1 -c:a ac3 -ac 6 -shortest

# 4K HEVC 10-bit HDR10: the resolution and bit depth that matter, with the
# colour metadata a real UHD rip carries.
make sample_4k_hdr10.mkv "${VIDEO4K[@]}" "${AUDIO[@]}" \
	-c:v libx265 -pix_fmt yuv420p10le -tag:v hvc1 \
	-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
	-x265-params "hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
	-c:a aac -shortest

# Subtitles that need rendering rather than system handling.
if [ ! -f "$OUT/sample_subs.mkv" ]; then
	echo "==> sample_subs.mkv"
	cat > "$OUT/.subs.srt" <<'SRT'
1
00:00:01,000 --> 00:00:04,000
Styled subtitles need mpv to render.

2
00:00:04,500 --> 00:00:08,000
AVFoundation cannot draw these.
SRT
	ffmpeg -v error -y "${VIDEO[@]}" "${AUDIO[@]}" -i "$OUT/.subs.srt" \
		-c:v libx264 -pix_fmt yuv420p -c:a aac \
		-c:s ass -map 0:v -map 1:a -map 2:s -shortest "$OUT/sample_subs.mkv"
	rm -f "$OUT/.subs.srt"
else
	echo "    exists  sample_subs.mkv"
fi

echo
echo "Fixtures in $OUT:"
ls -1sh "$OUT" | tail -n +2
