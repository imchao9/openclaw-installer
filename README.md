# OpenClaw 新 MacBook 安装与打包

当前交付分五块：

- `install-files/`：给新 MacBook 的非敏感安装目录。
- `private-secrets/`：密钥、登录态、订阅地址和私密说明，单独保存，默认不进入包。
- `upload-packages/openclaw.zip`：需要局域网单文件分发时使用的最终 zip。
- `docs/user-install-guide.md` / `docs/user-install-guide.pdf`：给安装用户的简明安装说明。
- `docs/download-sources.md` / `scripts/assets/download-sources.yml`：离线安装包的下载源、版本、SHA 和打包前刷新清单。
- `openclaw-install-content-20260607/01-新电脑初始化/`：百度网盘可上传的非敏感初始化包，不含 Clash。
- `openclaw-install-content-20260607/05-Clash单独安装/`：Clash 独立安装包，不放百度网盘。

## 源仓库与生成产物

Git 仓库只保存可审计、可重建的源码、脚本、Markdown 文档和下载清单。以下目录或文件属于本地生成/下载/私密材料，默认不提交：

- `install-files/`
- `.package-build/`
- `upload-packages/` 里的压缩包和校验文件
- `openclaw-team/` 里的 DMG/PKG/tgz 离线安装包
- `docs/*.pdf`
- `private-secrets/`

从源文件重建非源产物：

```bash
bash scripts/build-source-artifacts.sh --overwrite
```

只重建 PDF 文档、不压缩大安装包：

```bash
bash scripts/build-source-artifacts.sh --skip-packages
```

## 最新安装入口

推荐把以下目录放在同一个父目录后，在目标机器执行一个入口：

```text
some-folder/
  install-openclaw.sh
  install-files/ 或 02-新电脑初始化/
  01-Clash单独安装/    # 可选但推荐
  private-secrets/     # 可选；有则自动恢复密钥
```

统一命令：

```bash
bash install-openclaw.sh
```

这个入口会自动执行：Clash 单独安装包（如果存在）-> base 阶段 -> office-skills 阶段 -> secrets 阶段（如果找到 `private-secrets/`）。默认跳过微信扫码连接，避免安装过程卡在二维码等待；需要立即连接微信时加 `--with-weixin`。出错后修复脚本或环境，再重跑同一条命令即可；已完成阶段会用 `.openclaw-install-state/` 标记跳过。如需强制重跑已完成阶段：

```bash
bash install-openclaw.sh --force
```

`cliproxy-config` 默认不自动执行，避免无意改写 Codex/OpenClaw 模型入口；需要时显式运行：

```bash
bash install-openclaw.sh --with-cliproxy-config
```

手动分阶段备用流程如下。先单独安装 Clash 并打开系统代理：

```bash
cd 05-Clash单独安装
bash install-clash.sh
```

然后安装非密钥内容：

```bash
INSTALL_PHASE=base bash install-new-macbook.sh
```

第二次恢复密钥、登录态和私密配置：

```bash
PRIVATE_SECRETS_DIR=/path/to/private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh
```

如果 `private-secrets/` 与 `install-files/` 同级，可以省略 `PRIVATE_SECRETS_DIR`：

```bash
INSTALL_PHASE=secrets bash install-new-macbook.sh
```

## 当前 base 阶段会做什么

