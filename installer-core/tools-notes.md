<!-- MEDIA-GEN-NOTES-START (由 installer-core/install.sh 自动写入；删此标记块即可重置) -->
## 图片生成 → 统一用 Seedream（不要用 mmx）

- 出图一律走 `doubao-seedream-skill`（火山 Ark），不再用 mmx-cli。
- Skill 路径：`~/clawd/skills/doubao-seedream-skill/`，入口 `seedream_api.py`。
- 默认模型：`doubao-seedream-5-0-260128`（别名 `5.0`，skill 默认值）。
- Key：skill 读 `VOLCENGINE_API_KEY`（值 = `installer-core/secrets.env` 里的 ARK key，图片/视频共用同一个 Ark key）。install.sh 已写入 skill 的 `.env`。
- 依赖：`requests`、`python-dotenv`（install.sh 用 pip --user 装）。
- 用法：`cd ~/clawd/skills/doubao-seedream-skill && python3 seedream_api.py "提示词" -o ~/clawd/generated`
  - `-m` 模型(5.0/4.5/4.0/3.0-t2i)、`-s` 尺寸(默认2048x2048,可2K/4K)、`-i` 参考图(图生图)、`--group` 组图、`--tools web_search`(仅5.0)。

## 音乐/语音 → mmx-cli（MiniMax，cn 区）

- 全局包：`npm install -g mmx-cli`（install.sh 已装）。生成音乐/语音/视频/文本/搜索。图片改用 Seedream。
- key 是 **cn 区** key。`mmx auth login` 自动区域检测对它会失败，所以每条命令都要同时带 `--api-key <key>` 和 `--region cn`。
- key 在 `installer-core/secrets.env`（install.sh 会复制一份到固定位置 `~/.config/openclaw-media/secrets.env`）的 `MINIMAX_API_KEY`，已写进 `~/.zshrc` 自动加载。
- 音乐示例：`mmx music generate --api-key "$MINIMAX_API_KEY" --region cn --prompt "..." --lyrics "[verse]..." --out song.mp3 --quiet`

## 视频 → ~/clawd/bin/seedance.sh（火山 Ark）

- 纯 curl 脚本，install.sh 已复制到永久位置 `~/clawd/bin/seedance.sh`（不要再去 installer-core/ 里找）。
- key 在固定位置 `~/.config/openclaw-media/secrets.env` 的 `ARK_API_KEY` + 接入点 `SEEDANCE_ENDPOINT`（已写进 ~/.zshrc）。
- 用法：`ARK_API_KEY="$ARK_API_KEY" bash ~/clawd/bin/seedance.sh create '<json>' ~/clawd/generated`
- ⚠️ 轮询别用后台 `while/sleep` 长循环（会被环境杀掉）。用脚本自带的 `wait <task_id>` 前台跑，或用 cron 定时 `status <task_id>` 查。
- 视频 URL 24 小时过期，生成后立刻下载。

## 新机器还原（一次到位）

- `cd installer-core && bash install.sh`：还原 .codex/.claude/.openclaw 配置 + 装 mmx-cli + 两个 skill + 写密钥 + 装微信插件。
- 跳过开关：`SKIP_DOTFILES=1` / `SKIP_MEDIA=1` / `SKIP_WEIXIN=1`。
<!-- MEDIA-GEN-NOTES-END -->
