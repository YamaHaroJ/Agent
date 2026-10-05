#!/bin/zsh
set -euo pipefail

ROOT="$HOME/Library/Application Support/ClockArtBridge"
REPO_BASE="https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/mac-bridge"
CACHE_BUST="$(date +%s)"

mkdir -p "$ROOT"

echo "1/4 Downloading Clock Art Bridge..."
curl -fsSL "$REPO_BASE/nowplaying.m?v=$CACHE_BUST" -o "$ROOT/nowplaying.m"
curl -fsSL "$REPO_BASE/clock-nowplaying.pl?v=$CACHE_BUST" -o "$ROOT/clock-nowplaying.pl"
curl -fsSL "$REPO_BASE/bridge.py?v=$CACHE_BUST" -o "$ROOT/bridge.py"
chmod +x "$ROOT/clock-nowplaying.pl" "$ROOT/bridge.py"

echo "2/4 Finding Xcode clang..."
XCODE_APP="$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null | head -n 1 || true)"
if [[ -n "$XCODE_APP" && -d "$XCODE_APP/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

if ! xcrun --find clang >/dev/null 2>&1; then
  echo "ERROR: clang was not found. Open Xcode once, then rerun this command."
  exit 1
fi

echo "3/4 Building the tiny Now Playing reader..."
xcrun clang \
  -dynamiclib \
  -fobjc-arc \
  -fblocks \
  -framework Foundation \
  -o "$ROOT/libClockNowPlaying.dylib" \
  "$ROOT/nowplaying.m"

echo "4/4 Starting the bridge..."
echo
echo "IMPORTANT FOR THE TEST:"
echo "On the iPad, route the audio to this Mac with Control Center > AirPlay."
echo "Then leave a song/video playing."
echo
exec /usr/bin/python3 "$ROOT/bridge.py"
