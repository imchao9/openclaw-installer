# OpenClaw 机械式装机流程

这套流程把 AI 限制在安装前决策和安装后分析两个边界。
中间的同步、安装、一次定向修复、验证和报告回收全部由确定性脚本执行。

## 流程

```text
assess（只读）
  -> AI 阅读 assessment summary 并决定是否批准
  -> apply（机械执行，不插入 AI 操作）
  -> AI 阅读 final summary 并只处理剩余异常
```

`assess` 会运行 raw preflight、checkpoint scan 和八秒的现有运行时探测。
它不会安装 CLT、App、配置或服务。
干净机器上的 `not_installed` 是正常状态。
已有机器上的 `auth_unavailable` 会被提前标为 Codex OAuth 人工项。

`apply` 必须显式携带 `assess` 生成的 `run_id` 和 `--approve-assessment`。
它会重新执行硬门禁、安装 CLT、同步唯一匹配的 profile、安装缺失项、重新 scan、最多 repair 一次、分层验证并回收报告。
它不会自动处理 Codex OAuth、微信扫码或 macOS TCC。

## 命令

先生成只包含 IP 和账号的 inventory。

```bash
ANSIBLE_USER=mac \
bash scripts/ansible/ips-to-inventory.sh private-secrets/ips.txt \
  > /tmp/openclaw-inventory.ini
```

为一次装机生成固定的 run id。

```bash
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
```

已有 SSH key 时执行只读 assessment。

```bash
bash scripts/ansible/mechanical-rollout.sh assess \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID"
```

只有密码登录时使用一次性隐藏输入。

```bash
bash scripts/ansible/mechanical-rollout.sh assess \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID" \
  --prompt-ssh-password
```

AI 只读取下面的文件做安装前判断。

```text
scripts/ansible/runs/<run-id>/reports/<host>/mechanical-assessment-summary.json
```

批准后执行机械安装。

```bash
bash scripts/ansible/mechanical-rollout.sh apply \
  -i /tmp/openclaw-inventory.ini \
  --run-id "$RUN_ID" \
  --approve-assessment \
  --private-secrets \
  --prompt-sudo-password
```

如果 SSH 也仍使用密码，可以同时加入 `--prompt-ssh-password`。
完整安装默认包含 Chrome、Obsidian、CC-Switch、钉钉等额外 App；只有明确希望跳过时才添加 `--core-only`。
密码只进入权限为 `0600` 的临时 Ansible vars 文件，并在 runner 退出时删除。
密码、token 和完整 OAuth URL不会写入报告。

## 硬门禁

apply 在任何安装动作前验证以下条件。

- SSH preflight 成功。
- macOS 与 CPU 架构存在唯一支持的 package profile。
- 根卷空间满足要求。
- 显式 profile 与自动推导 profile 完全一致。
- rsync 只能使用 `.package-build/openclaw-<profile>/`，禁止同步通用 `install-files/`。
- `DIST_MANIFEST.json` 的 profile、目标架构和所有必需资产 SHA256 全部匹配。

任何硬门禁失败都会在安装前停止。

## 状态语义

- `pass`：主链路和模型验收全部通过。
- `pass_with_warnings`：主链路通过，但存在豆包、微信或 TCC 等非阻塞项。
- `manual_action_required`：安装完成，但 Codex OAuth 等主链路人工项尚未完成。
- `fail`：必需安装 phase、最终 checkpoint、OpenClaw 或 Codex 非鉴权验证失败。
- `blocked`：assessment 阶段发现磁盘、系统或 profile 硬门禁不满足。

apply 的退出码为 `0` 时自动部分完成。
退出码 `10` 表示需要人工操作。
退出码 `30` 表示必需安装或验证失败，需要 AI 读取报告后定向处理。

## 报告

每次 run 使用独立目录，不覆盖历史证据。

```text
scripts/ansible/runs/<run-id>/reports/<host>/
```

主要文件如下。

- `mechanical-assessment-summary.json`：安装前 AI 判断输入。
- `preflight-report.json`：系统、架构、磁盘、sudo、GUI、CLT 和 Python 状态。
- `assessment-install-report.json`：安装前 checkpoint 与计划原因。
- `install-result.json`：合并后的两次 attempt、phase 计时和 blocking 分类。
- `install-result-<run-id>-attempt-<n>.json`：不可覆盖的单次 attempt 证据。
- `validation-report.json`：Codex/OpenClaw 分层验证、reason code 和耗时。
- `final-install-report.json`：最终 checkpoint。
- `mechanical-final-summary.json`：安装后 AI 分析输入。

远端 phase 日志保存在下面的目录。

```text
~/openclaw-installer-run/reports/runs/<run-id>/attempt-<n>/install-logs/
```

## 构建 profile 包

机械 apply 要求 profile 构建包含机器可读 manifest。

```bash
OVERWRITE_DIST=1 bash scripts/build-dist.sh macos15-x64
```

x64 profile 使用 universal DingTalk DMG，而不是文件名带 `arm64` 的旧资产。
构建阶段会记录七个必需资产的 SHA256。
目标机同步完成后会重新计算这些 SHA256。