- 检查 Command Line Tools 是否已存在；不存在且包内有兼容的离线 DMG 时自动安装。macOS 15.x 使用 `openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg`；macOS 26.2+ 使用 CLT 26.5。
- Command Line Tools 会按系统和机器架构选包：macOS 26.2+ 的 Apple Silicon 优先使用 `openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg`；Intel 或 fallback 场景使用 `openclaw-team/Command_Line_Tools_26.5_Universal.dmg`。当前 core 上传包只带对应 profile 的 CLT，不带 Universal fallback。
- 跳过 Homebrew 自动安装；如目标机需要 brew，手动安装或后续单独处理。
- 安装 Node.js v24.16.0，并执行 `npm install -g @openai/codex` 安装 Codex CLI。
- 安装 Codex、OpenClaw。
- Clash Verge、Clash Party 仍然单独安装，不进入百度网盘初始化包。
- 安装 `OpenClaw Dashboard.app`、`OpenClaw Weixin Connect.app` 和对应 `.command` 到系统级 `/Applications`，方便在 Finder 的“应用程序”里直接打开；默认不启动扫码连接流程。
- 运行 OpenClaw CLI/Gateway 修复脚本。
- 运行 `installer-core/install.sh`，并在第一阶段强制 `SKIP_DOTFILES=1 SKIP_SECRETS=1`。
- 安装数据分析 / Office skills：`data-analysis-skill`、`data-analysis`、`xlsx-cn`、`excel-xlsx`、`pptx`、`markdown-converter`、`minimax-excel-sheet`、`tencent-docs`。如需跳过，可用 `SKIP_OFFICE_SKILLS=1 bash install-openclaw.sh` 或 `bash install-openclaw.sh --skip-office-skills`。
- 安装 CLIProxyAPI 到 `~/.local/bin/CLIProxyAPI`，写入用户级 LaunchAgent，默认监听 `http://127.0.0.1:8317/v1`。
- 配置接电不休眠、OpenClaw Gateway 自恢复、Cross-Session Tasks skill 和 Clash Party 登录后自动打开。

Google Chrome、Obsidian、CC-Switch、向日葵、钉钉属于 `extras` 阶段；豆包输入法不再自动安装，需要用户手动安装：

```bash
INSTALL_PHASE=extras bash install-new-macbook.sh
```

说明：macOS 的辅助功能、屏幕录制等 TCC 隐私权限不能由普通脚本默认代点授权。向日葵首次远控仍需用户在系统设置中手动允许；脚本会尽量避免触发可规避的 Command Line Tools/python3 弹窗。

## 当前 secrets 阶段会做什么

- 恢复 `~/.codex/auth.json`、`~/.codex/config.toml`。
- 恢复 `~/.openclaw/openclaw.json`。
- 从 `private-secrets/deepseek-key.csv` 读取 DeepSeek key，把 `deepseek/deepseek-v4-pro` 注册为 OpenClaw 次要模型；默认取第一条 key，可用 `DEEPSEEK_KEY_NAME=dp2` 指定。
- 恢复 `~/.cli-proxy-api/config.yaml` 和 `~/.cli-proxy-api/*.json` auth 文件，并重载 CLIProxyAPI LaunchAgent。
- 恢复媒体密钥到 `~/.config/openclaw-media/secrets.env`，并写入 `~/.zshrc` source 行。
- 恢复私密说明到 `~/.config/openclaw-installer/private-notes/`。
- 从私密说明提取 Clash 订阅 URL，生成 `~/Applications/OpenClaw Clash Party Setup.app` 和 `.command` 助手。
- 密钥文件恢复后重跑 Seedream key 注入。

## 可选：Codex/OpenClaw 统一走 CLIProxyAPI

如果要让 Codex 和 OpenClaw 都使用本机 CLIProxyAPI，执行：

```bash
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
```

该步骤会备份并改写：

- `~/.codex/auth.json`：写入 `OPENAI_API_KEY=open-api`。
- `~/.codex/config.toml`：设置 `model_provider="custom"`、`model="gpt-5.5"`、`base_url="http://127.0.0.1:8317/v1"`。
- `~/.openclaw/openclaw.json`：设置 `cliproxy/gpt-5.5` provider 为默认模型，并移除旧的 `matrixrouter` / `anthropic` provider。

可通过环境变量覆盖默认值：

```bash
CLIPROXY_BASE_URL=http://127.0.0.1:8317/v1 CLIPROXY_API_KEY=open-api CLIPROXY_MODEL=gpt-5.5 INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
```

## 自动验收：OpenClaw / Codex 回复测试

```bash
INSTALL_PHASE=validate bash install-new-macbook.sh
```

这个阶段会通过命令行让 OpenClaw 回复中文烟测 prompt `你好你是谁`，并默认用最小 `/v1/responses` 请求验证 Codex 的 CLIProxyAPI endpoint 可用。Codex 默认不跑完整 `codex exec`，避免无人值守安装被交互式重连卡住。

```bash
CODEX_VALIDATION_MODE=exec INSTALL_PHASE=validate bash install-new-macbook.sh
```

