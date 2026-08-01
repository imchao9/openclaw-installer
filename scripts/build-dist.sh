#!/usr/bin/env bash
# Build profile-specific OpenClaw installer archives.
#
# Default output:
#   upload-packages/openclaw-macos26-arm64.tar.zst
#   upload-packages/openclaw-macos26-arm64.sha256
#   upload-packages/openclaw-macos15-arm64.tar.zst
#   upload-packages/openclaw-macos15-arm64.sha256
#   upload-packages/openclaw-macos15-x64.tar.zst
#   upload-packages/openclaw-macos15-x64.sha256
#   upload-packages/openclaw-macos14-x64.tar.zst
#   upload-packages/openclaw-macos14-x64.sha256
#
# These packages are intentionally non-secret. Keep private-secrets/ separate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../install-openclaw.sh" ]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT="$SCRIPT_DIR"
fi
source "$ROOT/scripts/lib/source-assets.sh"
SERVE_DIR="${SERVE_DIR:-$ROOT/upload-packages}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.package-build}"
BUILD_CACHE_ROOT="${BUILD_CACHE_ROOT:-$ROOT/.build-cache}"
OVERWRITE="${OVERWRITE_DIST:-${OVERWRITE_PACKAGES:-0}}"
PROFILE="${1:-all}"
ZSTD_LEVEL="${ZSTD_LEVEL:--6}"
REFRESH_DOWNLOAD_ASSETS="${REFRESH_DOWNLOAD_ASSETS:-0}"
SKIP_STANDALONE_ARCHIVE="${SKIP_STANDALONE_ARCHIVE:-0}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-dist.sh [all|macos26-arm64|macos15-arm64|macos15-x64|macos14-x64]

Outputs only these supported archives:
  upload-packages/openclaw-macos26-arm64.tar.zst
  upload-packages/openclaw-macos15-arm64.tar.zst
  upload-packages/openclaw-macos15-x64.tar.zst
  upload-packages/openclaw-macos14-x64.tar.zst

Set OVERWRITE_DIST=1 to replace existing package build directories and archives.
Set REFRESH_DOWNLOAD_ASSETS=1 to download public assets before building.
EOF
}

case "$PROFILE" in
  all|macos26-arm64|macos15-arm64|macos15-x64|macos14-x64)
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

copy_item() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    printf '[WARN] Missing asset: %s\n' "$src" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  if cp -cR "$src" "$dst" 2>/dev/null; then
    return
  fi
  cp -R "$src" "$dst"
}

copy_clean_dir() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  (
    cd "$src"
    find . \
      -name '.DS_Store' -prune -o \
      -name 'openclaw-team.zip' -prune -o \
      -name 'openclaw team.zip' -prune -o \
      -name 'setup 3.zip' -prune -o \
      -name 'install-new-macbook.log' -prune -o \
      -path './dotfiles/.codex/auth.json' -prune -o \
      -path './dotfiles/.codex/config.toml' -prune -o \
      -path './dotfiles/.claude/settings.json' -prune -o \
      -path './dotfiles/.openclaw/openclaw.json' -prune -o \
      -name 'secrets.env' -prune -o \
      -name 'auth.json' -prune -o \
      -name 'config.toml' -prune -o \
      -name 'openclaw.json' -prune -o \
      -name 'key.txt' -prune -o \
      -name '安装.txt' -prune -o \
      -print
  ) | while IFS= read -r rel; do
    [ "$rel" = "." ] && continue
    rel="${rel#./}"
    if [ -d "$src/$rel" ]; then
      mkdir -p "$dst/$rel"
    elif [ -f "$src/$rel" ] || [ -L "$src/$rel" ]; then
      copy_item "$src/$rel" "$dst/$rel"
    fi
  done
}

profile_clt_asset() {
  case "$1" in
    macos26-arm64)
      printf '%s\n' "Command_Line_Tools_26.5_Apple_silicon.dmg"
      ;;
    macos15-arm64)
      printf '%s\n' "Command_Line_Tools_for_Xcode_16.4.dmg"
      ;;
    macos15-x64)
      printf '%s\n' "Command_Line_Tools_for_Xcode_16.4.dmg"
      ;;
    macos14-x64)
      printf '%s\n' ""
      ;;
  esac
}

