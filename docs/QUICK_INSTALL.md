# OpenClaw 快速装机说明

这份说明给执行装机的人使用。默认执行“完整安装”，会安装并配置：

- OpenClaw、Codex/ChatGPT 客户端、CLIProxyAPI、Clash Party
- Google Chrome、Obsidian、CC-Switch、钉钉
- Codex 与 OpenClaw 的 CLIProxyAPI 路由
- 可用的私有配置、启动项和最终验收

当前支持的安装 profile：

| 目标机器 | profile |
| --- | --- |
| macOS 14，Intel | `macos14-x64` |
| macOS 15，Intel | `macos15-x64` |
| macOS 15，Apple Silicon | `macos15-arm64` |
| macOS 26，Apple Silicon | `macos26-arm64` |

macOS 26 Intel 暂无完整安装包，不要选择其它 profile 强行安装。

## 方式一：从控制机远程安装（推荐）

目标 Mac 需要开机联网、开启“远程登录”，并有一个管理员账号。macOS 14 Intel
还需要先安装 Command Line Tools。控制机需要准备好对应 profile 的构建目录；私密配置放在
仓库根目录的 `private-secrets/`，该目录不会提交到 Git。

先创建 inventory，例如：

```ini
[openclaw_targets]
target-1 ansible_host=192.0.2.10 ansible_user=mac
```

先做只读检查：

```bash
RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
bash scripts/ansible/mechanical-rollout.sh assess \
  -i /path/to/inventory.ini \
  --run-id "$RUN_ID" \
  --prompt-ssh-password
```

检查结果没有硬阻塞后，执行完整安装：

```bash
bash scripts/ansible/mechanical-rollout.sh apply \
  -i /path/to/inventory.ini \
  --run-id "$RUN_ID" \
  --approve-assessment \
  --private-secrets \
  --prompt-ssh-password \
  --prompt-sudo-password
```

不要加 `--core-only`，否则会主动跳过 Chrome、Obsidian、CC-Switch、钉钉等完整安装项。

最终结果位于：

```text
scripts/ansible/runs/<run-id>/reports/<host>/mechanical-final-summary.json
```

`pass` 表示完整通过；`pass_with_warnings` 表示主链路通过但仍有非阻塞人工项；
`manual_action_required` 通常表示需要人工完成 OAuth、扫码或 macOS 权限授权；`fail` / `blocked`
需要按报告中的原因处理后重跑。

## 方式二：生成离线目录后在目标机安装

控制机先组装对应 profile：

```bash
bash scripts/build-offline-delivery.sh \
  --profile macos14-x64 \
  --output-root /path/to/output
```

把生成的 `OpenClaw-Install-<profile>/` 整体复制到目标 Mac。`private-secrets/` 只应通过可信渠道
单独传递，并放到交付目录中。随后在目标 Mac 执行：

```bash
cd OpenClaw-Install-<profile>
bash install-openclaw.sh
```

安装中断后可直接重跑；要强制重做已完成阶段时使用：

```bash
bash install-openclaw.sh --force
```

## 安装后快速检查

在目标 Mac 上执行：

```bash
INSTALL_PHASE=scan bash install-new-macbook.sh
INSTALL_PHASE=validate bash install-new-macbook.sh
```

完整安装应确认：Chrome、Obsidian、CC-Switch、钉钉存在；CLIProxyAPI 在
`127.0.0.1:8317` 可用；Codex 的 `config.toml` 与 `auth.json` 使用 CLIProxyAPI 当前 API key；
OpenClaw 和 Codex 验收均通过。

更完整的流程和故障状态解释见 [`mechanical-rollout.md`](mechanical-rollout.md)，macOS 14 Intel
的特殊准备见 [`INTEL_MACOS14_SETUP.md`](INTEL_MACOS14_SETUP.md)。