OpenClaw 会先检查配置只包含 `cliproxy` 和 `deepseek`，主模型为 `cliproxy/gpt-5.5`，fallback 为 `deepseek/deepseek-v4-pro`；然后再用 `openclaw infer model run --prompt "你好你是谁"` 发起真实模型调用。默认使用 OpenClaw 当前默认模型且只要求有非空回复；如果要指定模型，可设置 `OPENCLAW_TEST_MODEL=cliproxy/gpt-5.5`；如果要精确匹配 Codex/OpenClaw 的回复文本，需要设置 `EXPECTED_TEXT`、对应 prompt，并把 Codex 切到 `CODEX_VALIDATION_MODE=exec`。

单独验证某一边：

```bash
bash installer-core/scripts/validate-codex.sh
bash installer-core/scripts/validate-openclaw.sh
```

## 单独运行某个安装 / 验证步骤

目标机器已经有 `~/openclaw-installer-run/` 后，可以按需单独执行某个阶段。

只扫描检查点，不修改机器：

```bash
bash ~/openclaw-installer-run/install-files/installer-core/scripts/check-install-checkpoints.sh \
  --run-dir ~/openclaw-installer-run
```

单独安装或修复某一类能力：

```bash
cd ~/openclaw-installer-run/install-files

# 只跑基础软件安装：Node、Codex、OpenClaw、CLIProxyAPI、自启动等
INSTALL_PHASE=base bash install-new-macbook.sh

# 只跑非核心 App：Chrome、Obsidian、CC-Switch、向日葵、钉钉
INSTALL_PHASE=extras bash install-new-macbook.sh

# 只恢复密钥、登录态、OpenClaw/Codex 私密配置、Clash Party profiles
PRIVATE_SECRETS_DIR=../private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh

# 只安装 / 修复 Codex CLI
INSTALL_PHASE=codex-cli bash install-new-macbook.sh

# 只安装 / 启动 CLIProxyAPI
INSTALL_PHASE=cliproxy bash install-new-macbook.sh

# 只把 Codex/OpenClaw 配置改为走本机 CLIProxyAPI
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh

# 只补 DeepSeek fallback
INSTALL_PHASE=deepseek bash install-new-macbook.sh

# 只安装数据分析 / Office skills
INSTALL_PHASE=office-skills bash install-new-macbook.sh

# 只跑 Codex/OpenClaw 模型验收
INSTALL_PHASE=validate bash install-new-macbook.sh
```

统一入口也可以跳过或打开某些阶段：

```bash
cd ~/openclaw-installer-run

# 跑统一入口，但不做验收
bash install-openclaw.sh --skip-validate

# 跳过 base，只跑后续可用阶段
bash install-openclaw.sh --skip-base

# 跳过 secrets，只做公开包相关阶段
bash install-openclaw.sh --skip-secrets

# 额外启用 cliproxy-config
bash install-openclaw.sh --with-cliproxy-config

# 显式启用微信扫码连接流程；默认跳过，避免无人值守安装卡住
bash install-openclaw.sh --with-weixin
```

单独补装钉钉：

```bash
bash ~/openclaw-installer-run/install-files/installer-core/scripts/install-dingtalk.sh \
  /tmp/DingTalk_v8.3.30-Installer_55620621_arm64.dmg
```

## Ansible 批量验证

Ansible 现在只负责批量编排和报告，单机安装真相源仍然是
`install-openclaw.sh` / `install-new-macbook.sh`。推荐流程是：

```text
bootstrap-clt -> preflight -> scan -> sync -> install missing -> validate -> final scan -> collect reports
```

`private-secrets/ips.txt` 里有 appSecret，不要直接作为 inventory。先只提取 IP：

```bash
ANSIBLE_USER=mac bash scripts/ansible/ips-to-inventory.sh private-secrets/ips.txt > /tmp/openclaw-inventory.ini
```

完整批量流程：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/rollout.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

该流程会先用不依赖远端 Python 的 raw SSH 启动 `bootstrap-clt`：macOS 15.x 使用 `Command_Line_Tools_for_Xcode_16.4.dmg`；macOS 26.2+ 再按目标机 `uname -m` 选择 Command Line Tools DMG，`arm64` 优先传并安装 `Command_Line_Tools_26.5_Apple_silicon.dmg`，Intel 或 Apple Silicon fallback 使用 `Command_Line_Tools_26.5_Universal.dmg`。之后再跑 preflight、生成每台机器的 checkpoint 报告、同步安装包、按缺失项补装、安装后复验并拉回报告。报告目录：

