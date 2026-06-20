#!/usr/bin/env bash
# Enable Doubao input method for the current macOS user.
set -euo pipefail

SYSTEM_INPUT_METHOD_APP="/Library/Input Methods/DoubaoIme.app"
USER_INPUT_METHOD_APP="$HOME/Library/Input Methods/DoubaoIme.app"
INPUT_METHOD_APP="$SYSTEM_INPUT_METHOD_APP"
BUNDLE_ID="com.bytedance.inputmethod.doubaoime"
INPUT_MODE="com.bytedance.inputmethod.doubaoime.pinyin"
PREF="$HOME/Library/Preferences/com.apple.HIToolbox.plist"

find_real_python3() {
  local candidate
  for candidate in "${PYTHON3_BIN:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null || true)"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    if [ "$candidate" = "/usr/bin/python3" ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
      continue
    fi
    "$candidate" -c 'import plistlib' >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

if [ -d "$USER_INPUT_METHOD_APP" ]; then
  INPUT_METHOD_APP="$USER_INPUT_METHOD_APP"
elif [ -d "$SYSTEM_INPUT_METHOD_APP" ]; then
  INPUT_METHOD_APP="$SYSTEM_INPUT_METHOD_APP"
else
  echo "Doubao input method is not installed: $SYSTEM_INPUT_METHOD_APP or $USER_INPUT_METHOD_APP"
  exit 1
fi

mkdir -p "$(dirname "$PREF")"

PYTHON3_BIN="$(find_real_python3 || true)"
if [ -z "$PYTHON3_BIN" ]; then
  echo "No real python3 found; skipping automatic Doubao input source enable to avoid macOS Command Line Tools popup."
  echo "Open System Settings > Keyboard > Input Sources and enable Doubao manually if needed."
  exit 0
fi

"$PYTHON3_BIN" - "$PREF" "$BUNDLE_ID" "$INPUT_MODE" <<'PY'
import os
import plistlib
import sys

pref, bundle_id, input_mode = sys.argv[1:4]

if os.path.exists(pref):
    with open(pref, "rb") as f:
        data = plistlib.load(f)
else:
    data = {}

source = {
    "Bundle ID": bundle_id,
    "Input Mode": input_mode,
    "InputSourceKind": "Input Mode",
}
method_source = {
    "Bundle ID": bundle_id,
    "InputSourceKind": "Keyboard Input Method",
}

for key in ("AppleEnabledInputSources",):
    value = data.get(key)
    if not isinstance(value, list):
        value = []
    for candidate in (source, method_source):
        exists = any(
            isinstance(item, dict)
            and item.get("Bundle ID") == candidate.get("Bundle ID")
            and item.get("Input Mode") == candidate.get("Input Mode")
            and item.get("InputSourceKind") == candidate.get("InputSourceKind")
            for item in value
        )
        if not exists:
            value.append(dict(candidate))
    data[key] = value

history = data.get("AppleInputSourceHistory")
if not isinstance(history, list):
    history = []
history = [
    item for item in history
    if not (isinstance(item, dict) and item.get("Bundle ID") == bundle_id)
]
data["AppleInputSourceHistory"] = history[:10]

with open(pref, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
PY

/usr/bin/plutil -lint "$PREF" >/dev/null
if [ -d "$USER_INPUT_METHOD_APP" ]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$USER_INPUT_METHOD_APP" 2>/dev/null || true
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INPUT_METHOD_APP" 2>/dev/null || true
if command -v swift >/dev/null 2>&1; then
  swift - "$INPUT_METHOD_APP" <<'SWIFT' >/dev/null 2>&1 || true
import Carbon
import Foundation

let appPath = CommandLine.arguments[1]
let url = URL(fileURLWithPath: appPath) as CFURL
TISRegisterInputSource(url)
let props = [kTISPropertyInputSourceID: "com.bytedance.inputmethod.doubaoime.pinyin" as CFString] as CFDictionary
let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as NSArray? ?? []
if list.count > 0 {
    let source = list[0] as! TISInputSource
    TISEnableInputSource(source)
}
SWIFT
fi
/bin/rm -f "$HOME/Library/Caches/com.apple.inputsources"* 2>/dev/null || true
/bin/rm -f "$HOME/Library/Caches/com.apple.IntlDataCache"* 2>/dev/null || true
/usr/bin/defaults write com.apple.TextInputMenu visible -bool true
if ! /usr/bin/defaults read com.apple.systemuiserver menuExtras 2>/dev/null | /usr/bin/grep -q 'TextInput.menu'; then
  /usr/bin/defaults write com.apple.systemuiserver menuExtras -array-add "/System/Library/CoreServices/Menu Extras/TextInput.menu" 2>/dev/null || true
fi
/usr/bin/killall cfprefsd 2>/dev/null || true
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/usr/bin/killall TextInputSwitcher 2>/dev/null || true
/usr/bin/killall SystemUIServer 2>/dev/null || true
/usr/bin/open -a "$INPUT_METHOD_APP" 2>/dev/null || true

echo "Added Doubao input method to enabled sources: $INPUT_MODE"
echo "Select it from the macOS input menu if it does not become active automatically."
