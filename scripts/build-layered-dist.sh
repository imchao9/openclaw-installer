#!/usr/bin/env bash
# Build deduplicated OpenClaw delivery layers and a profile composition index.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT/scripts/lib/source-assets.sh"
SERVE_DIR="${SERVE_DIR:-$ROOT/upload-packages}"
LAYER_BUILD_ROOT="${LAYER_BUILD_ROOT:-$ROOT/.layer-build}"
PROFILE_BUILD_ROOT="${BUILD_ROOT:-$ROOT/.package-build}"
OVERWRITE="${OVERWRITE_LAYERED_DIST:-0}"
ZSTD_LEVEL="${ZSTD_LEVEL:--6}"
CLIPROXY_SOURCE_DIR="${CLIPROXY_SOURCE_DIR:-/Users/cm/Documents/Me/Tool/cliproxy/CLIProxyAPI}"

case "$LAYER_BUILD_ROOT" in
  ''|/|"$ROOT")
    echo "Unsafe LAYER_BUILD_ROOT: $LAYER_BUILD_ROOT" >&2
    exit 2
    ;;
esac

for command_name in tar zstd shasum lipo; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

layer_ids=(
  common
  x64-common
  arm64-common
  macos15-clt
  macos26-arm64-clt
)

layer_archive_name() {
  case "$1" in
    common) printf '%s\n' openclaw-common.tar.zst ;;
    x64-common) printf '%s\n' openclaw-x64-common.tar.zst ;;
    arm64-common) printf '%s\n' openclaw-arm64-common.tar.zst ;;
    macos15-clt) printf '%s\n' openclaw-macos15-clt.tar.zst ;;
    macos26-arm64-clt) printf '%s\n' openclaw-macos26-arm64-clt.tar.zst ;;
  esac
}

copy_item() {
  local src="$1" dst="$2"
  [ -e "$src" ] || {
    echo "Missing layered source asset: $src" >&2
    exit 1
  }
  mkdir -p "$(dirname "$dst")"
  if cp -cR "$src" "$dst" 2>/dev/null; then
    return
  fi
  cp -R "$src" "$dst"
}

for layer_id in "${layer_ids[@]}"; do
  archive="$SERVE_DIR/$(layer_archive_name "$layer_id")"
  checksum="${archive%.tar.zst}.sha256"
  if { [ -e "$archive" ] || [ -e "$checksum" ]; } && [ "$OVERWRITE" != "1" ]; then
    echo "Layer output exists; set OVERWRITE_LAYERED_DIST=1: $archive" >&2
    exit 1
  fi
done
if { [ -e "$SERVE_DIR/openclaw-layer-index.json" ] ||
  [ -e "$SERVE_DIR/openclaw-layer-index.sha256" ]; } && [ "$OVERWRITE" != "1" ]; then
  echo "Layer index exists; set OVERWRITE_LAYERED_DIST=1" >&2
  exit 1
fi

rm -rf "$LAYER_BUILD_ROOT"
mkdir -p "$LAYER_BUILD_ROOT" "$SERVE_DIR"
if [ "$OVERWRITE" = "1" ]; then
  for layer_id in "${layer_ids[@]}"; do
    archive="$SERVE_DIR/$(layer_archive_name "$layer_id")"
    rm -f "$archive" "${archive%.tar.zst}.sha256"
  done
  rm -f "$SERVE_DIR/openclaw-layer-index.json" "$SERVE_DIR/openclaw-layer-index.sha256"
fi

echo "Building representative macos14-x64 staging without a standalone archive"
BUILD_ROOT="$PROFILE_BUILD_ROOT" \
  OVERWRITE_DIST=1 \
  SKIP_STANDALONE_ARCHIVE=1 \
  bash "$ROOT/scripts/build-dist.sh" macos14-x64

profile_root="$PROFILE_BUILD_ROOT/openclaw-macos14-x64"
[ -d "$profile_root/install-files/openclaw-team" ] || {
  echo "Representative profile staging was not built: $profile_root" >&2
  exit 1
}

