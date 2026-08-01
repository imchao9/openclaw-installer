#!/usr/bin/env bash
# Verify every layered profile can be assembled with the expected architecture and CLT.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX="${LAYER_INDEX:-$ROOT/upload-packages/openclaw-layer-index.json}"
PACKAGES_DIR="${LAYER_DIR:-$ROOT/upload-packages}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-layered-test.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

profiles=(macos14-x64 macos15-x64 macos15-arm64 macos26-arm64)
for profile in "${profiles[@]}"; do
  output="$TMP/openclaw-$profile"
  OVERWRITE_ASSEMBLED=1 bash "$ROOT/scripts/assemble-layered-package.sh" \
    --profile "$profile" \
    --index "$INDEX" \
    --packages-dir "$PACKAGES_DIR" \
    --output-dir "$output"

  manifest="$output/install-files/DIST_MANIFEST.json"
  /usr/bin/python3 - "$manifest" "$profile" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
profile = sys.argv[2]
manifest = json.loads(path.read_text())
assert manifest["profile"] == profile
assert manifest["layers"][0] == "common"
root = path.parent
for asset in manifest["required_assets"]:
    candidate = root / asset["path"]
    assert candidate.is_file(), candidate
    hasher = hashlib.sha256()
    with candidate.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    assert digest == asset["sha256"], candidate
PY

  binary="$output/install-files/openclaw-team/cliproxy/CLIProxyAPI"
  case "$profile" in
    *-x64) expected_arch=x86_64 ;;
    *-arm64) expected_arch=arm64 ;;
  esac
  lipo -archs "$binary" | tr ' ' '\n' | grep -qx "$expected_arch"

  clt15="$output/install-files/openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg"
  clt26="$output/install-files/openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg"
  case "$profile" in
    macos14-x64)
      [ ! -e "$clt15" ] && [ ! -e "$clt26" ]
      ;;
    macos15-*)
      [ -f "$clt15" ] && [ ! -e "$clt26" ]
      ;;
    macos26-arm64)
      [ ! -e "$clt15" ] && [ -f "$clt26" ]
      ;;
  esac

  rm -rf "$output"
done

printf 'PASS: all layered OpenClaw profiles assemble with correct assets\n'
