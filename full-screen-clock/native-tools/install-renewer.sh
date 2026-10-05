#!/bin/zsh
set -e

BASE="$HOME/Library/Application Support/ClockAutoRenew"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs"
PLIST="$LAUNCH_AGENTS/com.jay.clock-auto-renew.plist"
SCRIPT="$BASE/clock-renew.sh"
CONFIG="$BASE/config"

mkdir -p "$BASE" "$LAUNCH_AGENTS" "$LOGS"

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SOURCE_DIR/clock-renew.sh" "$SCRIPT"
chmod +x "$SCRIPT"

PROJECT_PATH="${1:-$HOME/Documents/Clock/Clock.xcodeproj}"
SCHEME="${2:-Clock}"
DEVICE_ID="${3:-}"

if [[ -z "$DEVICE_ID" ]]; then
  echo
  echo "Connected / paired devices:"
  DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcrun devicectl list devices || true
  echo
  read "DEVICE_ID?Paste your iPad device identifier: "
fi

cat > "$CONFIG" <<EOF
PROJECT_PATH="$PROJECT_PATH"
SCHEME="$SCHEME"
DEVICE_ID="$DEVICE_ID"
RENEW_AFTER_DAYS=5
EOF

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jay.clock-auto-renew</string>

  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <!-- Check every 6 hours. The script only rebuilds after 5 days,
       and otherwise exits immediately. If the iPad is unavailable,
       it retries on a later check. -->
  <key>StartInterval</key>
  <integer>21600</integer>

  <key>StandardOutPath</key>
  <string>$LOGS/ClockAutoRenew.launchd.log</string>

  <key>StandardErrorPath</key>
  <string>$LOGS/ClockAutoRenew.launchd-error.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.jay.clock-auto-renew"

echo
echo "Clock auto-renew installed."
echo "It checks every 6 hours and renews after 5 days, before the 7-day Personal Team profile expires."
echo "Main log: $HOME/Library/Logs/ClockAutoRenew.log"
