#!/bin/zsh
set -u

APP_SUPPORT="$HOME/Library/Application Support/ClockAutoRenew"
CONFIG="$APP_SUPPORT/config"
STATE="$APP_SUPPORT/last_success_epoch"
LOG="$HOME/Library/Logs/ClockAutoRenew.log"
DERIVED="$HOME/Library/Caches/ClockAutoRenew/DerivedData"

mkdir -p "$APP_SUPPORT" "$HOME/Library/Logs" "$DERIVED"

log() {
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

if [[ ! -f "$CONFIG" ]]; then
  log "No config yet; skipping."
  exit 0
fi

source "$CONFIG"

: "${PROJECT_PATH:?PROJECT_PATH missing from config}"
: "${SCHEME:=Clock}"
: "${DEVICE_ID:?DEVICE_ID missing from config}"
: "${RENEW_AFTER_DAYS:=5}"

XCODE_APP="$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null | head -n 1 || true)"
if [[ -z "$XCODE_APP" || ! -d "$XCODE_APP/Contents/Developer" ]]; then
  log "Xcode app could not be located; skipping."
  exit 0
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

if [[ ! -e "$PROJECT_PATH" ]]; then
  log "Project not found: $PROJECT_PATH"
  exit 0
fi

NOW="$(date +%s)"
LAST=0
if [[ -f "$STATE" ]]; then
  LAST="$(cat "$STATE" 2>/dev/null || echo 0)"
fi

THRESHOLD=$(( RENEW_AFTER_DAYS * 24 * 60 * 60 ))
AGE=$(( NOW - LAST ))

if (( LAST > 0 && AGE < THRESHOLD )); then
  exit 0
fi

# Only attempt a rebuild/install when the paired iPad is currently reachable.
if ! xcrun devicectl device info details --device "$DEVICE_ID" >/dev/null 2>&1; then
  log "Renewal is due, but iPad $DEVICE_ID is not reachable. Will retry automatically."
  exit 0
fi

log "Renewal due. Rebuilding Clock for iPad $DEVICE_ID."

rm -rf "$DERIVED"

if ! xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphoneos \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic \
  build >> "$LOG" 2>&1
then
  log "Build/signing failed. Will retry later."
  exit 0
fi

APP_PATH="$(find "$DERIVED/Build/Products/Debug-iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit)"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  log "Build succeeded but no .app bundle was found."
  exit 0
fi

if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >> "$LOG" 2>&1; then
  log "Install failed. Will retry later."
  exit 0
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"

echo "$NOW" > "$STATE"
log "Clock renewed successfully. Next renewal target: about $RENEW_AFTER_DAYS days."

# Relaunch after renewal when possible. Failure here does not invalidate the renewal.
if [[ -n "$BUNDLE_ID" ]]; then
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >> "$LOG" 2>&1 || true
fi

exit 0