profile_description() {
  case "$1" in
    macos26-arm64)
      printf '%s\n' "Apple Silicon targets on macOS 26.2+"
      ;;
    macos15-arm64)
      printf '%s\n' "Apple Silicon targets on macOS 15.x or compatible older setup flow"
      ;;
    macos15-x64)
      printf '%s\n' "Intel targets on macOS 15.x"
      ;;
    macos14-x64)
      printf '%s\n' "Intel targets on macOS 14.x with Command Line Tools already installed"
      ;;
  esac
}

profile_arch() {
  case "$1" in
    macos14-x64|macos15-x64) printf '%s\n' x86_64 ;;
    macos15-arm64|macos26-arm64) printf '%s\n' arm64 ;;
  esac
}

copy_profile_asset() {
  local profile="$1" asset="$2" dst="$3" src=""
  case "$profile:$asset" in
    macos14-x64:Codex.dmg|macos15-x64:Codex.dmg)
      src="${CODEX_DMG_X64:-$(asset_source_path Codex-intel.dmg)}"
      ;;
    macos14-x64:clash-party-macos-1.9.6-x64.pkg|macos15-x64:clash-party-macos-1.9.6-x64.pkg)
      src="${CLASH_PARTY_PKG_X64:-$(asset_source_path clash-party-macos-1.9.6-x64.pkg)}"
      ;;
    macos14-x64:DingTalk-universal.dmg|macos15-x64:DingTalk-universal.dmg)
      src="${DINGTALK_DMG_X64:-$(asset_source_path DingTalk_v8.3.40-Installer_56018405_universal.dmg)}"
      ;;
    *)
      src="$(asset_source_path "$asset")"
      ;;
  esac
  copy_item "$src" "$dst"
}

copy_openclaw_team_assets() {
  local profile="$1" dst="$2" clt
  mkdir -p "$dst"

  local asset
  for asset in \
    "CC-Switch-v3.15.0-macOS.dmg" \
    "Homebrew.pkg" \
    "Obsidian-1.12.7.dmg" \
    "OpenClaw Dashboard.app" \
    "OpenClaw Weixin Connect.app" \
    "OpenClaw-2026.5.26.dmg" \
    "fix-openclaw-install.sh" \
    "googlechrome.dmg" \
    "node-v24.16.0.pkg" \
    "setup-openclaw-weixin.sh" \
    "disable-sleep-note.txt"; do
    copy_item "$(asset_source_path "$asset")" "$dst/$asset"
  done

  copy_profile_asset "$profile" "Codex.dmg" "$dst/Codex.dmg"
  if [[ "$profile" == macos*-x64 ]]; then
    copy_profile_asset "$profile" "clash-party-macos-1.9.6-x64.pkg" "$dst/clash-party-macos-1.9.6-x64.pkg"
    copy_profile_asset "$profile" "DingTalk-universal.dmg" "$dst/DingTalk_v8.3.40-Installer_56018405_universal.dmg"
  else
    copy_item "$(asset_source_path AweSun_v16.5.0.30757_arm64.dmg)" "$dst/AweSun_v16.5.0.30757_arm64.dmg"
    copy_item "$(asset_source_path 'Clash Verge 2.5.1.dmg')" "$dst/Clash Verge 2.5.1.dmg"
    copy_item "$(asset_source_path clash-party-macos-1.9.5-arm64.pkg)" "$dst/clash-party-macos-1.9.5-arm64.pkg"
    copy_item "$(asset_source_path DingTalk_v8.3.30-Installer_55620621_arm64.dmg)" "$dst/DingTalk_v8.3.30-Installer_55620621_arm64.dmg"
  fi

  clt="$(profile_clt_asset "$profile")"
  if [ -n "$clt" ]; then
    copy_item "$(asset_source_path "$clt")" "$dst/$clt"
  fi

  if npm_cache="$(asset_source_path openclaw-npm-cache.tgz)"; then
    copy_item "$npm_cache" "$dst/openclaw-npm-cache.tgz"
  fi
}

