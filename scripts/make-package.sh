#!/usr/bin/env bash
# Build a transfer zip for a new MacBook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../install-openclaw.sh" ] && { [ -d "$SCRIPT_DIR/../install-files" ] || [ -d "$SCRIPT_DIR/../dist" ]; }; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi
PACKAGE_PROFILE="${PACKAGE_PROFILE:-full}"
if [ -f "$PROJECT_ROOT/DIST_MANIFEST.md" ]; then
  PACKAGE_DIR="$PROJECT_ROOT"
elif [ -d "$PROJECT_ROOT/install-files" ]; then
  PACKAGE_DIR="$PROJECT_ROOT/install-files"
elif [ -d "$PROJECT_ROOT/dist" ]; then
  PACKAGE_DIR="$PROJECT_ROOT/dist"
else
  PACKAGE_DIR="$PROJECT_ROOT"
fi

usage() {
  cat <<'EOF'
Usage:
  bash scripts/make-package.sh [output.zip]

Environment:
  PACKAGE_PROFILE=full         Include all non-secret assets. Default.
  PACKAGE_PROFILE=core         Exclude extras apps, keep both CLT profiles.
  PACKAGE_PROFILE=core-macos15 Exclude extras apps and macOS 26 CLT.
  PACKAGE_PROFILE=core-macos26 Exclude extras apps and macOS 15 CLT.

Examples:
  PACKAGE_PROFILE=core-macos15 bash scripts/make-package.sh upload-packages/openclaw-core-macos15.zip
  PACKAGE_PROFILE=core-macos26 bash scripts/make-package.sh upload-packages/openclaw-core-macos26.zip
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

NAME="$(basename "$PACKAGE_DIR")"
PARENT="$(dirname "$PACKAGE_DIR")"
DEFAULT_OUT_DIR="$PROJECT_ROOT/upload-packages"
OUT="${1:-$DEFAULT_OUT_DIR/${NAME}-${PACKAGE_PROFILE}-new-macbook-$(date +%Y%m%d_%H%M%S).zip}"

case "$PACKAGE_PROFILE" in
  full|core|core-macos15|core-macos26)
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

case "$OUT" in
  /*) ;;
  *) OUT="$PWD/$OUT" ;;
esac

mkdir -p "$(dirname "$OUT")"

TMP_OUT="$(mktemp "${TMPDIR:-/tmp}/openclaw-package.XXXXXX.zip")"
cleanup_tmp() {
  rm -f "$TMP_OUT"
}
trap cleanup_tmp EXIT
rm -f "$TMP_OUT"

exclude_args=(
  -x "$NAME/.DS_Store"
  -x "$NAME/*/.DS_Store"
  -x "$NAME/*/*/.DS_Store"
  -x "$NAME/**/*.DS_Store"
  -x "$NAME/__MACOSX/*"
  -x "$NAME/__MACOSX/**"
  -x "$NAME/private-secrets/*"
  -x "$NAME/private-secrets/**"
  -x "$NAME/.server/*"
  -x "$NAME/.server/**"
  -x "$NAME/http-server.pid"
  -x "$NAME/install-new-macbook.log"
  -x "$NAME/*.log"
  -x "$NAME/**/*.log"
  -x "$NAME/openclaw-team.zip"
  -x "$NAME/openclaw team.zip"
  -x "$NAME/setup 3.zip"
  -x "$NAME/openclaw.zip"
  -x "$NAME/serve/*.zip"
  -x "$NAME/serve/**/*.zip"
  -x "$NAME/upload-packages/*.zip"
  -x "$NAME/upload-packages/**/*.zip"
  -x "$NAME/install-files/*.zip"
  -x "$NAME/install-files/**/*.zip"
  -x "$NAME/dist/*.zip"
  -x "$NAME/dist/**/*.zip"
  -x "$NAME/key.csv"
  -x "$NAME/**/key.csv"
  -x "$NAME/deepseek-key.csv"
  -x "$NAME/deepseek-key.xlsx"
  -x "$NAME/**/deepseek-key.csv"
  -x "$NAME/**/deepseek-key.xlsx"
  -x "$NAME/**/secrets.env"
  -x "$NAME/**/auth.json"
  -x "$NAME/**/config.toml"
  -x "$NAME/**/openclaw.json"
  -x "$NAME/**/key.txt"
  -x "$NAME/**/安装.txt"
)

add_core_excludes() {
  exclude_args+=(
    -x "$NAME/openclaw-team/googlechrome.dmg"
    -x "$NAME/openclaw-team/Obsidian-1.12.7.dmg"
    -x "$NAME/openclaw-team/DingTalk_v8.3.30-Installer_55620621_arm64.dmg"
    -x "$NAME/openclaw-team/DoubaoImeInstaller_v0.9.1.app/*"
    -x "$NAME/openclaw-team/DoubaoImeInstaller_v0.9.1.app/**"
    -x "$NAME/openclaw-team/AweSun_v16.5.0.30757_arm64.dmg"
    -x "$NAME/openclaw-team/AweSun_v16.5.0.30905_x86_64.dmg"
    -x "$NAME/openclaw-team/CC-Switch-v3.15.0-macOS.dmg"
    -x "$NAME/openclaw-team/Homebrew.pkg"
    -x "$NAME/openclaw-team/openclaw-npm-cache.tgz"
  )
}

case "$PACKAGE_PROFILE" in
  core|core-macos15|core-macos26)
    add_core_excludes
    ;;
esac

case "$PACKAGE_PROFILE" in
  core-macos15)
    exclude_args+=(-x "$NAME/openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg")
    ;;
  core-macos26)
    exclude_args+=(-x "$NAME/openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg")
    ;;
esac

cd "$PARENT"
# Preserve symlinks inside .app/.framework bundles. Following them can drop
# framework aliases and make bundled apps fail after extraction.
zip -yr "$TMP_OUT" "$NAME" "${exclude_args[@]}"

mv "$TMP_OUT" "$OUT"
trap - EXIT

printf '\nPackage written to: %s\n' "$OUT"
printf 'Package profile: %s\n' "$PACKAGE_PROFILE"
printf 'Sensitive files are excluded. Keep private-secrets/ separate.\n'
