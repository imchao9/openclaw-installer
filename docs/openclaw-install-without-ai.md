# OpenClaw 安装说明：不用 AI 的执行方式与故障处理

适用对象：需要在新 Mac 或已使用过的 Mac 上安装 OpenClaw/Codex/CLIProxyAPI/Clash Party 的执行人员。本文只描述人工命令和 Ansible 命令，不依赖 AI 代操作。

## 一、安装包结构

推荐把这些目录放在目标机器同一个父目录下：

```text
openclaw-installer-run/
  install-openclaw.sh
  install-files/
  private-secrets/          # 可选，有密钥和登录态时放这里
  01-Clash单独安装/          # 可选，有独立 Clash 包时放这里
```

说明：

- `install-files/` 是非敏感安装包，包含脚本、installer-core、离线 App/PKG/DMG。
- `private-secrets/` 只放私密配置，不应该上传公开网盘。
- `upload-packages/openclaw-layer-index.json` 与 common、architecture、CLT layers 用于局域网 HTTP 分发。
- 修改安装脚本后，如果要走 HTTP 分发，必须先重建 `upload-packages/` 包。

重建 HTTP 分发包：

```bash
cd /Users/cm/Documents/Me/Project/openclaw-installer
OVERWRITE_LAYERED_DIST=1 bash scripts/build-layered-dist.sh
```

## 二、非 Ansible：单台机器手动安装

### 1. 准备目标机器

目标机器需要：

- macOS，优先 Apple Silicon。
- 登录到桌面用户。
- 有管理员密码。
- 磁盘空间建议大于 30 GB。
- 如果需要远程执行，先打开 System Settings > General > Sharing > Remote Login。

### 2. 拷贝安装目录

把安装目录放到目标机器，例如：

```bash
mkdir -p ~/openclaw-installer-run
```

如果是本机 U 盘或 AirDrop，直接复制 `install-openclaw.sh`、`install-files/`、可选的 `private-secrets/` 和 Clash 包。

如果使用局域网 HTTP 包：

```bash
cd /Users/cm/Documents/Me/Project/openclaw-installer
PORT=8765 bash scripts/serve-package-http.sh
```

目标机器下载：

```bash
LAYER_INDEX_URL=http://<installer-host-ip>:8765/openclaw-layer-index.json \
LAYER_INDEX_CHECKSUM_URL=http://<installer-host-ip>:8765/openclaw-layer-index.sha256 \
PACKAGE_PROFILE=macos15-arm64 \
REMOTE_RUN_DIR=$HOME/openclaw-installer-run \
bash fetch-package-over-http.sh
```

macOS 26.2+ 设置 `PACKAGE_PROFILE=macos26-arm64`。

### 3. 一条命令安装

```bash
cd ~/openclaw-installer-run
bash install-openclaw.sh
```

默认流程：

1. 找到独立 Clash 包时先安装 Clash。
2. 跑 base 阶段，安装 Node、Codex、OpenClaw、CLIProxyAPI、启动项、Dashboard launcher 等。
3. 找到 `private-secrets/` 时恢复密钥、登录态、Clash profiles 和媒体密钥。
4. 默认不改写 Codex/OpenClaw 入口到本机 CLIProxyAPI。
5. 默认做 OpenClaw 和 Codex endpoint 验收。

需要让 Codex/OpenClaw 都走本机 CLIProxyAPI：

```bash
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
```

强制重跑已完成阶段：

```bash
bash install-openclaw.sh --force
```

跳过验收：

```bash
bash install-openclaw.sh --skip-validate
```

### 4. 分阶段重跑

进入 install-files：

```bash
cd ~/openclaw-installer-run/install-files
```

常用阶段：

```bash
INSTALL_PHASE=base bash install-new-macbook.sh
INSTALL_PHASE=extras bash install-new-macbook.sh
PRIVATE_SECRETS_DIR=../private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh
INSTALL_PHASE=codex-cli bash install-new-macbook.sh
INSTALL_PHASE=cliproxy bash install-new-macbook.sh
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
INSTALL_PHASE=deepseek bash install-new-macbook.sh
INSTALL_PHASE=office-skills bash install-new-macbook.sh
INSTALL_PHASE=validate bash install-new-macbook.sh
```

只扫描，不修改机器：

```bash
bash ~/openclaw-installer-run/install-files/installer-core/scripts/check-install-checkpoints.sh \
  --run-dir ~/openclaw-installer-run
```

### 5. 手动验收

```bash
openclaw status
openclaw health
openclaw models list
openclaw infer model run --model cliproxy/gpt-5.5 --prompt "Reply exactly: OK"
INSTALL_PHASE=validate bash ~/openclaw-installer-run/install-files/install-new-macbook.sh
```

