#!/usr/bin/env bash
set -euo pipefail

# Physical device only. Do not use simulators.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IOS_COREDEVICE_ID="${IOS_COREDEVICE_ID:-}"
IOS_DEVICE_UDID="${IOS_DEVICE_UDID:-}"

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

XCODE_DESTINATION="${IOS_XCODEBUILD_DESTINATION:-platform=iOS,id=${IOS_DEVICE_UDID}}"

DATASET="${TTSEVAL_DATASET:-short}"   # short|medium|long|all
PROMPT_LIMIT="${TTSEVAL_PROMPT_LIMIT:-1}" # 1 for smoke; set 0 to disable limit
TIMEOUT_S="${TTSEVAL_TIMEOUT_S:-7200}" # 2 hours
POLL_S="${TTSEVAL_POLL_S:-10}"

cd "$REPO_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it (brew install xcodegen)." >&2
  exit 1
fi

./scripts/install-device.sh

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

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

existing_out="$(
  xcrun devicectl device info files \
    -d "$IOS_COREDEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --subdirectory "Documents/TTSEvalExports" \
    --no-recurse \
    2>&1 || true
)"

existing_results=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  existing_results+=("$f")
done < <(echo "$existing_out" | rg -o 'results-[^[:space:]]+\\.json' | sort -u || true)

echo "Launching autorun benchmark (dataset=$DATASET, promptLimit=$PROMPT_LIMIT)..."

LAUNCH_JSON="$(mktemp)"
trap 'rm -f "$LAUNCH_JSON"' EXIT

ENV_JSON="{\"TTSEVAL_AUTORUN\":\"benchmark\",\"TTSEVAL_DATASET\":\"${DATASET}\",\"TTSEVAL_PROMPT_LIMIT\":\"${PROMPT_LIMIT}\"}"

if ! xcrun devicectl device process launch \
  -d "$IOS_COREDEVICE_ID" \
  --terminate-existing \
  --activate \
  -e "$ENV_JSON" \
  --json-output "$LAUNCH_JSON" \
  "$BUNDLE_ID" \
  >/dev/null; then
  # Some platforms don't support --terminate-existing; retry without it.
  xcrun devicectl device process launch \
    -d "$IOS_COREDEVICE_ID" \
    --activate \
    -e "$ENV_JSON" \
    --json-output "$LAUNCH_JSON" \
    "$BUNDLE_ID" \
    >/dev/null
fi

echo "Waiting for exports in Documents/TTSEvalExports (timeout=${TIMEOUT_S}s)..."

start_ts="$(date +%s)"
saw_start=0
while true; do
  now_ts="$(date +%s)"
  elapsed="$((now_ts - start_ts))"
  if [ "$elapsed" -ge "$TIMEOUT_S" ]; then
    echo "Timed out waiting for exports after ${TIMEOUT_S}s." >&2
    exit 1
  fi

  # List export directory; if not present yet, devicectl returns "0 files" or error.
  out="$(
    xcrun devicectl device info files \
      -d "$IOS_COREDEVICE_ID" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --subdirectory "Documents/TTSEvalExports" \
      --no-recurse \
      2>&1 || true
  )"

  current_results=()
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    current_results+=("$f")
  done < <(echo "$out" | rg -o 'results-[^[:space:]]+\\.json' | sort -u || true)

  for f in "${current_results[@]-}"; do
    if ! contains "$f" "${existing_results[@]-}"; then
      break 2
    fi
  done

  STATUS_FILE="$(mktemp)"
  if xcrun devicectl device copy from \
    -d "$IOS_COREDEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Documents/TTSEvalExports/autorun-status.txt" \
    --destination "$STATUS_FILE" \
    >/dev/null 2>&1; then
    status_line="$(tail -n 1 "$STATUS_FILE" 2>/dev/null || true)"
    status_line="${status_line//$'\r'/}"
    if [ -n "$status_line" ]; then
      echo "  ${elapsed}s: ${status_line}"
      if echo "$status_line" | rg -q 'starting benchmark'; then
        saw_start=1
      fi
      if [ "$saw_start" -eq 1 ] && echo "$status_line" | rg -q 'done success='; then
        rm -f "$STATUS_FILE"
        break
      fi
    else
      echo "  ${elapsed}s: still running..."
    fi
  else
    echo "  ${elapsed}s: still running..."
  fi
  rm -f "$STATUS_FILE"
  sleep "$POLL_S"
done

DEST_DIR="$REPO_DIR/device-exports/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST_DIR"

echo "Copying exports to: $DEST_DIR"
xcrun devicectl device copy from \
  -d "$IOS_COREDEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "Documents/TTSEvalExports" \
  --destination "$DEST_DIR" \
  >/dev/null

echo "Exports copied:"
ls -la "$DEST_DIR" | sed 's/^/  /'