copy_cliproxy_bundle() {
  local profile="$1" dst="$2"
  local source_dir="${CLIPROXY_SOURCE_DIR:-/Users/cm/Documents/Me/Tool/cliproxy/CLIProxyAPI}"
  local binary="${CLIPROXY_BINARY:-}" expected_arch
  expected_arch="$(profile_arch "$profile")"
  if [[ "$profile" == macos*-x64 ]]; then
    binary="${CLIPROXY_X64_BINARY:-${binary:-$BUILD_CACHE_ROOT/CLIProxyAPI-darwin-amd64}}"
    if [ ! -x "$binary" ]; then
      command -v go >/dev/null 2>&1 || {
        printf '[ERROR] Go is required to build the Intel CLIProxyAPI binary.\n' >&2
        return 1
      }
      mkdir -p "$(dirname "$binary")"
      printf 'Building CLIProxyAPI for darwin/amd64 from %s\n' "$source_dir"
      (
        cd "$source_dir"
        env GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -o "$binary" ./cmd/server
      )
    fi
  elif [ -z "$binary" ]; then
    binary="$source_dir/bin/CLIProxyAPI"
  fi
  if [ -x "$binary" ]; then
    if command -v lipo >/dev/null 2>&1 && ! lipo -archs "$binary" | tr ' ' '\n' | grep -qx "$expected_arch"; then
      printf '[ERROR] CLIProxyAPI architecture mismatch: expected %s, got %s (%s)\n' \
        "$expected_arch" "$(lipo -archs "$binary" 2>/dev/null || printf unknown)" "$binary" >&2
      return 1
    fi
    mkdir -p "$dst/cliproxy"
    copy_item "$binary" "$dst/cliproxy/CLIProxyAPI"
    if [ -d "$source_dir/bin/static" ]; then
      copy_clean_dir "$source_dir/bin/static" "$dst/cliproxy/static"
    fi
    cat > "$dst/cliproxy/config.yaml.example" <<'EOF'
host: "127.0.0.1"
port: 8317
auth-dir: "~/.cli-proxy-api"
api-keys:
  - open-api
debug: false
logging-to-file: true
EOF
  else
    printf '[WARN] CLIProxyAPI binary not found at %s; skipping cliproxy runtime bundle.\n' "$binary" >&2
  fi
}

