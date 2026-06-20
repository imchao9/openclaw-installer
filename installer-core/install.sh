#!/usr/bin/env bash
# install.sh — 新电脑一键完整还原：配置文件 + 媒体工具/skill + 密钥 + 微信插件
# 用法：
#   1. 把整个 installer-core/ 文件夹复制到新电脑
#   2. 编辑 secrets.env，填入真实密钥
#   3. 运行：  bash install.sh
# 可选环境变量：
#   SKIP_DOTFILES=1  跳过还原 .codex/.claude/.openclaw 配置
#   SKIP_MEDIA=1     跳过 mmx-cli / skill 安装
#   SKIP_SECRETS=1   跳过密钥安装、密钥校验和 Seedream key 注入
#   SKIP_WEIXIN=1    跳过微信插件 + 电源设置（需 sudo）
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
export PATH

# 装一个 ClawHub skill（已存在则跳过）
install_skill() {
  local slug="$1"
  local dir="$HOME/clawd/skills/$slug"
  if [ -d "$dir" ]; then
    echo "    skill 已存在，跳过：$slug"
  elif command -v openclaw >/dev/null 2>&1; then
    openclaw skills install "$slug" || echo "    [!] 安装 skill 失败：${slug}（可手动 openclaw skills install ${slug}）"
  else
    echo "    [!] 未找到 openclaw CLI，请手动：openclaw skills install $slug"
  fi
}

# 还原单个配置文件（旧文件自动备份）
restore_file() {
  local src="$1" dst="$2"
  [ -f "$src" ] || { echo "    [!] 源文件缺失，跳过：$src"; return; }
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    local bak="${dst}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$dst" "$bak"
    echo "    已备份旧文件 -> $bak"
  fi
  cp "$src" "$dst"
  chmod 600 "$dst"
  echo "    还原: $dst"
}

echo "==> 1/7 检查 Node / npm"
if ! command -v node >/dev/null 2>&1; then
  echo "缺少 Node.js。请先安装（推荐 nvm 或官网 LTS），然后重跑本脚本。"
  exit 1
fi
echo "    node $(node --version) / npm $(npm --version)"

echo "==> 2/7 还原配置文件（.codex / .claude / .openclaw）"
if [ "${SKIP_DOTFILES:-0}" != "1" ]; then
  restore_file "$HERE/dotfiles/.codex/auth.json"        "$HOME/.codex/auth.json"
  restore_file "$HERE/dotfiles/.codex/config.toml"      "$HOME/.codex/config.toml"
  restore_file "$HERE/dotfiles/.claude/settings.json"   "$HOME/.claude/settings.json"
  restore_file "$HERE/dotfiles/.openclaw/openclaw.json" "$HOME/.openclaw/openclaw.json"
else
  echo "    跳过 (SKIP_DOTFILES=1)"
fi

if [ "${SKIP_MEDIA:-0}" != "1" ]; then
  echo "==> 3/7 安装 mmx-cli + minimax-multimodal skill（MiniMax 音乐/语音/视频/文本）"
  if command -v mmx >/dev/null 2>&1; then
    echo "    已安装：mmx $(mmx --version 2>&1 | head -1)"
  else
    npm install -g mmx-cli
  fi
  # 钉死区域为 cn（这个 key 是 cn 区）
  mmx config set --key region --value cn >/dev/null 2>&1 || true
  install_skill minimax-multimodal
  # 把视频脚本安装到工作区永久位置（不依赖 installer-core/ 是否还在）
  if [ -f "$HERE/seedance.sh" ]; then
    mkdir -p "$HOME/clawd/bin"
    cp "$HERE/seedance.sh" "$HOME/clawd/bin/seedance.sh"
    chmod +x "$HOME/clawd/bin/seedance.sh"
    echo "    视频脚本已安装 -> $HOME/clawd/bin/seedance.sh"
  else
    echo "    [!] 未找到 seedance.sh，视频脚本未安装"
  fi
else
  echo "==> 3/7 跳过媒体工具 (SKIP_MEDIA=1)"
fi