common_root="$LAYER_BUILD_ROOT/common/openclaw-layered"
mkdir -p "$common_root"
if ! cp -cR "$profile_root/." "$common_root/" 2>/dev/null; then
  cp -R "$profile_root/." "$common_root/"
fi
rm -rf \
  "$common_root/install-files/openclaw-team/Codex.dmg" \
  "$common_root/install-files/openclaw-team/clash-party-macos-1.9.6-x64.pkg" \
  "$common_root/install-files/openclaw-team/DingTalk_v8.3.40-Installer_56018405_universal.dmg" \
  "$common_root/install-files/openclaw-team/cliproxy"
rm -f \
  "$common_root/install-files/DIST_MANIFEST.json" \
  "$common_root/install-files/DIST_MANIFEST.md"

x64_team="$LAYER_BUILD_ROOT/x64-common/openclaw-layered/install-files/openclaw-team"
copy_item "$(asset_source_path Codex-intel.dmg)" "$x64_team/Codex.dmg"
copy_item "$(asset_source_path clash-party-macos-1.9.6-x64.pkg)" \
  "$x64_team/clash-party-macos-1.9.6-x64.pkg"
copy_item "$(asset_source_path DingTalk_v8.3.40-Installer_56018405_universal.dmg)" \
  "$x64_team/DingTalk_v8.3.40-Installer_56018405_universal.dmg"
copy_item "$profile_root/install-files/openclaw-team/cliproxy" "$x64_team/cliproxy"
lipo -archs "$x64_team/cliproxy/CLIProxyAPI" | tr ' ' '\n' | grep -qx x86_64 || {
  echo "x64 common layer contains a non-x86_64 CLIProxyAPI" >&2
  exit 1
}

arm_team="$LAYER_BUILD_ROOT/arm64-common/openclaw-layered/install-files/openclaw-team"
copy_item "$(asset_source_path Codex.dmg)" "$arm_team/Codex.dmg"
copy_item "$(asset_source_path AweSun_v16.5.0.30757_arm64.dmg)" \
  "$arm_team/AweSun_v16.5.0.30757_arm64.dmg"
copy_item "$(asset_source_path 'Clash Verge 2.5.1.dmg')" "$arm_team/Clash Verge 2.5.1.dmg"
copy_item "$(asset_source_path clash-party-macos-1.9.5-arm64.pkg)" \
  "$arm_team/clash-party-macos-1.9.5-arm64.pkg"
copy_item "$(asset_source_path DingTalk_v8.3.30-Installer_55620621_arm64.dmg)" \
  "$arm_team/DingTalk_v8.3.30-Installer_55620621_arm64.dmg"
copy_item "$profile_root/install-files/openclaw-team/cliproxy" "$arm_team/cliproxy"
copy_item "$CLIPROXY_SOURCE_DIR/bin/CLIProxyAPI" \
  "$arm_team/cliproxy/CLIProxyAPI"
lipo -archs "$arm_team/cliproxy/CLIProxyAPI" | tr ' ' '\n' | grep -qx arm64 || {
  echo "arm64 common layer contains a non-arm64 CLIProxyAPI" >&2
  exit 1
}

copy_item "$(asset_source_path Command_Line_Tools_for_Xcode_16.4.dmg)" \
  "$LAYER_BUILD_ROOT/macos15-clt/openclaw-layered/install-files/openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg"
copy_item "$(asset_source_path Command_Line_Tools_26.5_Apple_silicon.dmg)" \
  "$LAYER_BUILD_ROOT/macos26-arm64-clt/openclaw-layered/install-files/openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg"

for layer_id in "${layer_ids[@]}"; do
  archive="$SERVE_DIR/$(layer_archive_name "$layer_id")"
  echo "Building layer $layer_id -> $archive"
  (
    cd "$LAYER_BUILD_ROOT/$layer_id"
    tar -cf - openclaw-layered | zstd -T0 "$ZSTD_LEVEL" -q -o "$archive"
  )
  (
    cd "$SERVE_DIR"
    shasum -a 256 "$(basename "$archive")" > "$(basename "${archive%.tar.zst}.sha256")"
  )
done

/usr/bin/python3 - "$LAYER_BUILD_ROOT" "$SERVE_DIR" <<'PY'
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

