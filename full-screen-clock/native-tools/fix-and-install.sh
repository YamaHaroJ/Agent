#!/bin/zsh
set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

PROJECT_ROOT="$HOME/Documents/Clock"
PROJECT="$PROJECT_ROOT/Clock.xcodeproj"
SOURCE_DIR="$PROJECT_ROOT/Clock"
BUILD_DIR="$HOME/Library/Caches/ClockNativeBuild"
DEVICE_NAME="Jay's iPad"
BUNDLE_ID="com.jayden.Clock"
LOG="$HOME/Library/Logs/ClockNativeInstall.log"

REMOTE_BASE="https://raw.githubusercontent.com/YamaHaroJ/Agent/main/full-screen-clock/native-app"

mkdir -p "$HOME/Library/Logs"

echo "=== Clock native repair/install $(date) ===" | tee "$LOG"

if [[ ! -d "$PROJECT" ]]; then
  echo "ERROR: Xcode project not found at $PROJECT" | tee -a "$LOG"
  exit 1
fi

echo "1/5 Replacing native source with the fixed GitHub-direct loader..." | tee -a "$LOG"
curl -fsSL "$REMOTE_BASE/ContentView.swift" -o "$SOURCE_DIR/ContentView.swift"
curl -fsSL "$REMOTE_BASE/ClockApp.swift" -o "$SOURCE_DIR/ClockApp.swift"

if grep -q "raw.githack.com" "$SOURCE_DIR/ContentView.swift"; then
  echo "ERROR: old raw.githack loader is still present." | tee -a "$LOG"
  exit 1
fi

echo "2/5 Cleaning old build output..." | tee -a "$LOG"
rm -rf "$BUILD_DIR"

echo "3/5 Building and signing Clock..." | tee -a "$LOG"
xcodebuild   -project "$PROJECT"   -scheme Clock   -configuration Debug   -sdk iphoneos   -destination "generic/platform=iOS"   -derivedDataPath "$BUILD_DIR"   -allowProvisioningUpdates   CODE_SIGN_STYLE=Automatic   clean build 2>&1 | tee -a "$LOG"

APP_PATH="$BUILD_DIR/Build/Products/Debug-iphoneos/Clock.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Build finished but Clock.app was not found." | tee -a "$LOG"
  exit 1
fi

echo "4/5 Installing Clock on $DEVICE_NAME..." | tee -a "$LOG"
xcrun devicectl device install app   --device "$DEVICE_NAME"   "$APP_PATH" 2>&1 | tee -a "$LOG"

echo "5/5 Launching Clock..." | tee -a "$LOG"
xcrun devicectl device process launch   --device "$DEVICE_NAME"   "$BUNDLE_ID" 2>&1 | tee -a "$LOG" || true

echo
echo "✅ Fixed source, cleaned, rebuilt, installed, and launched Clock."
echo "Log: $LOG"
