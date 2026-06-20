#!/usr/bin/env bash
# merge-tools-notes.sh — 把媒体生成笔记合并进新机器的 ~/clawd/TOOLS.md
# 让新机器的 agent 一启动读 TOOLS.md 就知道：key 在哪、用哪个命令出图/出音乐/出视频。
# 幂等：用 MEDIA-GEN-NOTES 标记块，重复跑会替换而不是重复追加。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$HERE/.." && pwd)"

NOTES="$SETUP_DIR/tools-notes.md"
TOOLS="$HOME/clawd/TOOLS.md"

[ -f "$NOTES" ] || { echo "    [!] 缺少 $NOTES，跳过"; exit 0; }

mkdir -p "$(dirname "$TOOLS")"
[ -f "$TOOLS" ] || printf '# TOOLS.md - Local Notes\n\n' > "$TOOLS"

# 先删掉旧的标记块（若存在），再追加新的。用系统 perl，避免触发 macOS python3/CLT 弹窗。
tmp="$(mktemp)"
perl -0pe 's/<!-- MEDIA-GEN-NOTES-START.*?MEDIA-GEN-NOTES-END -->\n?//gs; s/\s+\z/\n/s' "$TOOLS" > "$tmp"
{
  cat "$tmp"
  printf '\n'
  sed -e '${/^$/d;}' "$NOTES"
  printf '\n'
} > "$TOOLS"
rm -f "$tmp"
echo "    已合并媒体生成笔记 -> $TOOLS"
