#!/usr/bin/env bash
set -euo pipefail

# Fails fast if an Xcode project is saved with a newer "project file format"
# (objectVersion) than the Xcode version used in CI can understand.
#
# Why: GitHub Actions currently builds with Xcode 15.x. If the project is saved
# with a newer format (e.g. objectVersion 77), CI fails with:
#   "future Xcode project file format"
#
# Usage:
#   scripts/check_xcodeproj_objectversion.sh [path/to/project.pbxproj]
#
# Env:
#   MAX_OBJECT_VERSION (default: 56)

PBXPROJ_PATH="${1:-apps/macos/AIVoiceKeyboard/AIVoiceKeyboard.xcodeproj/project.pbxproj}"
MAX_OBJECT_VERSION="${MAX_OBJECT_VERSION:-56}"

if [[ ! -f "$PBXPROJ_PATH" ]]; then
  echo "ERROR: pbxproj not found: $PBXPROJ_PATH" >&2
  exit 2
fi

line="$(grep -E -m1 '^[[:space:]]*objectVersion[[:space:]]*=[[:space:]]*[0-9]+;' "$PBXPROJ_PATH" || true)"
if [[ -z "$line" ]]; then
  echo "ERROR: Could not find objectVersion in: $PBXPROJ_PATH" >&2
  exit 2
fi

object_version="$(echo "$line" | sed -E 's/.*objectVersion[[:space:]]*=[[:space:]]*([0-9]+);.*/\1/')"
if [[ -z "$object_version" || ! "$object_version" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Failed to parse objectVersion from: $line" >&2
  exit 2
fi

if (( object_version > MAX_OBJECT_VERSION )); then
  echo "ERROR: Xcode project format is too new for CI." >&2
  echo "  pbxproj: $PBXPROJ_PATH" >&2
  echo "  objectVersion: $object_version (max allowed: $MAX_OBJECT_VERSION)" >&2
  echo "" >&2
  echo "Fix options:" >&2
  echo "  1) Open the project with a CI-compatible Xcode (currently Xcode 15.x) and re-save" >&2
  echo "  2) If you know the project didn't actually use new features, you may manually set:" >&2
  echo "     objectVersion = $MAX_OBJECT_VERSION;" >&2
  exit 1
fi

echo "OK: objectVersion=$object_version (max allowed: $MAX_OBJECT_VERSION) — $PBXPROJ_PATH"

