#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/openclaw-clash-runtime-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export LAUNCHCTL_LOG="$WORK/launchctl.log"
mkdir -p "$HOME/Library/LaunchAgents" "$WORK/bin"

cat > "$WORK/bin/launchctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
exit 0
SH
chmod +x "$WORK/bin/launchctl"
PATH="$WORK/bin:$PATH"
export PATH

DRY_RUN=0

is_dry_run() {
  [ "$DRY_RUN" = "1" ]
}

dry_log() {
  :
}

log() {
  :
}

# shellcheck source=../installer-core/lib/installer-cliproxy.sh
source "$ROOT/installer-core/lib/installer-cliproxy.sh"

legacy_plist="$HOME/Library/LaunchAgents/local.openclaw-installer.mihomo-core.plist"
printf 'legacy\n' > "$legacy_plist"

remove_persistent_clash_party_sidecar_fallback

[ ! -e "$legacy_plist" ] || {
  echo "FAIL: legacy persistent mihomo fallback was not removed" >&2
  exit 1
}
grep -qF "bootout gui/$(id -u)/local.openclaw-installer.mihomo-core" "$LAUNCHCTL_LOG"

remove_persistent_clash_party_sidecar_fallback
[ ! -e "$legacy_plist" ] || {
  echo "FAIL: fallback cleanup is not idempotent" >&2
  exit 1
}

fallback_block="$(
  sed -n \
    '/log "Starting Clash Party mihomo sidecar fallback"/,/for wait_i in 1 2 3 4/p' \
    "$ROOT/installer-core/lib/installer-cliproxy.sh"
)"
if printf '%s\n' "$fallback_block" \
  | grep -Eq 'Library/LaunchAgents|launchctl (bootstrap|bootout)|<key>KeepAlive</key>'; then
  echo "FAIL: Clash Party sidecar fallback must not install a persistent LaunchAgent" >&2
  exit 1
fi

grep -qF 'Clash Party mihomo sidecar fallback is temporary' \
  "$ROOT/installer-core/lib/installer-cliproxy.sh"

echo "PASS: Clash Party fallback lifecycle contract"
