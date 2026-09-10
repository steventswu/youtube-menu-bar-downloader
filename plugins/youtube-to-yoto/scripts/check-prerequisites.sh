#!/bin/sh
set -eu

PLUGIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORKSPACE_ROOT=${YOUTUBE_YOTO_WORKSPACE:-$(CDPATH= cd -- "$PLUGIN_DIR/../.." && pwd)}
DOWNLOADER_APP=${DOWNLOADER_APP:-"$WORKSPACE_ROOT/dist/Downloader.app"}
YOTO_DIR=${YOTO_MCP_DIR:-"$WORKSPACE_ROOT/YotoMCP"}

fail=0
if [ ! -x "$DOWNLOADER_APP/Contents/MacOS/Downloader" ]; then
  echo "Missing headless Downloader: $DOWNLOADER_APP" >&2
  fail=1
fi
if [ ! -f "$YOTO_DIR/dist/index.js" ]; then
  echo "Missing built YotoMCP: $YOTO_DIR/dist/index.js" >&2
  fail=1
fi
if ! command -v node >/dev/null 2>&1; then
  echo "Missing Node.js" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "Downloader: $DOWNLOADER_APP"
echo "YotoMCP: $YOTO_DIR/dist/index.js"
echo "Prerequisites OK; OAuth is handled by yoto-local at runtime."
