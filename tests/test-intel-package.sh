#!/usr/bin/env bash
# Verify the built macOS 14 Intel package at the artifact boundary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${1:-$ROOT/.package-build/openclaw-macos14-x64/install-files}"
MANIFEST="$DIST/DIST_MANIFEST.json"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[ -f "$MANIFEST" ] || fail "missing manifest: $MANIFEST"

/usr/bin/python3 - "$MANIFEST" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
manifest = json.loads(manifest_path.read_text())
assert manifest["profile"] == "macos14-x64", manifest["profile"]
assert manifest["target_arch"] == "x86_64", manifest["target_arch"]
root = manifest_path.parent
paths = {item["path"] for item in manifest["required_assets"]}
assert "openclaw-team/clash-party-macos-1.9.6-x64.pkg" in paths
assert "openclaw-team/AweSun_v16.5.0.30905_x86_64.dmg" in paths
assert not any("Command_Line_Tools" in path for path in paths)
for item in manifest["required_assets"]:
    path = root / item["path"]
    assert path.is_file(), path
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == item["sha256"], path
PY

cliproxy="$DIST/openclaw-team/cliproxy/CLIProxyAPI"
[ -x "$cliproxy" ] || fail "missing executable CLIProxyAPI"
lipo -archs "$cliproxy" | tr ' ' '\n' | grep -qx x86_64 ||
  fail "CLIProxyAPI does not contain x86_64"

codex_dmg="$DIST/openclaw-team/Codex.dmg"
hdiutil verify "$codex_dmg" >/dev/null
mount_dir="$(mktemp -d /tmp/openclaw-intel-codex.XXXXXX)"
cleanup() {
  hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
  rm -rf "$mount_dir"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -noverify -mountpoint "$mount_dir" "$codex_dmg" >/dev/null

app="$mount_dir/ChatGPT.app"
[ -d "$app" ] || fail "Codex DMG does not contain ChatGPT.app"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
lipo -archs "$app/Contents/MacOS/$executable" | tr ' ' '\n' | grep -qx x86_64 ||
  fail "Codex app does not contain x86_64"
minimum_major="${minimum_system%%.*}"
[ "$minimum_major" -le 14 ] || fail "Codex app requires macOS $minimum_system"

printf 'PASS: macos14-x64 package manifest, CLIProxy, Clash, and Codex contracts\n'
