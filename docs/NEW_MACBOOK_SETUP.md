# 新 MacBook 安装与打包说明

这份说明以当前脚本为准。安装分两阶段：第一阶段只装非敏感内容，第二阶段再恢复密钥、登录态和私密配置。

## 一句话流程

```bash
# 1. 在旧机器重新生成非敏感交付目录
env OVERWRITE_DIST=1 bash scripts/build-dist.sh

# 2. 可选：打成单文件 zip
bash scripts/make-package.sh upload-packages/openclaw.zip

# 3. 在新 MacBook 上进入复制好的安装目录，执行统一入口
bash install-openclaw.sh

# 4. 如需确认或修复默认路由：让 Codex 和 OpenClaw 都走本机 CLIProxyAPI
bash install-openclaw.sh --with-cliproxy-config
```

如果 `private-secrets/` 不在 `install-files/` 同级，第二阶段改成：

```bash
PRIVATE_SECRETS_DIR=/path/to/private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh
```

## 目录结构

推荐复制到新 MacBook 后保持：

```text
some-folder/
  install-files/
    install-new-macbook.sh
    apply-person-key.sh
    installer-core/
    openclaw-team/
  private-secrets/
```

`install-files/` 可以给别人或新机器；`private-secrets/` 只能私下传输，不要公开上传。

## 推荐：统一入口

把 `install-openclaw.sh`、`install-files/` 或 `02-新电脑初始化/`、`01-Clash单独安装/` 和可选的 `private-secrets/` 放在同一个父目录后执行：

```bash
bash install-openclaw.sh
```

它会自动识别目录布局，并按顺序执行：

1. `01-Clash单独安装/install-clash.sh` 或 `05-Clash单独安装/install-clash.sh`，如果存在；
2. `INSTALL_PHASE=base bash install-new-macbook.sh`；
3. `INSTALL_PHASE=office-skills bash install-new-macbook.sh`；
4. `PRIVATE_SECRETS_DIR=... INSTALL_PHASE=secrets bash install-new-macbook.sh`，如果找到 `private-secrets/`；
5. 自动执行 CLIProxy 配置适配；也可用 `INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh` 单独重跑；
6. `INSTALL_PHASE=validate bash install-new-macbook.sh`，让 OpenClaw 和 Codex 分别回复 `HELLO_OK` 作为验收。

统一入口默认设置 `SKIP_WEIXIN=1`，不在无人值守安装里等待微信二维码扫码。需要当场连接微信时：

```bash
bash install-openclaw.sh --with-weixin
```

成功完成的阶段会记录到 `.openclaw-install-state/`。失败后修复脚本或环境，再重跑同一条命令即可；如需强制重跑已完成阶段：

```bash
bash install-openclaw.sh --force
```

只想看计划不改机器：

```bash
bash install-openclaw.sh --dry-run
```

## 第一次：base 阶段

在新 MacBook 上：

```bash
cd install-files
INSTALL_PHASE=base bash install-new-macbook.sh
```

不传 `INSTALL_PHASE` 时默认也是 `base`：

```bash
bash install-new-macbook.sh
```

当前 base 阶段会自动处理：

| 类别 | 内容 |
|---|---|
| 系统检查 | 检查 Command Line Tools 是否已存在；不存在且包内有兼容的离线 DMG 时自动安装。macOS 15.x 使用 `Command_Line_Tools_for_Xcode_16.4.dmg`；macOS 26.2+ 使用 CLT 26.5 |
| 系统基础 | 安装 Node.js v24.16.0，并执行 `npm install -g @openai/codex` 安装 Codex CLI |
| App | Google Chrome、Codex、OpenClaw、Obsidian、CC-Switch、向日葵、钉钉 |
| PKG | Node.js、Command Line Tools DMG 内的 PKG、向日葵 DMG 内的 PKG |
| 输入法 | 豆包输入法不随安装包自动安装，用户按需手动安装 |
| OpenClaw 入口 | 安装 `OpenClaw Dashboard.app`、`OpenClaw Weixin Connect.app` 和对应 `.command` 到 `/Applications`，可从 Finder 的“应用程序”直接打开；默认不启动扫码连接流程 |
| OpenClaw | CLI、Gateway、Dashboard 助手、微信连接助手 |
| Codex/OpenClaw installer-core | 运行 `installer-core/install.sh`，第一阶段强制跳过 dotfiles 和 secrets |
| 媒体能力 | 非敏感媒体脚本与 skill 安装 |
| Office / 数据分析 skills | 安装 `data-analysis-skill`、`data-analysis`、`xlsx-cn`、`excel-xlsx`、`pptx`、`markdown-converter`、`minimax-excel-sheet`、`tencent-docs` |
| CLIProxyAPI | 安装 `~/.local/bin/CLIProxyAPI`，写入用户级 LaunchAgent，默认使用 `~/.cli-proxy-api/config.yaml` |
| 运行保障 | 接电不休眠、Cross-Session Tasks skill、OpenClaw Gateway 自恢复、CLIProxyAPI 自恢复、Clash Party 登录后自动打开 |

