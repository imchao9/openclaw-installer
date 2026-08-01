#!/usr/bin/env bash
# Shared resolver for ignored, large offline installer assets.
# Lightweight scripts and app launchers remain under openclaw-team/ in Git.

SOURCE_ASSETS_DIR="${OPENCLAW_ASSET_SOURCE_DIR:-$ROOT/upload-packages/source-assets/openclaw-team}"
LEGACY_SOURCE_ASSETS_DIR="$ROOT/openclaw-team"

asset_source_path() {
  local relative_path="$1"
  if [ -e "$SOURCE_ASSETS_DIR/$relative_path" ]; then
    printf '%s\n' "$SOURCE_ASSETS_DIR/$relative_path"
    return 0
  fi
  if [ -e "$LEGACY_SOURCE_ASSETS_DIR/$relative_path" ]; then
    printf '%s\n' "$LEGACY_SOURCE_ASSETS_DIR/$relative_path"
    return 0
  fi
  printf '%s\n' "$SOURCE_ASSETS_DIR/$relative_path"
  return 1
}
