#!/usr/bin/env bash
# Assemble one complete, non-sensitive offline delivery directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE=""
OUTPUT_ROOT="${OPENCLAW_DELIVERY_DIR:-$ROOT/deliveries}"

usage() {
  cat <<'EOF'
Usage: bash scripts/build-offline-delivery.sh --profile PROFILE [--output-root DIR]

Creates DIR/OpenClaw-Install-PROFILE with the installer scripts and all required
non-sensitive package layers. private-secrets is intentionally never copied;
transfer it separately only to trusted operators.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --output-root) OUTPUT_ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PROFILE" ] || { printf '%s\n' '--profile is required' >&2; exit 2; }
case "$PROFILE" in
  macos14-x64|macos15-x64|macos15-arm64|macos26-arm64) ;;
  *) printf 'Unsupported profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

OUTPUT_DIR="$OUTPUT_ROOT/OpenClaw-Install-$PROFILE"
[ ! -e "$OUTPUT_DIR" ] || { printf 'Refusing to overwrite: %s\n' "$OUTPUT_DIR" >&2; exit 1; }
mkdir -p "$OUTPUT_ROOT"

bash "$ROOT/scripts/assemble-layered-package.sh" --profile "$PROFILE" --output-dir "$OUTPUT_DIR"
[ ! -e "$OUTPUT_DIR/private-secrets" ] || { printf '%s\n' 'ERROR: private-secrets must not be included.' >&2; exit 1; }

printf 'Offline delivery ready: %s\n' "$OUTPUT_DIR"