```text
scripts/ansible/reports/<host>/
```

汇总报告：

```bash
bash scripts/ansible/summarize-reports.sh
```

汇总表里的 `preflight`、`install`、`codex_val`、`openclaw_val` 来自结构化 JSON：

- `preflight-report.json`：SSH 已达、macOS、架构、磁盘、sudo 非交互能力、GUI session。
- `install-result.json`：本次补装执行了哪些 phase、每个 phase 的 exit code、最后 80 行日志。
- `validation-report.json`：Codex/OpenClaw 是否验收、exit code、是否使用本机 socks 代理、错误尾部。
- `post-install-report.json` / `final-install-report.json`：安装后的 checkpoint 状态和下一步 plan。

checkpoint 的 plan 现在会把 base 拆成更小的意图：

- `PLAN_INSTALL_NODE`：只补 Node/npm。
- `PLAN_INSTALL_CORE_APPS`：补 Codex、OpenClaw、Clash Party 等核心 App。
- `PLAN_INSTALL_DINGTALK`：只补钉钉。
- `PLAN_FIX_PATH`：只修 shell PATH。
- `PLAN_REPAIR_OPENCLAW`：只跑 OpenClaw CLI/Gateway 修复。
- `PLAN_CONFIGURE_DOUBAO`：豆包输入法已手动安装但输入法注册、菜单或麦克风授权不完整时的提示项。

`install-report.json` 还包含 `secrets_manifest`，只记录私密材料类别是否存在，不输出 key 内容。

只做 preflight：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/preflight.yml \
  --ask-pass
```

只做只读扫描：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/scan.yml \
  -e scan_label=initial \
  --ask-pass
```

只同步包：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/sync.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

只按 checkpoint 补缺失项：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/install-missing.yml \
  --ask-pass
```

只验证 Codex/OpenClaw：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  --ask-pass
```

只验证 Codex：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_openclaw=0 \
  --ask-pass
```

只验证 OpenClaw：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e validate_codex=0 \
  --ask-pass
```

精确验收模型返回 `HELLO_OK`：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml \
  -e expected_text=HELLO_OK \
  -e codex_validation_mode=exec \
  -e codex_hello_prompt='Reply with exactly HELLO_OK' \
  -e openclaw_hello_prompt='Reply with exactly HELLO_OK' \
  --ask-pass
```

批量修复 `codex: command not found`：

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/repair-codex-cli.yml
```

批量验证 Codex 和 OpenClaw：

```bash
ansible-playbook -i /tmp/openclaw-inventory.ini scripts/ansible/playbooks/validate-agents.yml
```

## 单独修复 Codex CLI

如果 zsh 提示 `command not found: codex`，只修 Codex CLI 和 PATH，不重跑整套安装：

```bash
INSTALL_PHASE=codex-cli bash install-new-macbook.sh
exec zsh -l
command -v codex && codex --version
```

## 可选：单独补 DeepSeek 次要模型

如果只想补 DeepSeek，不重跑完整 secrets：

```bash
INSTALL_PHASE=deepseek bash install-new-macbook.sh
```

默认从 `private-secrets/deepseek-key.csv` 读取第一条非空 key，并写入：

- Model ID：`deepseek/deepseek-v4-pro`
- OpenAI BaseURL：`https://api.qnaigc.com/v1`
- Anthropic BaseURL 元数据：`https://anthropic.qnaigc.com`

指定某一行 key：

```bash
DEEPSEEK_KEY_NAME=dp2 INSTALL_PHASE=deepseek bash install-new-macbook.sh
```

## 重新生成 install-files

`install-files/` 是给新电脑复制的目录，里面包含安装入口、文档、`installer-core/` 和 `openclaw-team/` 离线资产，不包含密钥。core 上传包只带对应 profile 需要的 CLT：macOS 15 包带 `Command_Line_Tools_for_Xcode_16.4.dmg`，macOS 26 Apple Silicon 包带 `Command_Line_Tools_26.5_Apple_silicon.dmg`。`openclaw-team/Command_Line_Tools_26.5_Universal.dmg` 保留给 Ansible 或手动 fallback，不默认进入 core 包。

```bash
env OVERWRITE_DIST=1 bash scripts/build-dist.sh
```

如果只是首次生成，且没有旧 `install-files/`：

```bash
bash scripts/build-dist.sh
```

