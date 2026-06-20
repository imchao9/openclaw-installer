#!/usr/bin/env bash
# Rebuild ignored non-source artifacts from the repository source files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CODEX_PYTHON="/Users/cm/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
if [[ -n "${PYTHON:-}" ]]; then
  PYTHON_BIN="$PYTHON"
elif [[ -x "$DEFAULT_CODEX_PYTHON" ]]; then
  PYTHON_BIN="$DEFAULT_CODEX_PYTHON"
else
  PYTHON_BIN="python3"
fi

PROFILE="all"
OVERWRITE=0
REFRESH_ASSETS=0
SKIP_PDF=0
SKIP_PACKAGES=0
SYNC_INSTALL_FILES=0
SYNC_PROFILE="macos26-arm64"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-source-artifacts.sh [options]

Options:
  --profile PROFILE          Build all, macos26-arm64, or macos15-arm64. Default: all.
  --overwrite                Replace existing package outputs.
  --refresh-download-assets  Download public assets before packaging.
  --skip-pdf                 Do not regenerate docs/*.pdf.
  --skip-packages            Do not run scripts/build-dist.sh.
  --sync-install-files       Refresh root install-files/ from one built profile.
  --sync-profile PROFILE     Profile used by --sync-install-files. Default: macos26-arm64.
  -h, --help                 Show this help.

Environment:
  PYTHON=/path/to/python3     Python with reportlab installed. Defaults to Codex bundled
                              Python when available, then system python3.

Examples:
  bash scripts/build-source-artifacts.sh --overwrite
  bash scripts/build-source-artifacts.sh --profile macos15-arm64 --overwrite
  bash scripts/build-source-artifacts.sh --skip-packages
  bash scripts/build-source-artifacts.sh --profile macos26-arm64 --overwrite --sync-install-files

Notes:
  - Downloaded installers, PDFs, install-files/, .package-build/, and upload archives are
    intentionally ignored by Git.
  - private-secrets/ is never packaged by this script; keep it as a separate local input.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then
        echo "--profile requires a value" >&2
        exit 1
      fi
      PROFILE="$2"
      shift 2
      ;;
    --overwrite)
      OVERWRITE=1
      shift
      ;;
    --refresh-download-assets)
      REFRESH_ASSETS=1
      shift
      ;;
    --skip-pdf)
      SKIP_PDF=1
      shift
      ;;
    --skip-packages)
      SKIP_PACKAGES=1
      shift
      ;;
    --sync-install-files)
      SYNC_INSTALL_FILES=1
      shift
      ;;
    --sync-profile)
      if [[ $# -lt 2 ]]; then
        echo "--sync-profile requires a value" >&2
        exit 1
      fi
      SYNC_PROFILE="$2"
      shift 2
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
done

case "$PROFILE" in
  all|macos26-arm64|macos15-arm64) ;;
  *)
    echo "unsupported profile: $PROFILE" >&2
    exit 1
    ;;
esac

case "$SYNC_PROFILE" in
  macos26-arm64|macos15-arm64) ;;
  *)
    echo "unsupported sync profile: $SYNC_PROFILE" >&2
    exit 1
    ;;
esac

if [[ "$SYNC_INSTALL_FILES" == "1" && "$SKIP_PACKAGES" == "1" ]]; then
  echo "--sync-install-files needs package output; remove --skip-packages" >&2
  exit 1
fi

run_step() {
  printf '\n==> %s\n' "$*"
}

if [[ "$SKIP_PDF" != "1" ]]; then
  run_step "Regenerating PDF docs"
  "$PYTHON_BIN" "$ROOT_DIR/scripts/pdf/generate_user_install_guide_pdf.py"
  "$PYTHON_BIN" "$ROOT_DIR/scripts/pdf/generate_user_install_guide_pdf.py" \
    "$ROOT_DIR/docs/openclaw-install-without-ai.md" \
    "$ROOT_DIR/docs/openclaw-install-without-ai.pdf" \
    "OpenClaw 安装说明"
  "$PYTHON_BIN" "$ROOT_DIR/scripts/pdf/generate_download_sources_pdf.py"
fi

if [[ "$SKIP_PACKAGES" != "1" ]]; then
  run_step "Building installer package artifacts"
  OVERWRITE_DIST="$OVERWRITE" REFRESH_DOWNLOAD_ASSETS="$REFRESH_ASSETS" \
    bash "$ROOT_DIR/scripts/build-dist.sh" "$PROFILE"
fi

if [[ "$SYNC_INSTALL_FILES" == "1" ]]; then
  source_dir="$ROOT_DIR/.package-build/openclaw-$SYNC_PROFILE/install-files"
  if [[ ! -d "$source_dir" ]]; then
    echo "built install-files not found: $source_dir" >&2
    exit 1
  fi

  run_step "Refreshing root install-files/ from $SYNC_PROFILE"
  rm -rf "$ROOT_DIR/install-files"
  if cp -cR "$source_dir" "$ROOT_DIR/install-files" 2>/dev/null; then
    :
  else
    cp -R "$source_dir" "$ROOT_DIR/install-files"
  fi
fi

run_step "Done"
printf 'Generated artifacts are ignored by Git; use git status --ignored to inspect them.\n'
