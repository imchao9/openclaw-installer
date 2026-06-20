#!/usr/bin/env bash
# restore.sh — 新机器一键还原（保留为兼容入口，实际全部交给 install.sh）
# install.sh 现在是完整入口：配置文件 + 媒体工具/skill + 密钥 + 微信插件
# 用法：  cd installer-core && bash restore.sh
# 可选环境变量（透传给 install.sh）：
#   SKIP_DOTFILES=1  跳过还原 .codex/.claude/.openclaw 配置
#   SKIP_MEDIA=1     跳过 mmx-cli / skill 安装
#   SKIP_WEIXIN=1    跳过微信插件（需要 sudo 改电源设置）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================"
echo " OpenClaw 还原脚本 -> 交给 install.sh 执行完整还原"
echo "================================================================"
exec bash "$HERE/install.sh"