## 重新打包 zip

从仓库根目录打包：

```bash
bash scripts/make-package.sh
```

指定输出为局域网分享文件：

```bash
bash scripts/make-package.sh upload-packages/openclaw.zip
```

打包规则会排除：

- `private-secrets/`
- `key.csv`
- `secrets.env`
- `auth.json`
- `config.toml`
- `openclaw.json`
- `deepseek-key.csv`
- `cliproxy/config.yaml`
- `cliproxy/auth/*.json`
- `.claude/settings.json`
- `key.txt`
- `安装.txt`
- 已存在的传输 zip，例如 `openclaw-team.zip`、`installer-core 3.zip`、`upload-packages/*.zip`、`install-files/*.zip`
- 日志、`.DS_Store`、`.server/` 和 `http-server.pid`

## 按人替换 OpenClaw/Codex key

仓库根目录和 `install-files/` 里都使用同一个入口：

```bash
bash scripts/apply-person-key.sh 张伟俊
bash scripts/apply-person-key.sh 张伟俊 --apply
bash scripts/apply-person-key.sh 张伟俊 --apply --ensure-runtime
```

脚本默认优先从 `private-secrets/key.csv` 读取姓名，兼容旧路径 `key.csv`；这些密钥文件不会进入 `install-files/` 或 zip。`claude-opus-4-8` 列会写入当前 OpenClaw 主模型 provider 和 Claude settings；`gpt-5.5` 列会写入 Codex，并注册为 OpenClaw 可选模型 `openai/gpt-5.5`，别名 `gpt55`，同时作为 heartbeat 保活模型。目标机不方便带 CSV 时，使用 `private-secrets/person-key-commands.md` 中对应人员的命令，或直接传 key：

```bash
OPENCLAW_API_KEY='sk-...' CODEX_API_KEY='sk-...' bash scripts/apply-person-key.sh --apply --ensure-runtime
```

远端替换示例：

```bash
REMOTE_HOST=cm@192.168.0.250 REMOTE_PASSWORD='123456' bash scripts/apply-person-key.sh 张伟俊 --apply --ensure-runtime
```

不带 `--apply` 只做 dry-run；真正写入前会自动备份原 JSON，输出只显示 key 掩码。`--ensure-runtime` 默认只安装 ClawHub skill `cross-session-tasks`。`openclaw-token-save` 可通过 `OPENCLAW_SKILLS="openclaw-token-save cross-session-tasks"` 手动启用，但不建议给小白默认安装。

## 目录职责

- `install-new-macbook.sh`：安装入口，只保留全局配置加载和 `INSTALL_PHASE` 分发。
- `installer-core/lib/installer-common.sh`：通用日志、dry-run、sudo、文件恢复、DMG/PKG、PATH、Codex CLI 基础函数。
- `installer-core/lib/installer-apps.sh`：Node、核心 App、额外 App、OpenClaw 修复、launcher、office skills。
- `installer-core/lib/installer-cliproxy.sh`：CLIProxyAPI 安装、私密文件恢复、Clash Party 运行配置、agent 配置。
- `installer-core/lib/installer-private.sh`：DeepSeek fallback、private-secrets 恢复、电源和启动恢复。
- `installer-core/lib/installer-phases.sh`：base、extras、secrets、cliproxy、validate 等阶段编排。
- `install-openclaw.sh`：目标机统一安装入口，可自动串起 Clash、base、secrets 和可选 `cliproxy-config`。
- `scripts/build-dist.sh`：重建非敏感 `install-files/`，默认排除 Clash 安装包。
- `scripts/make-package.sh`：生成 zip，避免误带敏感文件和嵌套 zip。
- `scripts/apply-person-key.sh`：按人员或显式 key 替换 OpenClaw/Codex key。
- `scripts/installer-core-mac-autostart.sh`：配置接电不休眠、OpenClaw Gateway 自恢复、Clash Party 登录后自动启动。
- `openclaw-team/`：离线安装包和 OpenClaw 修复脚本。
- `installer-core/`：OpenClaw/Codex 非敏感配置、媒体生成工具和微信插件安装。
- `private-secrets/`：私密文件，不要上传公开仓库或公开网盘。

完整安装说明见 [docs/NEW_MACBOOK_SETUP.md](docs/NEW_MACBOOK_SETUP.md)。
