#!/usr/bin/env bash
# Install/register Doubao input method and optionally grant microphone permission.
set -euo pipefail

APP="/Library/Input Methods/DoubaoIme.app"
USER_APP="$HOME/Library/Input Methods/DoubaoIme.app"
ZIP="${DOUBAO_ZIP:-$HOME/openclaw-installer-run/openclaw-team/DoubaoImeInstaller_v0.9.1.app/Contents/Resources/DoubaoIme.zip}"
BUNDLE_ID="com.bytedance.inputmethod.doubaoime"
INPUT_MODE="com.bytedance.inputmethod.doubaoime.pinyin"
PREF="$HOME/Library/Preferences/com.apple.HIToolbox.plist"

sudo_keepalive() {
  if sudo -n true >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${DOUBAO_SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "$DOUBAO_SUDO_PASSWORD" | sudo -S -v
    return 0
  fi
  return 1
}

install_system_app() {
  local version tmp
  version="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  if [ -d "$APP" ] && [ "$version" = "0.9.1" ]; then
    return
  fi
  [ -f "$ZIP" ] || {
    echo "Missing DoubaoIme zip: $ZIP" >&2
    return 1
  }
  sudo_keepalive
  tmp="$(/usr/bin/mktemp -d /tmp/openclaw-doubao-system.XXXXXX)"
  /usr/bin/unzip -qq "$ZIP" -d "$tmp"
  sudo -n /bin/rm -rf "$APP"
  sudo -n /bin/mv "$tmp/DoubaoIme.app" "$APP"
  /bin/rmdir "$tmp"
}

register_input_source() {
  /usr/bin/pkill -x DoubaoIme 2>/dev/null || true
  /usr/bin/pkill -x DoubaoImeSettings 2>/dev/null || true
  /bin/sleep 1

  /bin/rm -rf "$USER_APP"
  sudo_keepalive || true
  sudo -n /usr/sbin/chown -R root:wheel "$APP" 2>/dev/null || true
  sudo -n /usr/bin/xattr -d -r com.apple.quarantine "$APP" 2>/dev/null || true

  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$USER_APP" 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

  if [ "${DOUBAO_USE_SWIFT:-0}" = "1" ] && command -v swift >/dev/null 2>&1; then
    swift - "$APP" "$INPUT_MODE" <<'SWIFT' >/dev/null 2>&1 || true
import Carbon
import Foundation

let appPath = CommandLine.arguments[1]
let inputMode = CommandLine.arguments[2] as CFString
TISRegisterInputSource(URL(fileURLWithPath: appPath) as CFURL)
let props = [kTISPropertyInputSourceID: inputMode] as CFDictionary
let list = TISCreateInputSourceList(props, true)?.takeRetainedValue() as NSArray? ?? []
if list.count > 0 {
    let source = list[0] as! TISInputSource
    TISEnableInputSource(source)
    TISSelectInputSource(source)
}
SWIFT
  fi
}

write_input_preferences() {
  if /usr/bin/python3 -c 'import plistlib' >/dev/null 2>&1; then
    /usr/bin/python3 - "$PREF" "$BUNDLE_ID" "$INPUT_MODE" <<'PY'
import os
import plistlib
import sys

pref, bundle_id, input_mode = sys.argv[1:4]
abc = {"InputSourceKind": "Keyboard Layout", "KeyboardLayout ID": 252, "KeyboardLayout Name": "ABC"}
scim_mode = {"Bundle ID": "com.apple.inputmethod.SCIM", "Input Mode": "com.apple.inputmethod.SCIM.ITABC", "InputSourceKind": "Input Mode"}
scim_method = {"Bundle ID": "com.apple.inputmethod.SCIM", "InputSourceKind": "Keyboard Input Method"}
character = {"Bundle ID": "com.apple.CharacterPaletteIM", "InputSourceKind": "Non Keyboard Input Method"}
doubao_mode = {"Bundle ID": bundle_id, "Input Mode": input_mode, "InputSourceKind": "Input Mode"}
doubao_method = {"Bundle ID": bundle_id, "InputSourceKind": "Keyboard Input Method"}

try:
    with open(pref, "rb") as f:
        data = plistlib.load(f)
except FileNotFoundError:
    data = {}

def key(item):
    if not isinstance(item, dict):
        return None
    return (
        item.get("Bundle ID"),
        item.get("Input Mode"),
        item.get("InputSourceKind"),
        item.get("KeyboardLayout ID"),
        item.get("KeyboardLayout Name"),
    )

enabled = data.get("AppleEnabledInputSources")
if not isinstance(enabled, list):
    enabled = []
deduped = []
seen = set()
for item in enabled:
    item_key = key(item)
    if item_key is None or item_key in seen:
        continue
    deduped.append(item)
    seen.add(item_key)
enabled = deduped
for item in (abc, scim_mode, scim_method, character, doubao_mode, doubao_method):
    item_key = key(item)
    if item_key not in seen:
        enabled.append(dict(item))
        seen.add(item_key)
data["AppleEnabledInputSources"] = enabled
if os.environ.get("DOUBAO_SELECT", "1") != "0":
    data["AppleSelectedInputSources"] = [dict(doubao_mode)]
    data["AppleInputSourceHistory"] = [dict(doubao_mode), dict(scim_mode), dict(abc)]
else:
    if "AppleSelectedInputSources" not in data:
        data["AppleSelectedInputSources"] = [dict(scim_mode)]

os.makedirs(os.path.dirname(pref), exist_ok=True)
with open(pref, "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
PY
  else
    write_input_preferences_with_plistbuddy
  fi
  /usr/bin/plutil -lint "$PREF" >/dev/null
  /usr/bin/defaults write com.apple.TextInputMenu visible -bool true
  /usr/bin/defaults write com.apple.systemuiserver menuExtras -array "/System/Library/CoreServices/Menu Extras/TextInput.menu"
}

plist_array_count() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Print :$key" "$PREF" 2>/dev/null | /usr/bin/awk '/Dict \{/ {count++} END {print count + 0}'
}

plist_ensure_array() {
  local key="$1"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PREF" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :$key array" "$PREF"
  fi
}

plist_reset_array() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Delete :$key" "$PREF" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :$key array" "$PREF"
}

