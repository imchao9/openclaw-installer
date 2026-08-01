#!/usr/bin/env bash
# Resolve the only supported installer profile for a target macOS/architecture.
set -euo pipefail

macos_version="${1:-}"
arch="${2:-}"

if [ -z "$macos_version" ] || [ -z "$arch" ]; then
  echo "Usage: $0 <macos-version> <arch>" >&2
  exit 2
fi

major="${macos_version%%.*}"
case "$major" in
  ''|*[!0-9]*)
    echo "Unsupported macOS version: $macos_version" >&2
    exit 20
    ;;
esac

case "$major:$arch" in
  26:arm64)
    printf '%s\n' macos26-arm64
    ;;
  14:x86_64)
    printf '%s\n' macos14-x64
    ;;
  15:x86_64)
    printf '%s\n' macos15-x64
    ;;
  15:arm64)
    printf '%s\n' macos15-arm64
    ;;
  *)
    echo "No supported package profile for macOS $macos_version on $arch" >&2
    exit 20
    ;;
esac
