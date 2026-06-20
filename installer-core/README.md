# 媒体生成工具包 — 新电脑还原指南

这个文件夹包含在新电脑上还原"音乐 + 语音 + 视频"生成能力所需的一切。

## 里面有什么

- `secrets.env` — API 密钥文件；默认已移出到上级 `private-secrets/`，不要打进 `install-files/`
- `install.sh` — 一键安装脚本（装 CLI + 写密钥 + 钉区域 + 装图片 skill）
- `scripts/setup-seedream.sh` — 图片 skill（豆包 Seedream）安装脚本
- `seedance.sh` — Seedance 视频工作流脚本（建任务/轮询/下载）
- `README.md` — 本文件

## 四个能力分别是

| 能力 | 工具 | 密钥 | 区域/端点 |
|---|---|---|---|
| 音乐 / 语音 | `mmx-cli` + `minimax-multimodal` skill | `MINIMAX_API_KEY` | cn 区，必须带 `--region cn` |
| 图片 | `doubao-seedream-skill`（python） | `VOLCENGINE_API_KEY` | 火山 Ark，模型 `doubao-seedream-5-0-260128` |
| 视频 | `seedance.sh`（curl 调火山 Ark） | `ARK_API_KEY` | 接入点 `SEEDANCE_ENDPOINT` |

---

## 新电脑安装步骤

1. 把整个 `installer-core/` 文件夹拷到新电脑（U盘/AirDrop/git 私库都行）。

2. 确认有 Node.js（没有就先装 LTS：https://nodejs.org 或用 nvm）。

3. 如需媒体能力，把上级 `private-secrets/installer-core/secrets.env` 私下复制回 `installer-core/secrets.env`，并确认 `MINIMAX_API_KEY` 是完整 key
   （`sk-api` 开头那串，**别截断**，中间不能有省略号）。
   ARK 的 key 和接入点也在这个私密文件里。

4. 运行安装脚本：
   ```bash
   cd installer-core
   bash install.sh
   ```

5. 新开一个终端窗口（让密钥生效），或手动 `source installer-core/secrets.env`。

完成。下面是各能力的用法。

---

## 音乐生成（MiniMax）

关键坑：这个 key 是 cn 区的，但 `mmx auth login` 的自动区域检测对它会失败，
所以**不要依赖 login**，每条命令都同时带 `--api-key` 和 `--region cn`。

```bash
mmx music generate \
  --api-key "$MINIMAX_API_KEY" --region cn \
  --prompt "Warm acoustic folk, gentle and healing, fingerpicked guitar, slow tempo" \
  --lyrics "[verse]
第一段歌词
[chorus]
副歌最抓耳的一句" \
  --out ~/song.mp3 --quiet
```

prompt 写法：风格 + 情绪 + 乐器 + 速度（英文识别更稳）。
歌词用 `[intro] [verse] [pre-chorus] [chorus] [bridge] [outro]` 分段。

## 语音合成（MiniMax TTS）

```bash
mmx speech generate \
  --api-key "$MINIMAX_API_KEY" --region cn \
  --text "今天天气真好，要不要出去走走？" \
  --voice male-qn-qingse \
  --out ~/speech.mp3 --quiet
```

或直接 curl（t2a 接口，支持情绪/语速）：
```bash
curl -X POST https://api.minimaxi.com/v1/t2a_v2 \
  -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "speech-2.8-hd",
    "text": "今天是不是很开心呀，当然了！",
    "voice_setting": {"voice_id":"male-qn-qingse","speed":1,"vol":1,"pitch":0,"emotion":"happy"},
    "audio_setting": {"sample_rate":32000,"bitrate":128000,"format":"mp3","channel":1}
  }' --output ~/speech.mp3
```

---

## 图片生成（Seedream / 火山 Ark）

图片统一用 `doubao-seedream-skill`（不再走 mmx）。脚本会自动装 skill + Python 依赖，
并把 `VOLCENGINE_API_KEY` 写进 skill 的 `.env`。install.sh 已含这一步，也可单独跑：

```bash
cd installer-core && bash scripts/setup-seedream.sh
```

生成一张图（默认模型 doubao-seedream-5-0-260128）：
```bash
cd ~/clawd/skills/doubao-seedream-skill
python3 seedream_api.py "一只橘猫坐在窗台上，阳光洒进来" -o ~/clawd/generated
```

常用参数：`-m` 模型（5.0/4.5/4.0/3.0-t2i）、`-s` 尺寸（默认 2048x2048，可用 2K/4K）、
`-i` 参考图（图生图）、`--group` 组图。默认模型是 5.0，支持文生图/图生图/联网搜索。

---

## 视频生成（Seedance / 火山 Ark）

用 `seedance.sh`，确保 `ARK_API_KEY` 已在环境里（install.sh 已配置）。

最简单的文本生视频：
```bash
cd installer-core
./seedance.sh create '{
  "model": "ep-20260529154657-lqv5p",
  "content": [
    { "type": "text", "text": "一只橘猫坐在窗台上，阳光洒进来，缓缓眨眼" }
  ],
  "ratio": "16:9",
  "duration": 5,
  "resolution": "720p",
  "generate_audio": true,
  "watermark": false
}' ~/
```
脚本会自动建任务 → 每15秒轮询 → 完成后下载到指定目录。

其他命令：
```bash
./seedance.sh status <task_id>    # 查单个任务
./seedance.sh wait   <task_id> ~/ # 继续等已有任务并下载
./seedance.sh list                # 列最近任务
./seedance.sh delete <task_id>    # 取消/删除任务
```

参数参考：`duration` 4-12 秒；`ratio` 16:9 / 9:16 / 1:1 / 21:9 / adaptive；
`resolution` 480p/720p/1080p；图生视频时加 `image_url` 项并设 `role: first_frame`。

注意：生成的视频 URL 24 小时过期，任务历史保留 7 天，所以**生成后立刻下载**。

---

## 安全提醒

- `secrets.env` 含真实密钥，别公开分享、别提交到公共仓库。
- 想放 git 的话，加到 `.gitignore`，或用私有仓库。
- key 如果泄露，去对应控制台（MiniMax / 火山引擎）吊销重建。