plist_add_keyboard_layout() {
  local key="$1" idx
  defaults read "$PREF" "$key" 2>/dev/null | grep -qF "KeyboardLayout Name = ABC" && return
  idx="$(plist_array_count "$key")"
  plist_force_add_keyboard_layout "$key" "$idx"
}

plist_force_add_keyboard_layout() {
  local key="$1" idx="$2"
  /usr/libexec/PlistBuddy -c "Add :$key:$idx dict" "$PREF"
  /usr/libexec/PlistBuddy -c "Add :$key:$idx:InputSourceKind string Keyboard Layout" "$PREF"
  /usr/libexec/PlistBuddy -c "Add ':$key:$idx:KeyboardLayout ID' integer 252" "$PREF"
  /usr/libexec/PlistBuddy -c "Add ':$key:$idx:KeyboardLayout Name' string ABC" "$PREF"
}

plist_add_bundle_source() {
  local key="$1" bundle="$2" mode="$3" kind="$4" idx
  if [ -n "$mode" ]; then
    defaults read "$PREF" "$key" 2>/dev/null | grep -qF "$mode" && return
  elif defaults read "$PREF" "$key" 2>/dev/null | grep -qF "$bundle" && \
       defaults read "$PREF" "$key" 2>/dev/null | grep -qF "$kind"; then
    return
  fi
  idx="$(plist_array_count "$key")"
  /usr/libexec/PlistBuddy -c "Add :$key:$idx dict" "$PREF"
  /usr/libexec/PlistBuddy -c "Add ':$key:$idx:Bundle ID' string $bundle" "$PREF"
  if [ -n "$mode" ]; then
    /usr/libexec/PlistBuddy -c "Add ':$key:$idx:Input Mode' string $mode" "$PREF"
  fi
  /usr/libexec/PlistBuddy -c "Add :$key:$idx:InputSourceKind string $kind" "$PREF"
}

plist_force_add_bundle_source() {
  local key="$1" bundle="$2" mode="$3" kind="$4" idx
  idx="$(plist_array_count "$key")"
  /usr/libexec/PlistBuddy -c "Add :$key:$idx dict" "$PREF"
  /usr/libexec/PlistBuddy -c "Add ':$key:$idx:Bundle ID' string $bundle" "$PREF"
  if [ -n "$mode" ]; then
    /usr/libexec/PlistBuddy -c "Add ':$key:$idx:Input Mode' string $mode" "$PREF"
  fi
  /usr/libexec/PlistBuddy -c "Add :$key:$idx:InputSourceKind string $kind" "$PREF"
}

