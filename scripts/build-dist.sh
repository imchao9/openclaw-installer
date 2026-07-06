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
#
# These packages are intentionally non-secret. Keep private-secrets/ separate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../install-openclaw.sh" ]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT="$SCRIPT_DIR"
fi
SERVE_DIR="${SERVE_DIR:-$ROOT/upload-packages}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.package-build}"
OVERWRITE="${OVERWRITE_DIST:-${OVERWRITE_PACKAGES:-0}}"
PROFILE="${1:-all}"
ZSTD_LEVEL="${ZSTD_LEVEL:--6}"
REFRESH_DOWNLOAD_ASSETS="${REFRESH_DOWNLOAD_ASSETS:-0}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-dist.sh [all|macos26-arm64|macos15-arm64|macos15-x64]

Outputs only these supported archives:
  upload-packages/openclaw-macos26-arm64.tar.zst
  upload-packages/openclaw-macos15-arm64.tar.zst
  upload-packages/openclaw-macos15-x64.tar.zst

Set OVERWRITE_DIST=1 to replace existing package build directories and archives.
Set REFRESH_DOWNLOAD_ASSETS=1 to download public assets before building.
EOF
}

case "$PROFILE" in
  all|macos26-arm64|macos15-arm64|macos15-x64)
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
  esac
}

copy_profile_asset() {
  local profile="$1" asset="$2" dst="$3" src=""
  case "$profile:$asset" in
    macos15-x64:Codex.dmg)
      src="${CODEX_DMG_X64:-/Users/cm/Downloads/Codex-latest-x64.dmg}"
      ;;
    macos15-x64:clash-party-macos-1.9.6-x64.pkg)
      src="${CLASH_PARTY_PKG_X64:-/Users/cm/Downloads/clash-party-macos-1.9.6-x64.pkg}"
      ;;
    *)
      src="$ROOT/openclaw-team/$asset"
      ;;
  esac
  copy_item "$src" "$dst"
}

copy_openclaw_team_assets() {
  local profile="$1" dst="$2" clt
  mkdir -p "$dst"

  local asset
  for asset in \
    "AweSun_v16.5.0.30757_arm64.dmg" \
    "CC-Switch-v3.15.0-macOS.dmg" \
    "Clash Verge 2.5.1.dmg" \
    "DingTalk_v8.3.30-Installer_55620621_arm64.dmg" \
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
    copy_item "$ROOT/openclaw-team/$asset" "$dst/$asset"
  done

  copy_profile_asset "$profile" "Codex.dmg" "$dst/Codex.dmg"
  if [ "$profile" = "macos15-x64" ]; then
    copy_profile_asset "$profile" "clash-party-macos-1.9.6-x64.pkg" "$dst/clash-party-macos-1.9.6-x64.pkg"
  else
    copy_item "$ROOT/openclaw-team/clash-party-macos-1.9.5-arm64.pkg" "$dst/clash-party-macos-1.9.5-arm64.pkg"
  fi

  clt="$(profile_clt_asset "$profile")"
  copy_item "$ROOT/openclaw-team/$clt" "$dst/$clt"

  if [ -f "$ROOT/openclaw-team/openclaw-npm-cache.tgz" ]; then
    copy_item "$ROOT/openclaw-team/openclaw-npm-cache.tgz" "$dst/openclaw-npm-cache.tgz"
  fi
}

copy_cliproxy_bundle() {
  local profile="$1" dst="$2"
  local source_dir="${CLIPROXY_SOURCE_DIR:-/Users/cm/Documents/Me/Tool/cliproxy/CLIProxyAPI}"
  local binary="${CLIPROXY_BINARY:-}"
  if [ -z "$binary" ] && [ "$profile" = "macos15-x64" ]; then
    binary="${CLIPROXY_X64_BINARY:-}"
  fi
  if [ -z "$binary" ]; then
    binary="$source_dir/bin/CLIProxyAPI"
  fi
  if [ -x "$binary" ]; then
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
  local profile="$1" dist="$2" clt
  clt="$(profile_clt_asset "$profile")"
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

- Profile-specific Command Line Tools: \`$clt\`
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

build_profile() {
  local profile="$1"
  local package_name="openclaw-$profile"
  local package_dir="$BUILD_ROOT/$package_name"
  local dist="$package_dir/install-files"
  local archive="$SERVE_DIR/$package_name.tar.zst"
  local checksum="$SERVE_DIR/$package_name.sha256"

  if [ -e "$package_dir" ] || [ -e "$archive" ] || [ -e "$checksum" ]; then
    if [ "$OVERWRITE" != "1" ]; then
      printf 'Package output exists for %s. Re-run with OVERWRITE_DIST=1 to rebuild.\n' "$profile" >&2
      exit 1
    fi
    rm -rf "$package_dir" "$archive" "$checksum"
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

  chmod +x \
    "$package_dir/install-openclaw.sh" \
    "$package_dir/fetch-package-over-http.sh" \
    "$package_dir/serve-package-http.sh" \
    "$dist/install-new-macbook.sh" \
    "$dist/install-openclaw.sh" \
    "$dist/apply-person-key.sh" \
    "$dist/setup-mac-autostart.sh" \
    "$dist/make-package.sh"

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
}

mkdir -p "$BUILD_ROOT" "$SERVE_DIR"

if [ "$REFRESH_DOWNLOAD_ASSETS" = "1" ]; then
  "$ROOT/scripts/refresh-download-assets.sh"
fi

if [ "$PROFILE" = "all" ]; then
  build_profile macos26-arm64
  build_profile macos15-arm64
  build_profile macos15-x64
else
  build_profile "$PROFILE"
fi
