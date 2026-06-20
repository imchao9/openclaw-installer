#!/usr/bin/env bash
# Verify Doubao input method registration and microphone permission.
set -euo pipefail

APP="/Library/Input Methods/DoubaoIme.app"
BUNDLE_ID="com.bytedance.inputmethod.doubaoime"
INPUT_MODE="com.bytedance.inputmethod.doubaoime.pinyin"
PREF="$HOME/Library/Preferences/com.apple.HIToolbox.plist"
TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

version="$(/usr/bin/defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
input_source=0
/usr/bin/defaults read "$PREF" AppleEnabledInputSources 2>/dev/null | /usr/bin/grep -qF "$INPUT_MODE" && input_source=1
menu=0
/usr/bin/defaults read com.apple.systemuiserver menuExtras 2>/dev/null | /usr/bin/grep -qF "TextInput.menu" && menu=1
microphone=0
tcc_row=""
if [ -f "$TCC" ] && command -v sqlite3 >/dev/null 2>&1; then
  tcc_row="$(/usr/bin/sqlite3 "$TCC" "select auth_value || '|' || length(csreq) from access where service='kTCCServiceMicrophone' and client='$BUNDLE_ID' order by last_modified desc limit 1;" 2>/dev/null || true)"
  case "$tcc_row" in
    2\|[1-9]*)
      microphone=1
      ;;
  esac
fi
selected=0
/usr/bin/defaults read "$PREF" AppleSelectedInputSources 2>/dev/null | /usr/bin/grep -qF "$INPUT_MODE" && selected=1
history=0
/usr/bin/defaults read "$PREF" AppleInputSourceHistory 2>/dev/null | /usr/bin/grep -qF "$INPUT_MODE" && history=1
enabled_text="$(/usr/bin/defaults read "$PREF" AppleEnabledInputSources 2>/dev/null || true)"
abc_enabled_count="$(printf '%s\n' "$enabled_text" | /usr/bin/awk '/KeyboardLayout Name.*ABC/ {count++} END {print count + 0}')"
doubao_mode_enabled_count="$(printf '%s\n' "$enabled_text" | /usr/bin/awk -v mode="$INPUT_MODE" 'index($0, mode) {count++} END {print count + 0}')"

printf 'doubao_version=%s\n' "$version"
printf 'doubao_input_source=%s\n' "$input_source"
printf 'doubao_menu=%s\n' "$menu"
printf 'doubao_microphone=%s\n' "$microphone"
printf 'doubao_tcc_row=%s\n' "$tcc_row"
printf 'doubao_selected=%s\n' "$selected"
printf 'doubao_history=%s\n' "$history"
printf 'abc_enabled_count=%s\n' "$abc_enabled_count"
printf 'doubao_mode_enabled_count=%s\n' "$doubao_mode_enabled_count"

test "$version" = "0.9.1"
test "$input_source" = "1"
test "$menu" = "1"
test "$microphone" = "1"
test "$selected" = "1"
test "$history" = "1"
test "$abc_enabled_count" = "1"
test "$doubao_mode_enabled_count" = "1"
