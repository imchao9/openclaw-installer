#!/usr/bin/env bash
# setup-seedream.sh — 安装豆包 Seedream 文生图 skill（统一的图片生成入口）
# 做三件事：
#   1. 通过 ClawHub 安装 doubao-seedream-skill（若已存在则跳过）
#   2. 安装 Python 依赖（requests / python-dotenv）
#   3. 把 ARK key 写进 skill 的 .env（变量名 VOLCENGINE_API_KEY）
# 需要环境变量 ARK_API_KEY（或 VOLCENGINE_API_KEY）；脚本会尝试 source 同目录上层 secrets.env
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$HERE/.." && pwd)"

PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
export PATH

find_real_python3() {
  local candidate
  for candidate in "${PYTHON3_BIN:-}" /opt/homebrew/bin/python3 /usr/local/bin/python3 "$(command -v python3 2>/dev/null || true)"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    if [ "$candidate" = "/usr/bin/python3" ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
      continue
    fi
    "$candidate" -c 'import sys' >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# 载入密钥
[ -z "${ARK_API_KEY:-}${VOLCENGINE_API_KEY:-}" ] && [ -f "$SETUP_DIR/secrets.env" ] && source "$SETUP_DIR/secrets.env"
KEY="${VOLCENGINE_API_KEY:-${ARK_API_KEY:-}}"
: "${KEY:?未设置 ARK_API_KEY / VOLCENGINE_API_KEY}"

# 模型固定为 5.0（doubao-seedream-5-0-260128，skill 默认值）
MODEL="doubao-seedream-5-0-260128"

echo "==> 1/3 安装 doubao-seedream-skill"
PRIMARY_SKILL_DIR="$HOME/.openclaw/workspace/skills/doubao-seedream-skill"
LEGACY_SKILL_DIR="$HOME/clawd/skills/doubao-seedream-skill"
SKILL_DIR=""

if [ -f "$PRIMARY_SKILL_DIR/seedream_api.py" ]; then
  SKILL_DIR="$PRIMARY_SKILL_DIR"
  echo "    已存在，跳过安装：$SKILL_DIR"
elif [ -f "$LEGACY_SKILL_DIR/seedream_api.py" ]; then
  SKILL_DIR="$LEGACY_SKILL_DIR"
  echo "    已存在，跳过安装：$SKILL_DIR"
elif command -v openclaw >/dev/null 2>&1; then
  openclaw skills install doubao-seedream-skill
  if [ -f "$PRIMARY_SKILL_DIR/seedream_api.py" ]; then
    SKILL_DIR="$PRIMARY_SKILL_DIR"
  elif [ -f "$LEGACY_SKILL_DIR/seedream_api.py" ]; then
    SKILL_DIR="$LEGACY_SKILL_DIR"
  fi
else
  echo "    [!] 未找到 openclaw CLI，无法自动安装 skill。请手动：openclaw skills install doubao-seedream-skill"
fi

echo "==> 2/3 安装 Python 依赖（requests / python-dotenv）"
PYTHON3_BIN="$(find_real_python3 || true)"
if [ -n "$PYTHON3_BIN" ]; then
  "$PYTHON3_BIN" -m pip install --quiet --user requests python-dotenv 2>&1 | tail -2 || \
    echo "    [!] pip 安装出错，请手动：$PYTHON3_BIN -m pip install requests python-dotenv"
else
  echo "    [!] 未检测到真实可用的 python3，跳过依赖安装，避免弹出 macOS Command Line Tools 安装窗口"
fi

echo "==> 3/3 写入 API Key 到 skill 的 .env（VOLCENGINE_API_KEY）"
if [ -n "$SKILL_DIR" ] && [ -d "$SKILL_DIR" ]; then
  cat > "$SKILL_DIR/.env" <<EOF
# 火山引擎 API Key（Ark）— 由 setup/scripts/setup-seedream.sh 写入
  VOLCENGINE_API_KEY="$KEY"
EOF
  chmod 600 "$SKILL_DIR/.env"
  echo "    已写入：$SKILL_DIR/.env"
  echo "    默认模型：$MODEL"
else
  echo "    [!] skill 目录不存在，跳过写 .env"
fi

echo
echo "完成。测试："
if [ -n "${PYTHON3_BIN:-}" ]; then
  echo "  cd $SKILL_DIR && $PYTHON3_BIN seedream_api.py \"一只橘猫坐在窗台上\" -o ~/clawd/generated"
else
  echo "  cd $SKILL_DIR && python3 seedream_api.py \"一只橘猫坐在窗台上\" -o ~/clawd/generated"
fi
