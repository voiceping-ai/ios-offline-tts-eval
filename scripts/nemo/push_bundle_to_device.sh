#!/usr/bin/env bash
set -euo pipefail

# Physical device only. Do not use simulators.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

IOS_COREDEVICE_ID="${IOS_COREDEVICE_ID:-}"
IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-}"

MODEL_ID="${MODEL_ID:-nemo-fastpitch-hifigan-en}"
BUNDLE_DIR="${BUNDLE_DIR:-$REPO_DIR/artifacts/nemo_bundles/$MODEL_ID}"

if [ -z "$IOS_COREDEVICE_ID" ] || [ -z "$IOS_DEVICE_UDID" ]; then
  cat >&2 <<EOF
Missing IOS device identifiers.

Set:
  IOS_COREDEVICE_ID=<CoreDevice ID> IOS_DEVICE_UDID=<UDID> $0

Find connected devices:
  xcrun devicectl list devices
  xcrun xctrace list devices
EOF
  exit 1
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Missing bundle dir: $BUNDLE_DIR" >&2
  echo "Create it with the export scripts:" >&2
  echo "  ./scripts/nemo/create_venv.sh" >&2
  echo "  source ./scripts/nemo/.venv-nemo/bin/activate" >&2
  echo "  python3 scripts/nemo/export_fastpitch_onnx.py" >&2
  echo "  python3 scripts/nemo/export_hifigan_onnx.py" >&2
  exit 1
fi

cd "$REPO_DIR"

./scripts/install-device.sh

XCODE_DESTINATION="${IOS_XCODEBUILD_DESTINATION:-platform=iOS,id=${IOS_DEVICE_UDID}}"

BUNDLE_ID="$(
  xcodebuild \
    -scheme TTSEval \
    -configuration Release \
    -destination "$XCODE_DESTINATION" \
    -showBuildSettings \
    2>/dev/null | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=/ {print $2; exit}'
)"

if [ -z "$BUNDLE_ID" ]; then
  echo "Failed to detect PRODUCT_BUNDLE_IDENTIFIER from xcodebuild settings." >&2
  exit 1
fi

echo "Bundle ID: $BUNDLE_ID"

DEST_DIR="Documents/TTSEvalImports/$MODEL_ID"

echo "Pushing bundle to: $DEST_DIR"
xcrun devicectl device copy to \
  -d "$IOS_COREDEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "$BUNDLE_DIR" \
  --destination "$DEST_DIR" \
  --remove-existing-content true \
  >/dev/null

echo "✓ Bundle pushed. Open the app (Models tab) to import."