write_input_preferences_with_plistbuddy() {
  /bin/mkdir -p "$(/usr/bin/dirname "$PREF")"
  [ -f "$PREF" ] || /usr/bin/plutil -create binary1 "$PREF"

  plist_reset_array AppleEnabledInputSources
  plist_force_add_keyboard_layout AppleEnabledInputSources 0
  plist_force_add_bundle_source AppleEnabledInputSources "com.apple.inputmethod.SCIM" "com.apple.inputmethod.SCIM.ITABC" "Input Mode"
  plist_force_add_bundle_source AppleEnabledInputSources "com.apple.inputmethod.SCIM" "" "Keyboard Input Method"
  plist_force_add_bundle_source AppleEnabledInputSources "com.apple.CharacterPaletteIM" "" "Non Keyboard Input Method"
  plist_force_add_bundle_source AppleEnabledInputSources "$BUNDLE_ID" "$INPUT_MODE" "Input Mode"
  plist_force_add_bundle_source AppleEnabledInputSources "$BUNDLE_ID" "" "Keyboard Input Method"

  if [ "${DOUBAO_SELECT:-1}" != "0" ]; then
    plist_reset_array AppleSelectedInputSources
    plist_add_bundle_source AppleSelectedInputSources "$BUNDLE_ID" "$INPUT_MODE" "Input Mode"
    plist_reset_array AppleInputSourceHistory
    plist_force_add_bundle_source AppleInputSourceHistory "$BUNDLE_ID" "$INPUT_MODE" "Input Mode"
    plist_force_add_bundle_source AppleInputSourceHistory "com.apple.inputmethod.SCIM" "com.apple.inputmethod.SCIM.ITABC" "Input Mode"
    plist_force_add_keyboard_layout AppleInputSourceHistory 2
  else
    plist_ensure_array AppleSelectedInputSources
    if [ "$(plist_array_count AppleSelectedInputSources)" = "0" ]; then
      plist_add_bundle_source AppleSelectedInputSources "com.apple.inputmethod.SCIM" "com.apple.inputmethod.SCIM.ITABC" "Input Mode"
    fi
  fi
}

grant_microphone_permission() {
  [ "${DOUBAO_GRANT_MIC:-1}" = "1" ] || return
  [ -f "$HOME/Library/Application Support/com.apple.TCC/TCC.db" ] || return
  command -v sqlite3 >/dev/null 2>&1 || return

  local tcc backup req_txt req_bin hex now
  tcc="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  backup="$tcc.openclaw-backup.$(/bin/date +%Y%m%d%H%M%S)"
  /bin/cp "$tcc" "$backup"
  req_txt="/tmp/doubaoime.csreq.txt"
  req_bin="/tmp/doubaoime.csreq.bin"
  /usr/bin/codesign -dr - "$APP" 2>&1 \
    | /usr/bin/awk -F 'designated => ' '/designated => / {print $2}' \
    | /usr/bin/sed 's:/\*[^*]*\*/::g' > "$req_txt"
  /usr/bin/csreq -r "$req_txt" -b "$req_bin"
  hex="$(/usr/bin/xxd -p "$req_bin" | /usr/bin/tr -d '\n')"
  now="$(/bin/date +%s)"
  /usr/bin/sqlite3 "$tcc" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified, pid, pid_version, boot_uuid, last_reminded) VALUES ('kTCCServiceMicrophone', '$BUNDLE_ID', 0, 2, 3, 1, X'$hex', NULL, 0, 'UNUSED', NULL, 0, $now, NULL, NULL, 'UNUSED', $now);"
  /usr/bin/killall tccd 2>/dev/null || true
}

refresh_agents() {
  /bin/rm -f "$HOME/Library/Caches/com.apple.inputsources"* "$HOME/Library/Caches/com.apple.IntlDataCache"* 2>/dev/null || true
  /usr/bin/killall cfprefsd 2>/dev/null || true
  /usr/bin/killall TextInputMenuAgent 2>/dev/null || true
  /usr/bin/killall TextInputSwitcher 2>/dev/null || true
  /usr/bin/killall SystemUIServer 2>/dev/null || true
  /usr/bin/open -a "$APP" 2>/dev/null || true
}

install_system_app
register_input_source
write_input_preferences
grant_microphone_permission
refresh_agents

printf 'Doubao input configured: %s\n' "$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
