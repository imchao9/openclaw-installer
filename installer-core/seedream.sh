#!/usr/bin/env bash
# seedream.sh — 豆包 Seedream 文生图（火山 Ark）
# 用法：
#   ./seedream.sh "提示词" [size] [outfile]
# 示例：
#   ./seedream.sh "一只橘猫坐在窗台上，阳光洒进来" 2K ~/cat.png
# 默认：size=2K，输出到 ~/clawd/seedream_<时间>.png
# 需要环境变量 ARK_API_KEY（或脚本会尝试 source 同目录 secrets.env）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -z "${ARK_API_KEY:-}" ] && [ -f "$HERE/secrets.env" ] && source "$HERE/secrets.env"
: "${ARK_API_KEY:?未设置 ARK_API_KEY}"

PROMPT="${1:?需要提示词：./seedream.sh \"提示词\" [size] [outfile]}"
SIZE="${2:-2K}"
OUT="${3:-$HOME/clawd/seedream_$(date +%Y%m%d_%H%M%S).png}"
MODEL="${SEEDREAM_MODEL:-doubao-seedream-5-0-260128}"

echo "生成中... model=$MODEL size=$SIZE"
body=$(python3 -c "import json,sys;print(json.dumps({'model':sys.argv[1],'prompt':sys.argv[2],'size':sys.argv[3],'output_format':'png','watermark':False}))" "$MODEL" "$PROMPT" "$SIZE")
res=$(curl -s --max-time 120 --location 'https://ark.cn-beijing.volces.com/api/v3/images/generations' \
  -H 'Content-Type: application/json' -H "Authorization: Bearer $ARK_API_KEY" --data "$body")

url=$(echo "$res" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data'][0]['url'])" 2>/dev/null || true)
if [ -z "$url" ]; then
  echo "生成失败："; echo "$res" | python3 -m json.tool 2>/dev/null || echo "$res"; exit 1
fi
curl -s -o "$OUT" "$url"
echo "已保存：$OUT"
ls -la "$OUT"
