#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Reuse the shared SherpaOnnxKit binary dependencies from the translation repo.
PKG_DIR="$WORKSPACE_ROOT/../ios-android-offline-speech-translation/LocalPackages/SherpaOnnxKit"
MARKER_FILE="$PKG_DIR/.sherpa_ios_deps"

# This app requires Sherpa offline TTS, so we need the full iOS archive variant.
REQUIRED_SUFFIX="ios"
REQUIRED_VERSION="${SHERPA_VERSION:-1.12.23}"

installed_suffix=""
installed_version=""
if [ -f "$MARKER_FILE" ]; then
  installed_version="$(grep -E '^version=' "$MARKER_FILE" | head -n 1 | cut -d= -f2- || true)"
  installed_suffix="$(grep -E '^suffix=' "$MARKER_FILE" | head -n 1 | cut -d= -f2- || true)"
fi

if [ "${FORCE_SHERPA_DEPS:-0}" != "1" ] && \
  [ -d "$PKG_DIR/sherpa-onnx.xcframework" ] && \
  [ -d "$PKG_DIR/onnxruntime.xcframework" ] && \
  [ "$installed_suffix" = "$REQUIRED_SUFFIX" ] && \
  [ "$installed_version" = "$REQUIRED_VERSION" ]; then
  echo "SherpaOnnxKit XCFrameworks already present (version=$installed_version suffix=$installed_suffix); skipping download."
  exit 0
fi

SHERPA_VERSION="$REQUIRED_VERSION" \
SHERPA_IOS_ARCHIVE_SUFFIX="$REQUIRED_SUFFIX" \
  "$WORKSPACE_ROOT/../ios-android-offline-speech-translation/scripts/setup-ios-deps.sh"