需要跑完整 Codex exec 验收：

```bash
CODEX_VALIDATION_MODE=exec \
EXPECTED_TEXT=HELLO_OK \
CODEX_HELLO_PROMPT="Reply with exactly HELLO_OK" \
OPENCLAW_HELLO_PROMPT="Reply with exactly HELLO_OK" \
INSTALL_PHASE=validate bash ~/openclaw-installer-run/install-files/install-new-macbook.sh
```

## 三、Ansible：批量安装

### 1. 生成 inventory

不要直接把带 appSecret 的 `private-secrets/ips.txt` 当 inventory。先提取 IP：

```bash
cd /Users/cm/Documents/Me/Project/openclaw-installer
ANSIBLE_USER=mac bash ansible/ips-to-inventory.sh private-secrets/ips.txt > /tmp/openclaw-inventory.ini
```

如果目标机用户名不是 `mac`，替换 `ANSIBLE_USER`。

### 2. 完整批量流程

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/rollout.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

流程顺序：

```text
bootstrap-clt -> preflight -> scan -> sync -> install missing -> validate -> final scan -> collect reports
```

### 3. HTTP 分发模式

先在安装源机器启动 HTTP：

```bash
PORT=8765 bash upload-packages-package-http.sh
```

再执行同步：

```bash
OPENCLAW_PACKAGE_BASE_URL=http://<installer-host-ip>:8765 \
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/sync.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

注意：HTTP 分发读取的是 `upload-packages/openclaw-macos*.tar.zst`，脚本修改后要先跑：

```bash
OVERWRITE_DIST=1 bash build-dist.sh all
```

### 4. 分步执行

只做 preflight：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/preflight.yml \
  --ask-pass
```

只同步当前 `install-files/`：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/sync.yml \
  -e sync_private_secrets=1 \
  --ask-pass
```

只按 checkpoint 补缺失项：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/install-missing.yml \
  --ask-pass
```

只抓报告：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/collect-reports.yml \
  --ask-pass
```

只验证：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/validate-agents.yml \
  --ask-pass
```

精确验收 `HELLO_OK`：

```bash
LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
ansible-playbook -i /tmp/openclaw-inventory.ini ansible/playbooks/validate-agents.yml \
  -e expected_text=HELLO_OK \
  -e codex_validation_mode=exec \
  -e codex_hello_prompt='Reply with exactly HELLO_OK' \
  -e openclaw_hello_prompt='Reply with exactly HELLO_OK' \
  --ask-pass
```

### 5. 看报告

```bash
bash ansible/summarize-reports.sh
```

关键报告：

- `preflight-report.json`：SSH、macOS、架构、磁盘、sudo、GUI session。
- `install-result.json`：执行过的 phase、exit code、日志尾部。
- `validation-report.json`：Codex/OpenClaw 验收结果。
- `final-install-report.json`：最终 checkpoint 状态。
- `final-install-plan.env`：下一步需要补什么。

## 四、常见问题与处理

### 1. SSH 连不上

现象：Ansible unreachable，或 `ssh` 超时。

处理：

```bash
ping <ip>
nc -vz <ip> 22
ssh mac@<ip>
```

如果 22 端口不通，在目标机打开 Remote Login。若端口通但认证失败，先手动 SSH 一次或重新配置公钥。

### 2. sudo 需要 TTY

现象：`sudo: a terminal is required to read the password`。

处理：

- 手动安装时直接在目标机终端执行。
- SSH 执行时使用 `ssh -tt`。
- Ansible 需要密码时加 `--ask-become-pass`。
- 脚本支持 `SUDO_PASSWORD`，但不要在共享日志里明文打印。

### 3. Command Line Tools 不兼容

现象：CLT 安装失败、macOS 版本不匹配。

处理：

- macOS 15.x 使用 `Command_Line_Tools_for_Xcode_16.4.dmg`。
- macOS 26.2+ Apple Silicon 使用 `Command_Line_Tools_26.5_Apple_silicon.dmg`。
- 旧系统遇到不兼容时先跳过 CLT 26.5，不要强装。

### 4. `zstd` 不存在，无法解包 tar.zst

现象：HTTP 包下载成功但解压失败。

处理：

```bash
brew install zstd
```

如果目标机还没有 Homebrew，优先使用包内 `Homebrew.pkg` 或改走 rsync 同步 `install-files/`。

### 5. `codex: command not found`

处理：

```bash
cd ~/openclaw-installer-run/install-files
INSTALL_PHASE=codex-cli bash install-new-macbook.sh
source ~/.zshenv
command -v codex
codex --version
```