build_root = Path(sys.argv[1])
serve_dir = Path(sys.argv[2])
layer_files = {
    "common": "openclaw-common.tar.zst",
    "x64-common": "openclaw-x64-common.tar.zst",
    "arm64-common": "openclaw-arm64-common.tar.zst",
    "macos15-clt": "openclaw-macos15-clt.tar.zst",
    "macos26-arm64-clt": "openclaw-macos26-arm64-clt.tar.zst",
}
profile_layers = {
    "macos14-x64": ["common", "x64-common"],
    "macos15-x64": ["common", "x64-common", "macos15-clt"],
    "macos15-arm64": ["common", "arm64-common", "macos15-clt"],
    "macos26-arm64": ["common", "arm64-common", "macos26-arm64-clt"],
}
profile_arch = {
    "macos14-x64": "x86_64",
    "macos15-x64": "x86_64",
    "macos15-arm64": "arm64",
    "macos26-arm64": "arm64",
}

def file_digest(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

layers = {}
for layer_id, filename in layer_files.items():
    archive = serve_dir / filename
    layers[layer_id] = {
        "file": filename,
        "size_bytes": archive.stat().st_size,
        "sha256": file_digest(archive),
    }

def resolve_asset(layer_ids, relative):
    for layer_id in reversed(layer_ids):
        candidate = build_root / layer_id / "openclaw-layered" / "install-files" / relative
        if candidate.is_file():
            return candidate
    raise SystemExit(f"asset not found in profile layers: {relative}")

profiles = {}
for profile, layer_ids in profile_layers.items():
    is_x64 = profile.endswith("-x64")
    clash = (
        "openclaw-team/clash-party-macos-1.9.6-x64.pkg"
        if is_x64
        else "openclaw-team/clash-party-macos-1.9.5-arm64.pkg"
    )
    dingtalk = (
        "openclaw-team/DingTalk_v8.3.40-Installer_56018405_universal.dmg"
        if is_x64
        else "openclaw-team/DingTalk_v8.3.30-Installer_55620621_arm64.dmg"
    )
    required = [
        "openclaw-team/Codex.dmg",
        "openclaw-team/OpenClaw-2026.5.26.dmg",
        "openclaw-team/node-v24.16.0.pkg",
        "openclaw-team/cliproxy/CLIProxyAPI",
        clash,
        dingtalk,
    ]
    if profile.startswith("macos15-"):
        required.append("openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg")
    elif profile == "macos26-arm64":
        required.append("openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg")
    assets = []
    for relative in required:
        path = resolve_asset(layer_ids, relative)
        assets.append(
            {
                "path": relative,
                "size_bytes": path.stat().st_size,
                "sha256": file_digest(path),
            }
        )
    manifest = {
        "schema_version": 2,
        "generated_at": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "profile": profile,
        "target_arch": profile_arch[profile],
        "layers": layer_ids,
        "required_assets": assets,
        "app_mappings": [
            {
                "asset": "openclaw-team/Codex.dmg",
                "source_bundle": "ChatGPT.app",
                "target_bundle": "Codex.app",
            },
            {
                "asset": "openclaw-team/OpenClaw-2026.5.26.dmg",
                "source_bundle": "OpenClaw.app",
                "target_bundle": "OpenClaw.app",
            },
        ],
    }
    profiles[profile] = {
        "target_arch": profile_arch[profile],
        "layers": layer_ids,
        "dist_manifest": manifest,
    }

index = {
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc)
    .replace(microsecond=0)
    .isoformat()
    .replace("+00:00", "Z"),
    "layers": layers,
    "profiles": profiles,
}
(serve_dir / "openclaw-layer-index.json").write_text(json.dumps(index, indent=2) + "\n")
PY

(
  cd "$SERVE_DIR"
  shasum -a 256 openclaw-layer-index.json > openclaw-layer-index.sha256
)

printf 'Built layered package index: %s\n' "$SERVE_DIR/openclaw-layer-index.json"
printf 'Assemble with: bash scripts/assemble-layered-package.sh --profile macos14-x64 --output-dir /tmp/openclaw-macos14-x64\n'