SECRETS_DIR="$HOME/.config/openclaw-media"
SECRETS="$SECRETS_DIR/secrets.env"
if [ "${SKIP_SECRETS:-0}" != "1" ]; then
  echo "==> 4/7 安装密钥到固定位置 + 写入 shell 启动文件"
  RC="$HOME/.zshrc"
  SRC_SECRETS="$HERE/secrets.env"
  # 把密钥复制到固定位置，脱离 installer-core/ 文件夹位置依赖
  if [ -f "$SRC_SECRETS" ]; then
    mkdir -p "$SECRETS_DIR"
    cp "$SRC_SECRETS" "$SECRETS"
    chmod 600 "$SECRETS"
    echo "    密钥已安装 -> $SECRETS"
  else
    echo "    [!] 未找到 $SRC_SECRETS，跳过密钥安装和 shell 自动加载"
  fi
  if [ -f "$SECRETS" ]; then
    # 清理旧的、指向 installer-core/ 的残留 source 行（避免 installer-core 文件夹挪位后失效）
    if [ -f "$RC" ] && grep -qF "$SRC_SECRETS" "$RC" 2>/dev/null; then
      tmp_rc="$(mktemp)"
      { grep -vF "$SRC_SECRETS" "$RC" || true; } > "$tmp_rc"
      mv "$tmp_rc" "$RC"
      echo "    已清理指向 installer-core/ 的旧 source 行"
    fi
    LINE="[ -f \"$SECRETS\" ] && source \"$SECRETS\"  # media-gen keys"
    if ! grep -qF "$SECRETS" "$RC" 2>/dev/null; then
      echo "$LINE" >> "$RC"
      echo "    已在 $RC 添加 source 行（指向固定位置）"
    else
      echo "    $RC 已包含 source 行，跳过"
    fi
  fi
  # 当前会话也加载一次
  # shellcheck disable=SC1090
  [ -f "$SECRETS" ] && source "$SECRETS"

  echo "==> 5/7 校验密钥 + 安装图片 skill（豆包 Seedream）"
  if [ -z "${MINIMAX_API_KEY:-}" ] || echo "${MINIMAX_API_KEY:-}" | grep -q "在此粘贴"; then
    echo "    [!] MINIMAX_API_KEY 还没填，请编辑 $SECRETS"
  else
    echo "    MINIMAX_API_KEY 已设置"
  fi
  [ -n "${ARK_API_KEY:-}" ] && echo "    ARK_API_KEY 已设置"
  [ -n "${VOLCENGINE_API_KEY:-}" ] && echo "    VOLCENGINE_API_KEY 已设置"
  [ -n "${SEEDANCE_ENDPOINT:-}" ] && echo "    SEEDANCE_ENDPOINT = ${SEEDANCE_ENDPOINT}"
  if [ "${SKIP_MEDIA:-0}" != "1" ]; then
    bash "$HERE/scripts/setup-seedream.sh" || echo "    [!] seedream 安装出错，可单独重跑 bash scripts/setup-seedream.sh"
  fi
else
  echo "==> 4/7 跳过密钥安装 (SKIP_SECRETS=1)"
  echo "==> 5/7 跳过密钥校验和 Seedream key 注入 (SKIP_SECRETS=1)"
fi

echo "==> 6/7 写入媒体生成笔记到 ~/clawd/TOOLS.md（让 agent 知道怎么用）"
bash "$HERE/scripts/merge-tools-notes.sh" || echo "    [!] 笔记合并出错，可单独重跑 bash scripts/merge-tools-notes.sh"

echo "==> 7/7 安装 OpenClaw 微信插件 + 电源设置（需 sudo）"
if [ "${SKIP_WEIXIN:-0}" != "1" ]; then
  bash "$HERE/scripts/setup-openclaw-weixin.sh" || echo "    [!] 微信脚本出错（可能需要 sudo 密码或网络），可单独重跑 bash scripts/setup-openclaw-weixin.sh"
else
  echo "    跳过 (SKIP_WEIXIN=1)"
fi

echo
if [ "${SKIP_SECRETS:-0}" != "1" ]; then
  echo "完成。新开一个终端，或先运行：source \"$SECRETS\""
else
  echo "完成。当前跳过了密钥安装；如需恢复 key，请运行顶层脚本的 INSTALL_PHASE=secrets。"
fi
echo "然后用 installer-core/ 里的 README.md 的命令测试。"
