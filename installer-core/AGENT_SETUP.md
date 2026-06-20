# AGENT_SETUP.md — 给新 OpenClaw agent 的执行指令

如果你是一个全新的 OpenClaw agent，用户把这个 `installer-core/` 文件夹给了你，
按下面步骤把环境完整还原。逐步执行，遇到错误先诊断再继续。

## 最快路径：一键还原

```bash
cd installer-core && bash restore.sh
```
这个脚本会依次做：
1. 还原配置文件（旧文件会自动备份）：
   - `~/.codex/auth.json`、`~/.codex/config.toml`
   - `~/.claude/settings.json`
   - `~/.openclaw/openclaw.json`
2. 安装媒体生成工具（mmx-cli；如私密文件存在则写入三个密钥）
3. 安装 OpenClaw 微信插件 + 配置电源不休眠（需 sudo）

可选跳过：`SKIP_WEIXIN=1`（跳过微信/sudo）、`SKIP_MEDIA=1`（跳过 mmx）。

---

## 你要装的能力总览

| 能力 | 工具 | 密钥变量 | 备注 |
|---|---|---|---|
| 音乐/语音 | `mmx-cli` + `minimax-multimodal` skill | `MINIMAX_API_KEY` | cn 区 key，命令必须带 `--api-key *** --region cn` |
| 图片 | `doubao-seedream-skill`（python） | `VOLCENGINE_API_KEY` | 火山 Ark，模型 `doubao-seedream-5-0-260128` |
| 视频 | `seedance.sh`（curl 调火山 Ark） | `ARK_API_KEY` + `SEEDANCE_ENDPOINT` | 纯脚本，无需安装 |

两个 skill 由 install.sh 自动装，也可手动：
```bash
openclaw skills install doubao-seedream-skill   # 图片
openclaw skills install minimax-multimodal       # 音乐/语音/视频/文本
```

## 执行步骤

### 1. 确认前置环境
```bash
node --version && npm --version   # 没有 Node 就先装 LTS：https://nodejs.org
curl --version && python3 --version
```
Node 缺失时，告诉用户需要先装 Node.js，不要硬装。

### 2. 检查密钥是否已提供
```bash
test -f installer-core/secrets.env && echo "secrets.env exists" || echo "secrets.env missing"
```
- 密钥默认不随 `install-files/` 分发。如用户另外提供了 `private-secrets/installer-core/secrets.env`，先私下复制回 `installer-core/secrets.env` 再继续。
- `ARK_API_KEY`、`VOLCENGINE_API_KEY` 和 `SEEDANCE_ENDPOINT` 应该已经填好（图片和视频共用同一个 Ark key）。
- `MINIMAX_API_KEY` 如果还是占位符（含"在此粘贴"字样），**停下来问用户要完整的 `sk-api...` key**。
  注意：这个 key 不能截断、中间不能有省略号，否则鉴权会失败（1004）。

### 3. 跑安装脚本
```bash
cd installer-core && bash install.sh
```
脚本会：装 mmx-cli、装 minimax-multimodal skill、把 mmx 区域钉成 cn、装图片 skill（Seedream）。如果 `secrets.env` 存在，还会复制到固定位置并加进 ~/.zshrc 自动加载。

### 4. 加载密钥到当前会话
```bash
source installer-core/secrets.env
```

### 5. 验证三个能力（可选，会产生少量费用）

音乐：
```bash
mmx music generate --api-key "***" --region cn \
  --prompt "Warm acoustic test" --lyrics "[verse]
test
[chorus]
la la la" --out /tmp/test.mp3 --quiet
```

视频（验证鉴权，不花钱）：
```bash
ARK_API_KEY="$ARK_API_KEY" bash installer-core/seedance.sh list
```
返回 JSON（即使空列表）就说明 key 有效。

图片（豆包 Seedream，会产生少量费用）：
```bash
cd ~/clawd/skills/doubao-seedream-skill
python3 seedream_api.py "一只橘猫坐在窗台上" -o ~/clawd/generated
```
返回本地文件路径就说明成功。默认模型 doubao-seedream-5-0-260128。

## 关键坑（务必记住）

1. **MiniMax 区域**：`mmx auth login` 的自动区域检测对这个 cn key 会失败，
   所以别依赖 login，每条 mmx 命令都带 `--api-key "***" --region cn`。

2. **key 完整性**：MINIMAX key 若被省略号截断会报 1004 鉴权失败。

3. **视频 URL 时效**：Seedance 生成的视频 URL 24 小时过期，
   任务历史保留 7 天，生成后立刻下载。

4. **mmx 本体不能靠复制搬运**：它是 npm 全局包，新机器必须 `npm install -g mmx-cli`。
   `seedance.sh` 则纯靠 curl，复制即用。

详细用法见同目录 `README.md`。