write_manifest() {
  local profile="$1" dist="$2" clt clt_display
  clt="$(profile_clt_asset "$profile")"
  clt_display="${clt:-preinstalled; not bundled}"
  cat > "$dist/DIST_MANIFEST.md" <<EOF
# Dist Manifest

Profile: \`$profile\`
Target: $(profile_description "$profile")

## Install flow

After extracting the archive, run from the extracted package root:

\`\`\`bash
bash install-openclaw.sh --with-cliproxy-config
\`\`\`

The wrapper auto-detects \`install-files/\`, runs base install, restores \`private-secrets/\`
when provided next to \`install-files/\`, configures CLIProxyAPI when requested, and runs
validation.

## Included assets

- Profile-specific Command Line Tools: \`$clt_display\`
- Node.js PKG
- Google Chrome DMG
- Profile-specific Codex DMG and Codex.app bundled CLI
- OpenClaw DMG and OpenClaw CLI/Gateway repair
- Optional offline npm cache for OpenClaw CLI install, when \`openclaw-npm-cache.tgz\` is present
- Obsidian DMG
- CC-Switch DMG
- AweSun DMG
- DingTalk DMG
- Doubao input method is not bundled; install it manually if needed
- Clash Verge DMG
- Clash Party PKG
- CLIProxyAPI binary and non-secret example config
- Non-secret OpenClaw/Codex/media setup files
- Install checkpoint scanner and validation scripts

## Excluded assets

- Universal Command Line Tools
- Command Line Tools for other profile families
- \`private-secrets/\`
- auth/config/key files

## Codex CLI policy

The base phase now prefers the Codex CLI bundled in \`Codex.app\`. It falls back
to \`npm install -g @openai/codex\` only if no usable \`codex\` command exists
after app installation.
EOF
}

write_machine_manifest() {
  local profile="$1" dist="$2" arch clt clash dingtalk
  arch="$(profile_arch "$profile")"
  clt="$(profile_clt_asset "$profile")"
  if [[ "$profile" == macos*-x64 ]]; then
    clash="openclaw-team/clash-party-macos-1.9.6-x64.pkg"
    dingtalk="openclaw-team/DingTalk_v8.3.40-Installer_56018405_universal.dmg"
  else
    clash="openclaw-team/clash-party-macos-1.9.5-arm64.pkg"
    dingtalk="openclaw-team/DingTalk_v8.3.30-Installer_55620621_arm64.dmg"
  fi

  MANIFEST_PROFILE="$profile" \
  MANIFEST_ARCH="$arch" \
  MANIFEST_CLT="${clt:+openclaw-team/$clt}" \
  MANIFEST_CLASH="$clash" \
  MANIFEST_DINGTALK="$dingtalk" \
  /usr/bin/python3 - "$dist" <<'PY'
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
required = [
    "openclaw-team/Codex.dmg",
    "openclaw-team/OpenClaw-2026.5.26.dmg",
    "openclaw-team/node-v24.16.0.pkg",
    "openclaw-team/cliproxy/CLIProxyAPI",
    os.environ["MANIFEST_CLASH"],
    os.environ["MANIFEST_DINGTALK"],
]
if os.environ.get("MANIFEST_CLT"):
    required.append(os.environ["MANIFEST_CLT"])
assets = []
for relative in required:
    path = root / relative
    if not path.is_file():
        raise SystemExit(f"Required profile asset is missing: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    assets.append({"path": relative, "size_bytes": path.stat().st_size, "sha256": digest.hexdigest()})

manifest = {
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "profile": os.environ["MANIFEST_PROFILE"],
    "target_arch": os.environ["MANIFEST_ARCH"],
    "required_assets": assets,
    "app_mappings": [
        {"asset": "openclaw-team/Codex.dmg", "source_bundle": "ChatGPT.app", "target_bundle": "Codex.app"},
        {"asset": "openclaw-team/OpenClaw-2026.5.26.dmg", "source_bundle": "OpenClaw.app", "target_bundle": "OpenClaw.app"},
    ],
}
(root / "DIST_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
}

build_profile() {
  local profile="$1"
  local package_name="openclaw-$profile"
  local package_dir="$BUILD_ROOT/$package_name"
  local dist="$package_dir/install-files"
  local archive="$SERVE_DIR/$package_name.tar.zst"
  local checksum="$SERVE_DIR/$package_name.sha256"

  if [ -e "$package_dir" ] ||
    { [ "$SKIP_STANDALONE_ARCHIVE" != "1" ] && { [ -e "$archive" ] || [ -e "$checksum" ]; }; }; then
    if [ "$OVERWRITE" != "1" ]; then
      printf 'Package output exists for %s. Re-run with OVERWRITE_DIST=1 to rebuild.\n' "$profile" >&2
      exit 1
    fi
    rm -rf "$package_dir"
    if [ "$SKIP_STANDALONE_ARCHIVE" != "1" ]; then
      rm -f "$archive" "$checksum"
    fi
  fi

  mkdir -p "$dist" "$SERVE_DIR"

  copy_item "$ROOT/install-openclaw.sh" "$package_dir/install-openclaw.sh"
  copy_item "$ROOT/AGENTS.md" "$package_dir/AGENTS.md"
  copy_item "$ROOT/scripts/fetch-package-over-http.sh" "$package_dir/fetch-package-over-http.sh"
  copy_item "$ROOT/scripts/serve-package-http.sh" "$package_dir/serve-package-http.sh"
  copy_item "$ROOT/install-new-macbook.sh" "$dist/install-new-macbook.sh"
  copy_item "$ROOT/install-openclaw.sh" "$dist/install-openclaw.sh"
  copy_item "$ROOT/scripts/apply-person-key.sh" "$dist/apply-person-key.sh"
  copy_item "$ROOT/scripts/setup-mac-autostart.sh" "$dist/setup-mac-autostart.sh"
  copy_item "$ROOT/scripts/make-package.sh" "$dist/make-package.sh"
  copy_item "$ROOT/README.md" "$dist/README.md"
  perl -0pi -e 's#bash scripts/(apply-person-key|make-package|setup-mac-autostart)\\.sh#bash $1.sh#g; s#`scripts/(apply-person-key|make-package|setup-mac-autostart)\\.sh`#`$1.sh`#g; s#bash scripts/build-dist\\.sh#bash build-dist.sh#g; s#`scripts/build-dist\\.sh`#`build-dist.sh`#g' "$dist/README.md"
  copy_item "$ROOT/docs/NEW_MACBOOK_SETUP.md" "$dist/NEW_MACBOOK_SETUP.md"
  copy_item "$ROOT/docs/MAC_AUTOSTART.md" "$dist/MAC_AUTOSTART.md"
  if [ -f "$ROOT/docs/openclaw-install-without-ai.md" ]; then
    copy_item "$ROOT/docs/openclaw-install-without-ai.md" "$dist/docs/openclaw-install-without-ai.md"
  fi
  if [ -f "$ROOT/docs/user-install-guide.md" ]; then
    copy_item "$ROOT/docs/user-install-guide.md" "$dist/docs/user-install-guide.md"
  fi
  if [ -f "$ROOT/docs/user-install-guide.pdf" ]; then
    copy_item "$ROOT/docs/user-install-guide.pdf" "$dist/docs/user-install-guide.pdf"
  fi
  if [ -f "$ROOT/docs/download-sources.md" ]; then
    copy_item "$ROOT/docs/download-sources.md" "$dist/docs/download-sources.md"
  fi
  if [ -f "$ROOT/docs/download-sources.pdf" ]; then
    copy_item "$ROOT/docs/download-sources.pdf" "$dist/docs/download-sources.pdf"
  fi
  if [ -f "$ROOT/docs/openclaw-install-without-ai.pdf" ]; then
    copy_item "$ROOT/docs/openclaw-install-without-ai.pdf" "$dist/docs/openclaw-install-without-ai.pdf"
  elif [ -f "$ROOT/output/pdf/openclaw-install-without-ai.pdf" ]; then
    copy_item "$ROOT/output/pdf/openclaw-install-without-ai.pdf" "$dist/docs/openclaw-install-without-ai.pdf"
  fi
  copy_clean_dir "$ROOT/installer-core" "$dist/installer-core"
  copy_openclaw_team_assets "$profile" "$dist/openclaw-team"
  copy_cliproxy_bundle "$profile" "$dist/openclaw-team"
  write_manifest "$profile" "$dist"
  write_machine_manifest "$profile" "$dist"

  chmod +x \
    "$package_dir/install-openclaw.sh" \
    "$package_dir/fetch-package-over-http.sh" \
    "$package_dir/serve-package-http.sh" \
    "$dist/install-new-macbook.sh" \
    "$dist/install-openclaw.sh" \
    "$dist/apply-person-key.sh" \
    "$dist/setup-mac-autostart.sh" \
    "$dist/make-package.sh"

  if [ "$SKIP_STANDALONE_ARCHIVE" = "1" ]; then
    printf 'Built staging only: %s\n' "$package_dir"
  else
    (
      cd "$BUILD_ROOT"
      tar -cf - "$package_name" | zstd -T0 "$ZSTD_LEVEL" -q -o "$archive"
    )
    (
      cd "$SERVE_DIR"
      shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
    )

    printf 'Built %s\n' "$archive"
    printf 'Checksum %s\n' "$checksum"
  fi
}

mkdir -p "$BUILD_ROOT" "$SERVE_DIR"

if [ "$REFRESH_DOWNLOAD_ASSETS" = "1" ]; then
  "$ROOT/scripts/refresh-download-assets.sh"
fi

if [ "$PROFILE" = "all" ]; then
  build_profile macos26-arm64
  build_profile macos15-arm64
  build_profile macos15-x64
  build_profile macos14-x64
else
  build_profile "$PROFILE"
fi
