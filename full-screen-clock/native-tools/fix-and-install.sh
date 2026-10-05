#!/bin/zsh
set -euo pipefail

XCODE_APP=""

# Find the actual Xcode app wherever it was installed.
XCODE_APP="$(mdfind 'kMDItemCFBundleIdentifier == "com.apple.dt.Xcode"' 2>/dev/null | head -n 1 || true)"

if [[ -z "$XCODE_APP" || ! -d "$XCODE_APP/Contents/Developer" ]]; then
  for candidate in     /Applications/Xcode*.app     "$HOME"/Applications/Xcode*.app     "$HOME"/Downloads/Xcode*.app     "$HOME"/Desktop/Xcode*.app
  do
    if [[ -d "$candidate/Contents/Developer" ]]; then
      XCODE_APP="$candidate"
      break
    fi
  done
fi

if [[ -z "$XCODE_APP" || ! -d "$XCODE_APP/Contents/Developer" ]]; then
  echo "ERROR: Could not locate the installed Xcode app."
  echo "Open Xcode once, then run this installer again."
  exit 1
fi

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
echo "Using Xcode: $XCODE_APP"
echo "Using developer directory: $DEVELOPER_DIR"

PROJECT_ROOT="$HOME/Documents/Clock"
PROJECT="$PROJECT_ROOT/Clock.xcodeproj"
SOURCE_DIR="$PROJECT_ROOT/Clock"
BUILD_DIR="$HOME/Library/Caches/ClockNativeBuild"
DEVICE_NAME="Jay’s iPad"
DEVICE_ID=""
BUNDLE_ID="com.jayden.Clock"
LOG="$HOME/Library/Logs/ClockNativeInstall.log"

REMOTE_BASE="https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/native-app"
TOOLS_BASE="https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/native-tools"
ASSET_DIR="$SOURCE_DIR/Assets.xcassets"
ICON_SCRIPT="$HOME/Library/Caches/ClockGenerateIcons.swift"
ICON_MASTER_DIR="$HOME/Library/Caches/ClockIconMasters"
ICON_MASTER_BASE="https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/native-assets"

mkdir -p "$HOME/Library/Logs"

echo "=== Clock native repair/install $(date) ===" | tee "$LOG"

if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: Xcode project not found at $PROJECT" | tee -a "$LOG"
  exit 1
fi

echo "1/6 Replacing native source with the latest Clock build..." | tee -a "$LOG"
CACHE_BUST="$(date +%s)"
curl -fsSL "$REMOTE_BASE/ContentView.swift?v=$CACHE_BUST" -o "$SOURCE_DIR/ContentView.swift"
curl -fsSL "$REMOTE_BASE/ClockApp.swift?v=$CACHE_BUST" -o "$SOURCE_DIR/ClockApp.swift"

if ! grep -q "BACKGROUND_PHOTO_SETTINGS" "$SOURCE_DIR/ContentView.swift"; then
  echo "ERROR: Latest background-photo Clock source was not downloaded; refusing to build stale code." | tee -a "$LOG"
  exit 1
fi

echo "Confirmed latest background-photo Clock source is present." | tee -a "$LOG"

if ! grep -q "ClockChromeC" "$SOURCE_DIR/ContentView.swift"; then
  echo "ERROR: Latest alternate-icon Clock source was not downloaded." | tee -a "$LOG"
  exit 1
fi

if grep -q "raw.githack.com" "$SOURCE_DIR/ContentView.swift"; then
  echo "ERROR: old raw.githack loader is still present." | tee -a "$LOG"
  exit 1
fi

echo "2/6 Installing the exact approved app icon artwork..." | tee -a "$LOG"
mkdir -p "$ASSET_DIR" "$ICON_MASTER_DIR"
curl -fsSL "$TOOLS_BASE/generate-icons.swift?v=$CACHE_BUST" -o "$ICON_SCRIPT"

for icon_name in ClockItalicC ClockWordmark ClockChromeC; do
  curl -fsSL \
    "$ICON_MASTER_BASE/${icon_name}_master.jpg?v=$CACHE_BUST" \
    -o "$ICON_MASTER_DIR/${icon_name}_master.jpg"
done

xcrun swift "$ICON_SCRIPT" "$ASSET_DIR" "$ICON_MASTER_DIR" 2>&1 | tee -a "$LOG"

for icon_set in ClockItalicC ClockWordmark ClockChromeC; do
  if [[ ! -f "$ASSET_DIR/$icon_set.appiconset/Contents.json" ]]; then
    echo "ERROR: Failed to generate $icon_set." | tee -a "$LOG"
    exit 1
  fi
done

echo "3/6 Cleaning old build output..." | tee -a "$LOG"
rm -rf "$BUILD_DIR"

echo "4/6 Building and signing Clock..." | tee -a "$LOG"
xcodebuild \
  -project "$PROJECT" \
  -scheme Clock \
  -configuration Debug \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES=ClockItalicC ClockWordmark ClockChromeC" \
  ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS=YES \
  clean build 2>&1 | tee -a "$LOG"

APP_PATH="$BUILD_DIR/Build/Products/Debug-iphoneos/Clock.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Build finished but Clock.app was not found." | tee -a "$LOG"
  exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"
PLIST_DUMP="$(plutil -p "$INFO_PLIST" 2>/dev/null || true)"

for icon_name in ClockItalicC ClockWordmark ClockChromeC; do
  if ! printf '%s\n' "$PLIST_DUMP" | grep -q "$icon_name"; then
    echo "ERROR: Built app did not register alternate icon $icon_name." | tee -a "$LOG"
    echo "The installer will not install a broken icon build." | tee -a "$LOG"
    exit 1
  fi
done

echo "Confirmed all 3 alternate icons are registered in the built app." | tee -a "$LOG"

echo "5/6 Installing Clock on $DEVICE_NAME..." | tee -a "$LOG"
xcrun devicectl device install app --device "$DEVICE_NAME" "$APP_PATH" 2>&1 | tee -a "$LOG"

echo "6/6 Launching Clock..." | tee -a "$LOG"
xcrun devicectl device process launch --device "$DEVICE_NAME" "$BUNDLE_ID" 2>&1 | tee -a "$LOG" || true

echo
echo "✅ Rebuilt Clock with background photos and 3 selectable app icons."
echo "Log: $LOG"