当前 base 阶段不会自动安装：

- Clash Verge / Clash Party。它们仍然放在 `05-Clash单独安装/` 单独分发，建议在 base 前先安装。
- Homebrew。脚本会跳过自动安装；如新机器确实需要 brew，单独安装。

如果临时不想安装 Office / 数据分析 skills：

```bash
SKIP_OFFICE_SKILLS=1 bash install-openclaw.sh
# 或
bash install-openclaw.sh --skip-office-skills
```

向日葵安装后首次远控通常还需要在系统设置里手动授予屏幕录制、辅助功能等权限。macOS 不允许普通安装脚本默认代点这类 TCC 隐私授权；如需远控，打开系统设置后手动勾选。

## 第二次：secrets 阶段

把 `private-secrets/` 私下复制到新 MacBook，推荐放在 `install-files/` 同级，然后执行：

```bash
cd install-files
INSTALL_PHASE=secrets bash install-new-macbook.sh
```

第二阶段会恢复：

- `~/.codex/auth.json`
- `~/.codex/config.toml`
- `~/.openclaw/openclaw.json`
- `deepseek/deepseek-v4-pro` 次要模型：从 `private-secrets/deepseek-key.csv` 读取 key，OpenAI BaseURL 为 `https://api.qnaigc.com/v1`，Anthropic BaseURL 元数据为 `https://anthropic.qnaigc.com`
- `~/.cli-proxy-api/config.yaml`
- `~/.cli-proxy-api/*.json`
- `~/.config/openclaw-media/secrets.env`
- `~/.config/openclaw-installer/private-notes/key.txt`
- `~/.config/openclaw-installer/private-notes/安装.txt`
- `~/.config/openclaw-installer/clash-party/subscriptions.txt`
- `~/Applications/OpenClaw Clash Party Setup.app`
- `~/Applications/OpenClaw Clash Party Setup.command`

如果原目标文件已存在，会先备份为 `.bak.YYYYMMDD_HHMMSS`。

`deepseek-key.csv` 支持两列：`name,key`。默认使用第一条非空 key；需要指定时：

```bash
DEEPSEEK_KEY_NAME=dp2 INSTALL_PHASE=secrets bash install-new-macbook.sh
```

已完成安装后只想补这个模型，可以单独运行：

```bash
INSTALL_PHASE=deepseek bash install-new-macbook.sh
```

Clash 订阅地址不会打印到终端。第二阶段会把订阅保存到用户私密目录，并生成双击助手；打开后会把第一个订阅 URL 复制到剪贴板，再打开 Clash Party 或 Clash Verge。

## 默认：Codex/OpenClaw 走 CLIProxyAPI

完成 base 阶段后，CLIProxyAPI 会以用户级 LaunchAgent 启动；完成 secrets 阶段后，会恢复 `private-secrets/cliproxy/config.yaml` 和 auth JSON。需要让 Codex 和 OpenClaw 都连接本机 CLIProxyAPI 时执行：

```bash
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
```

默认配置：

- API 地址：`http://127.0.0.1:8317/v1`
- API Key：`open-api`
- 模型：`gpt-5.5`
- Codex provider：`custom`
- OpenClaw provider：`cliproxy`

该步骤会先备份原文件，再改写 `~/.codex/auth.json`、`~/.codex/config.toml` 和 `~/.openclaw/openclaw.json`。如果只想重装或重启 CLIProxyAPI，不改 Codex/OpenClaw，执行：

