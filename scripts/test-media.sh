#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TOOLS="$PWD/dist/Downloader.app/Contents/Helpers"
TEST_DIR="$(mktemp -d "$PWD/.build/media-test.XXXXXX")"
"$TOOLS/ffmpeg" -v error -f lavfi -i testsrc2=size=3840x2160:rate=1 -f lavfi -i sine=frequency=440 -t 1 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -c:a libopus "$TEST_DIR/source.mkv"
for FORMAT in m4a mp3 opus; do
  "$TOOLS/ffmpeg" -v error -i "$TEST_DIR/source.mkv" -vn "$TEST_DIR/audio.$FORMAT"
  "$TOOLS/ffprobe" -v error -show_entries stream=codec_name -of csv=p=0 "$TEST_DIR/audio.$FORMAT"
done
"$TOOLS/ffmpeg" -nostdin -v error -i "$TEST_DIR/source.mkv" -map 0:v:0 -map 0:a:0 -c:v hevc_videotoolbox -b:v 20M -allow_sw 1 -tag:v hvc1 -c:a aac -movflags +faststart "$TEST_DIR/video.mp4"
"$TOOLS/ffprobe" -v error -show_entries stream=codec_name,width,height -of csv=p=0 "$TEST_DIR/video.mp4"
printf 'Media fixtures retained at %s\n' "$TEST_DIR"
