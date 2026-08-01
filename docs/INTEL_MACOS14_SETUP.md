# macOS 14 Intel 安装 Runbook

适用于 `macOS 14.x + x86_64`。该 profile 来自实机兼容验证，不与 Apple Silicon
资产混用。

## 前置门禁

- `uname -m` 必须输出 `x86_64`。
- `sw_vers -productVersion` 的主版本必须是 `14`。
- `xcode-select -p` 必须成功。macOS 14 的 CLT 不随包分发，缺失时先在目标机安装兼容版本。
- Intel Codex DMG 必须包含 `x86_64`，Clash Party 必须使用 `*-x64.pkg`。
- `private-secrets/` 始终与公开安装包分开传输。

## 构建分层包并组合 profile

```bash
OVERWRITE_LAYERED_DIST=1 bash scripts/build-layered-dist.sh

OVERWRITE_ASSEMBLED=1 \
bash scripts/assemble-layered-package.sh \
  --profile macos14-x64 \
  --output-dir /tmp/openclaw-macos14-x64
```

默认从 canonical `openclaw-team/Codex-intel.dmg` 和
`openclaw-team/clash-party-macos-1.9.6-x64.pkg` 取资产；只有临时替换候选包时才使用
`CODEX_DMG_X64` / `CLASH_PARTY_PKG_X64` 覆盖。

构建脚本会从现有 CLIProxyAPI 源码自动交叉编译 `darwin/amd64` 二进制，并在打包前
校验架构。编译缓存保留在 `.build-cache/`。macOS 14 Intel 使用：

```text
openclaw-common.tar.zst
openclaw-x64-common.tar.zst
openclaw-layer-index.json
```

macOS 14 不需要 CLT layer；目标机必须预装兼容 CLT。

## 推荐机械装机

先生成只包含目标 IP 和账号的 inventory，再做只读 assessment：

```bash
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"

bash scripts/ansible/mechanical-rollout.sh assess \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID" \
  --prompt-ssh-password
```

确认 summary 的 `expected_profile` 为 `macos14-x64`、`status` 为 `ready` 后执行：

```bash
bash scripts/ansible/mechanical-rollout.sh apply \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID" \
  --approve-assessment \
  --profile macos14-x64 \
  --private-secrets \
  --prompt-ssh-password \
  --prompt-sudo-password
```

## Codex Auth Sync

Auth Sync 是显式可选阶段，不属于无人值守的 mechanical apply 主链路，因为首次注册需要
一次性注册码和管理员批准。

注册码不得写进仓库、日志或命令文件。首次注册时交互读取：

```bash
read -r -s -p "Codex Auth Sync registration code: " CODEX_AUTH_SYNC_CODE
export CODEX_AUTH_SYNC_CODE
INSTALL_PHASE=auth-sync bash install-new-macbook.sh
unset CODEX_AUTH_SYNC_CODE
```

安装器会固定校验默认远端脚本的 SHA-256。若使用自定义
`CODEX_AUTH_SYNC_INSTALL_URL`，还必须同时提供
`CODEX_AUTH_SYNC_INSTALL_SHA256`。

设备进入 `pending` 后等待管理员批准。批准后首次强制同步：

```bash
"$HOME/Library/Application Support/Codex Auth Sync/bin/codex-auth-sync" \
  sync --mode cliproxy \
  --root "$HOME/Library/Application Support/Codex Auth Sync" \
  --force
```

## 验收

```bash
bash installer-core/scripts/check-install-checkpoints.sh \
  --run-dir "$HOME/openclaw-installer-run"

nc -z 127.0.0.1 7890 && echo CLASH_OK
nc -z 127.0.0.1 8317 && echo CLIPROXY_OK
nc -z 127.0.0.1 18789 && echo OPENCLAW_OK

INSTALL_PHASE=validate bash install-new-macbook.sh
```

验收必须同时满足：

- Clash Party 已安装，`127.0.0.1:7890` 代理请求成功；
- CLIProxyAPI 二进制架构与 `uname -m` 一致且监听 8317；
- OpenClaw Gateway 监听 18789；
- Codex 与 OpenClaw 的真实模型调用通过。

## 单阶段重跑

```bash
INSTALL_PHASE=base bash install-new-macbook.sh
PRIVATE_SECRETS_DIR=../private-secrets INSTALL_PHASE=secrets bash install-new-macbook.sh
INSTALL_PHASE=cliproxy bash install-new-macbook.sh
INSTALL_PHASE=cliproxy-config bash install-new-macbook.sh
INSTALL_PHASE=auth-sync bash install-new-macbook.sh
INSTALL_PHASE=validate bash install-new-macbook.sh
```

默认不会因为 Clash 暂时未启动而删除 `proxy-url`。只有明确希望允许 CLIProxy
直连上游时，才设置：

```bash
CLIPROXY_REMOVE_UNHEALTHY_LOCAL_PROXY=1 INSTALL_PHASE=cliproxy bash install-new-macbook.sh
```