```bash
INSTALL_PHASE=cliproxy bash install-new-macbook.sh
```

## 按人替换 OpenClaw/Codex key

如果手上有 `private-secrets/key.csv`，可以按姓名写入当前机器的 OpenClaw、Claude settings 和 Codex API key：

```bash
bash scripts/apply-person-key.sh 张伟俊
bash scripts/apply-person-key.sh 张伟俊 --apply
bash scripts/apply-person-key.sh 张伟俊 --apply --ensure-runtime
```

默认映射：

- `private-secrets/key.csv` 第一列是姓名；也可以用 `KEY_CSV=/path/to/key.csv` 指定其他位置。
- OpenClaw 会按当前 `~/.openclaw/openclaw.json` 的 primary model 自动选择 provider，但固定读取 `claude-opus-4-8` 列。
- 如果存在 `~/.claude/settings.json`，会用同一个 `claude-opus-4-8` key 替换 `env.ANTHROPIC_AUTH_TOKEN`。
- `gpt-5.5` 列会写入 Codex；只有当 `~/.codex/auth.json` 已是 `OPENAI_API_KEY` 结构时才自动替换，OAuth 登录态会跳过。
- 同一个 `gpt-5.5` key 也会注册到 OpenClaw 的 `openai/gpt-5.5` 模型，别名 `gpt55`，并作为默认 heartbeat 保活模型。

不带 `--apply` 只检查，不改文件；真正写入时会备份原 JSON，且不打印完整 key。

带 `--ensure-runtime` 时默认只安装 ClawHub skill `cross-session-tasks`。`openclaw-token-save` 只作为手动可选项保留，不建议给小白默认安装。

目标机不方便带 CSV 时，从 `private-secrets/person-key-commands.md` 复制对应人员命令，或直接传 key：

```bash
OPENCLAW_API_KEY='sk-...' CODEX_API_KEY='sk-...' bash scripts/apply-person-key.sh --apply --ensure-runtime
```

远端处理示例：

```bash
REMOTE_HOST=cm@192.168.0.250 REMOTE_PASSWORD='123456' bash scripts/apply-person-key.sh 张伟俊 --apply --ensure-runtime
```

## 开机后自动恢复

base 阶段会自动执行这部分。如果要单独重跑：

```bash
bash scripts/installer-core-mac-autostart.sh
```

它会配置：

- 接电时系统不休眠，只按 `DISPLAY_SLEEP_MINUTES` 关闭屏幕；
- `localhost`、`127.0.0.1`、`::1`、`0.0.0.0`、`*.local` 不走系统代理；
- OpenClaw 默认工具权限设为 `full`；
- OpenClaw 安装 `cross-session-tasks` skill；
- OpenClaw Gateway 使用 LaunchAgent 恢复；
- CLIProxyAPI 使用用户级 LaunchAgent 恢复；
- Clash Party 使用用户级 LaunchAgent，在用户登录后自动打开。

如果 Clash Party 的 App 名称不是 `Clash Party.app`：

```bash
CLASH_APP_NAME="Clash Verge" bash scripts/installer-core-mac-autostart.sh
```

GUI App 的 LaunchAgent 只在“用户登录后”生效。机器刚开机但没人登录时，Clash Party 不会打开。

## 微信连接

微信连接不放进 base 阶段等待扫码。需要连接微信时，双击：

```bash
install-files/openclaw-team/OpenClaw Weixin Connect.app
```

它会打开终端窗口，安装或刷新 OpenClaw 微信插件，并显示二维码或链接。手机微信扫码后，回到 OpenClaw 点击 Recheck，或重启 OpenClaw。

如需跳过微信相关 installer-core：

```bash
SKIP_WEIXIN=1 INSTALL_PHASE=base bash install-new-macbook.sh
```

## 失败后重跑

脚本可以重复执行。某块已成功时，用环境变量跳过：

```bash
SKIP_BASE_PKGS=1 bash install-new-macbook.sh
SKIP_APPS=1 bash install-new-macbook.sh
bash install-new-macbook.sh
SKIP_OPENCLAW_FIX=1 bash install-new-macbook.sh
SKIP_OPENCLAW_SETUP=1 bash install-new-macbook.sh
SKIP_POWER=1 bash install-new-macbook.sh
SKIP_AUTOSTART=1 bash install-new-macbook.sh
```

