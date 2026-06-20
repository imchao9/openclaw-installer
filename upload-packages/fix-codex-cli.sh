#!/usr/bin/env bash
# Repair the `codex` shell command on a target macOS user account.
set -euo pipefail

log() {
  printf '[fix-codex-cli] %s\n' "$*"
}

ensure_path_line() {
  local file="$1" dir="$2" label="$3"
  local marker="# openclaw-installer PATH: $label"
  local expr="$dir"

  case "$dir" in
    "$HOME") expr='$HOME' ;;
    "$HOME"/*) expr='$HOME/'"${dir#"$HOME"/}" ;;
  esac

  touch "$file"
  if ! grep -qF "$marker" "$file"; then
    printf '\nexport PATH="%s:$PATH" %s\n' "$expr" "$marker" >> "$file"
    log "added $dir to $file"
  fi
}

ensure_path_dir() {
  local dir="$1" label="$2"
  [ -n "$dir" ] || return 0
  mkdir -p "$dir" 2>/dev/null || true
  ensure_path_line "$HOME/.zshenv" "$dir" "$label"
  ensure_path_line "$HOME/.zshrc" "$dir" "$label"
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}

npm_global_bin_dir() {
  local npm_bin="$1"
  local prefix
  prefix="$("$npm_bin" config get prefix 2>/dev/null || true)"
  if [ -n "$prefix" ] && [ "$prefix" != "undefined" ] && [ "$prefix" != "null" ]; then
    printf '%s/bin\n' "$prefix"
  fi
}

ensure_path_dir "/usr/local/bin" "system-bin"
ensure_path_dir "/opt/homebrew/bin" "homebrew-bin"
ensure_path_dir "$HOME/.local/bin" "local-bin"

if command -v npm >/dev/null 2>&1; then
  npm_bin="$(command -v npm)"
  npm_bin_dir="$(npm_global_bin_dir "$npm_bin" || true)"
  if [ -n "$npm_bin_dir" ]; then
    ensure_path_dir "$npm_bin_dir" "npm-global"
  fi
else
  npm_bin=""
  npm_bin_dir=""
fi

if ! command -v codex >/dev/null 2>&1; then
  if [ -n "$npm_bin" ]; then
    log "installing @openai/codex with npm"
    if ! "$npm_bin" install -g @openai/codex; then
      log "npm global install failed without sudo; retrying with sudo"
      sudo "$npm_bin" install -g @openai/codex
    fi
    hash -r 2>/dev/null || true
  fi
fi

if ! command -v codex >/dev/null 2>&1; then
  app_codex="/Applications/Codex.app/Contents/Resources/codex"
  if [ -x "$app_codex" ]; then
    ln -sf "$app_codex" "$HOME/.local/bin/codex"
    hash -r 2>/dev/null || true
    log "linked Codex.app CLI to $HOME/.local/bin/codex"
  fi
fi

if command -v codex >/dev/null 2>&1; then
  log "ok: $(command -v codex)"
  codex --version || true
  log "open a new terminal, or run: exec zsh -l"
else
  log "failed: codex is still not found"
  log "Node/npm may be missing. Re-run the OpenClaw installer base phase, then run this script again."
  exit 1
fi
