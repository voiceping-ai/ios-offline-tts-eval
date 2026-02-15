#!/usr/bin/env bash
set -euo pipefail

# Physical device only. Do not use simulators.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IOS_COREDEVICE_ID="${IOS_COREDEVICE_ID:-}" # CoreDevice id for devicectl (required for install)
IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-}"     # UDID for xcodebuild destination (optional)

XCODE_DESTINATION="${IOS_XCODEBUILD_DESTINATION:-}"
if [ -z "$XCODE_DESTINATION" ]; then
  if [ -n "$IOS_DEVICE_UDID" ]; then
    XCODE_DESTINATION="platform=iOS,id=${IOS_DEVICE_UDID}"
  else
    # Build-only (no install) if device id is not provided.
    XCODE_DESTINATION="generic/platform=iOS"
  fi
fi

cd "$REPO_DIR"

./scripts/setup-ios-deps.sh

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it (brew install xcodegen)." >&2
  exit 1
fi

SPEC="$REPO_DIR/project.yml"
if [ -f "$REPO_DIR/project.local.yml" ]; then
  SPEC="$REPO_DIR/project.local.yml"
fi

xcodegen generate --spec "$SPEC"

# Build for the specific physical device.
xcodebuild \
  -scheme TTSEval \
  -configuration Release \
  -destination "$XCODE_DESTINATION" \
  -allowProvisioningUpdates \
  build

# Resolve the built .app path from build settings to avoid ambiguous DerivedData matches.
TARGET_BUILD_DIR="$(
  xcodebuild \
    -scheme TTSEval \
    -configuration Release \
    -destination "$XCODE_DESTINATION" \
    -showBuildSettings \
    2>/dev/null | awk -F' = ' '/TARGET_BUILD_DIR/ {print $2; exit}'
)"

WRAPPER_NAME="$(
  xcodebuild \
    -scheme TTSEval \
    -configuration Release \
    -destination "$XCODE_DESTINATION" \
    -showBuildSettings \
    2>/dev/null | awk -F' = ' '/WRAPPER_NAME/ {print $2; exit}'
)"

APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"

if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$WRAPPER_NAME" ] || [ ! -d "$APP_PATH" ]; then
  # Fallback (best effort).
  APP_PATH="$(
    /usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" \
      -type d -name "TTSEval.app" \
      -path "*/Build/Products/Release-iphoneos/*" \
      2>/dev/null | /usr/bin/head -n 1
  )"
fi

if [ -z "$APP_PATH" ]; then
  echo "Built app not found in DerivedData. Open the project in Xcode and install from there." >&2
  exit 1
fi

if [ -z "$IOS_COREDEVICE_ID" ]; then
  cat >&2 <<EOF
IOS_COREDEVICE_ID is not set; skipping install.

Built app:
  $APP_PATH

To install to a physical device, set:
  IOS_COREDEVICE_ID=<CoreDevice ID> IOS_DEVICE_UDID=<UDID> ./scripts/install-device.sh

Find connected devices:
  xcrun devicectl list devices
  xcrun xctrace list devices
EOF
  exit 0
fi

echo "Installing: $APP_PATH"
xcrun devicectl device install app --device "$IOS_COREDEVICE_ID" "$APP_PATH"