常见组合：

```bash
# App 已经装好，只补 OpenClaw 和媒体配置
SKIP_BASE_PKGS=1 SKIP_APPS=1 bash install-new-macbook.sh

# 只跑 installer-core/ 里的 OpenClaw 与媒体配置
cd installer-core
bash install.sh

# 只恢复密钥/登录态
INSTALL_PHASE=secrets bash install-new-macbook.sh

# 只恢复私密配置并生成 Clash Party 助手
PRIVATE_SECRETS_DIR=/path/to/private-secrets bash installer-core/scripts/install-private-configs.sh
```

## 打包给新电脑

重建非敏感交付目录：

```bash
env OVERWRITE_DIST=1 bash scripts/build-dist.sh
```

`install-files/` 会包含安装入口、文档、`installer-core/` 和 `openclaw-team/` 离线安装包，不包含密钥、登录态、订阅地址等私密文件。

生成 zip：

```bash
bash scripts/make-package.sh
```

指定输出路径：

```bash
bash scripts/make-package.sh ~/Desktop/openclaw-installer-new-macbook.zip
```

指定局域网分享文件：

```bash
bash scripts/make-package.sh upload-packages/openclaw.zip
```

打包脚本会排除：

- `private-secrets/`
- `key.csv`
- `secrets.env`
- `auth.json`
- `config.toml`
- `openclaw.json`
- `.claude/settings.json`
- `key.txt`
- `安装.txt`
- 已存在的传输 zip，例如 `openclaw-team.zip`、`installer-core 3.zip`、`upload-packages/*.zip`、`install-files/*.zip`
- 安装日志、`.DS_Store`、`.server/`、`http-server.pid`

如需局域网分享：

```bash
PORT=8765 bash scripts/upload-packages-package-http.sh
```

本机检查：

```bash
curl -I --noproxy '*' http://127.0.0.1:8765/openclaw-macos26-arm64.tar.zst
```

目标机下载推荐使用 HTTP 断点续传，而不是首次大包 rsync：

```bash
PACKAGE_URL=http://<installer-host-ip>:8765/openclaw-macos26-arm64.tar.zst \
CHECKSUM_URL=http://<installer-host-ip>:8765/openclaw-macos26-arm64.sha256 \
bash scripts/fetch-package-over-http.sh
```

补装非核心应用：

```bash
cd ~/openclaw-installer-run/install-files
INSTALL_PHASE=extras bash install-new-macbook.sh
```

## 私密文件位置

这些文件默认放在 `private-secrets/`，不会进入 `install-files/` 或 zip：

```text
private-secrets/installer-core/secrets.env
private-secrets/installer-core/dotfiles/.codex/auth.json
private-secrets/installer-core/dotfiles/.codex/config.toml
private-secrets/installer-core/dotfiles/.openclaw/openclaw.json
private-secrets/cliproxy/config.yaml
private-secrets/cliproxy/auth/*.json
private-secrets/openclaw-team/auth.json
private-secrets/openclaw-team/config.toml
private-secrets/openclaw-team/openclaw.json
private-secrets/openclaw-team/key.txt
private-secrets/openclaw-team/安装.txt
private-secrets/person-key-commands.md
```

## 安装后验收

新开终端检查：

```bash
node --version
npm --version
openclaw --version
openclaw gateway status
openclaw gateway health
openclaw status --deep
INSTALL_PHASE=validate bash install-new-macbook.sh
openclaw config get tools.profile
openclaw config get tools.exec.security
openclaw config get agents.defaults.elevatedDefault
networksetup -getproxybypassdomains Wi-Fi
launchctl print "gui/$(id -u)/local.openclaw-installer.clash-party"
launchctl print "gui/$(id -u)/local.openclaw-installer.cliproxy"
lsof -nP -iTCP:8317 -sTCP:LISTEN
curl --noproxy '*' -I http://127.0.0.1:8317/
mmx --version
```

再确认以下 App 能正常打开：

- `/Applications/Google Chrome.app`
- `/Applications/Codex.app`
- `/Applications/OpenClaw.app`
- `/Applications/Obsidian.app`
- `/Applications/DingTalk.app`
- Clash Party 或 Clash Verge
- CC-Switch