脚本会优先链接 `Codex.app` 内置 CLI，不可用时再 npm fallback。

### 6. Codex 验收超时或一直 Reconnecting

默认验收现在使用 `/v1/responses` endpoint，避免 `codex exec` 在无人值守时卡住。

先查 CLIProxyAPI：

```bash
launchctl print gui/$(id -u)/local.openclaw-installer.cliproxy
lsof -nP -iTCP:8317 -sTCP:LISTEN
```

再跑 endpoint 验收：

```bash
cd ~/openclaw-installer-run/install-files
INSTALL_PHASE=validate bash install-new-macbook.sh
```

只有需要模型输出精确文本时，才切到：

```bash
CODEX_VALIDATION_MODE=exec INSTALL_PHASE=validate bash install-new-macbook.sh
```

### 7. CLIProxyAPI 8317 没监听

处理：

```bash
cd ~/openclaw-installer-run/install-files
INSTALL_PHASE=cliproxy bash install-new-macbook.sh
launchctl kickstart -k gui/$(id -u)/local.openclaw-installer.cliproxy
lsof -nP -iTCP:8317 -sTCP:LISTEN
```

如果远程管理页面 403，检查 `~/.cli-proxy-api/config.yaml` 里的 `remote-management.allow-remote`。

### 8. Clash Party 已安装但 7890 不通

处理：

1. 打开 `/Applications/Clash Party.app`。
2. 确认订阅和代理已启动。
3. 如果 GUI 在但 sidecar 没起来，可手动启动：

```bash
"/Applications/Clash Party.app/Contents/Resources/sidecar/mihomo" \
  -d "$HOME/Library/Application Support/mihomo-party/work"
```

检查：

```bash
curl --socks5-hostname 127.0.0.1:7890 -I https://chatgpt.com
```

### 9. private-secrets 缺失

现象：`PLAN_NEEDS_SECRETS=1`，Codex/OpenClaw auth 或媒体密钥缺失。

处理：

```bash
cd ~/openclaw-installer-run/install-files
PRIVATE_SECRETS_DIR=../private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh
```

不要把 `private-secrets/` 上传公开网盘。

### 10. Doubao 输入法安装了但未配置好

现象：`doubao_configured=false`，或麦克风授权缺失。

处理：

```bash
cd ~/openclaw-installer-run/install-files
bash installer-core/scripts/configure-doubao-input.sh
bash installer-core/scripts/enable-doubao-input.sh
```

如果 TCC 数据库拒绝访问，需要在 System Settings 里手动处理麦克风、输入法或辅助功能权限。

### 11. Weixin 插件或二维码

默认安装跳过微信扫码，避免无人值守安装卡住。需要时再运行：

```bash
cd ~/openclaw-installer-run
bash install-openclaw.sh --with-weixin
```

微信二维码登录属于人工步骤。

### 12. Seedream key 注入超时

Seedream 是非关键步骤，超时不会让整机安装失败。修复后单独重跑：

```bash
cd ~/openclaw-installer-run/install-files
bash installer-core/scripts/setup-seedream.sh
```

### 13. OpenClaw/Clash 自启动设置超时

处理：

```bash
cd ~/openclaw-installer-run/install-files
bash installer-core-mac-autostart.sh
launchctl list | grep openclaw-installer
```

重启或重新登录后确认 OpenClaw Gateway、CLIProxyAPI、Clash Party 都恢复。

### 14. App 首次启动被 macOS 阻止

处理：

```bash
sudo xattr -dr com.apple.quarantine /Applications/OpenClaw.app
sudo xattr -dr com.apple.quarantine /Applications/Codex.app
sudo xattr -dr com.apple.quarantine "/Applications/OpenClaw Dashboard.app"
```

首次打开 Codex、OpenClaw、向日葵时，仍可能需要在系统设置里授予屏幕录制、辅助功能等 TCC 权限。

## 五、推荐收尾检查清单

在每台机器上确认：

```bash
command -v node
command -v npm
command -v codex
command -v openclaw
lsof -nP -iTCP:8317 -sTCP:LISTEN
openclaw health
cd ~/openclaw-installer-run/install-files && INSTALL_PHASE=validate bash install-new-macbook.sh
```

Ansible 汇总里应尽量达到：

```text
base=ok
secrets=ok
cliproxy=ok
clash=ok 或 needs_gui
codex_cfg=ok
openclaw_cfg=ok
codex_val=pass
openclaw_val=pass
```

`needs_gui` 通常表示机器需要人工打开或登录 Clash Party，不代表 OpenClaw 安装器主链路失败。
