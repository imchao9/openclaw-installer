# OpenClaw 用户安装说明

这份说明给拿到安装包的用户使用。公开安装包里不包含密钥、登录态、Clash 订阅或人员 API key。

## 1. 选择安装包

按目标 Mac 的系统版本选择一个 zip：

| 目标系统 | 使用安装包 |
|---|---|
| macOS 15.x | `openclaw-core-macos15-20260619_211403.zip` |
| macOS 26.x Apple Silicon | `openclaw-core-macos26-20260619_211446.zip` |

如果不确定系统版本，点屏幕左上角 Apple 图标，选择“关于本机”查看 macOS 版本。

## 2. 解压并安装核心组件

把 zip 放到目标 Mac 上，打开“终端”，进入 zip 所在目录。

macOS 15.x：

```bash
unzip openclaw-core-macos15-20260619_211403.zip
cd install-files
bash install-new-macbook.sh
```

macOS 26.x Apple Silicon：

```bash
unzip openclaw-core-macos26-20260619_211446.zip
cd install-files
bash install-new-macbook.sh
```

安装过程中如果系统要求输入本机密码，输入当前 Mac 登录密码即可。终端里输入密码时通常不会显示字符，这是正常现象。

## 3. 核心安装会安装什么

默认核心安装会处理：

- Command Line Tools
- Node.js
- Codex App
- OpenClaw App
- OpenClaw Dashboard / Weixin Connect 启动入口
- OpenClaw CLI / Gateway 修复
- Office / 数据分析相关 skills
- CLIProxyAPI
- 接电不休眠和基础自启动恢复

默认不会安装：

- Chrome、Obsidian、CC-Switch、向日葵、钉钉
- 豆包输入法
- 私密 key、登录态、Clash 订阅

## 4. 可选安装额外 App

如果需要 Chrome、Obsidian、CC-Switch、向日葵、钉钉，核心安装完成后继续执行：

```bash
INSTALL_PHASE=extras bash install-new-macbook.sh
```

向日葵首次使用时，macOS 可能要求手动授予“屏幕录制”“辅助功能”等权限。按系统弹窗进入设置勾选即可。

## 5. 豆包输入法

豆包输入法不随脚本自动安装。需要使用时，请用浏览器打开下面地址下载并手动安装：

```text
https://srf.doubao.com/pc
```

安装完成后，到：

```text
系统设置 / 键盘 / 输入法
```

手动添加或启用豆包输入法。

## 6. 恢复私密配置

公开 zip 里不会包含 `private-secrets/`。如果管理员另外私下提供了 `private-secrets/`，不要把它放进 `install-files/` 里面，而是放在 `install-files/` 旁边。

例如 zip 解压后在 `Downloads/openclaw/`，目录应该长这样：

```text
Downloads/openclaw/
  install-files/
    install-new-macbook.sh
    openclaw-team/
    installer-core/
  private-secrets/
    key.csv
    deepseek-key.csv
    openclaw-team/
    cliproxy/
```

也就是说，`install-files/` 和 `private-secrets/` 是同级目录。上面列出的 `key.csv`、`deepseek-key.csv`、`openclaw-team/`、`cliproxy/` 只有在管理员私下提供时才会有；普通公开安装包里没有这些文件。

如果你当前在 `Downloads/openclaw/` 这个父目录，执行：

```bash
INSTALL_PHASE=secrets bash install-files/install-new-macbook.sh
```

如果你当前已经进入了 `install-files/` 目录，先回到上一层，再执行：

```bash
cd ..
INSTALL_PHASE=secrets bash install-files/install-new-macbook.sh
```

如果 `private-secrets/` 放在其他位置，也可以手动指定路径：

```bash
export PRIVATE_SECRETS_DIR=/path/to/private-secrets
INSTALL_PHASE=secrets bash install-files/install-new-macbook.sh
```

`private-secrets/` 可能包含 API key、登录态、Clash 订阅和私密说明，不要公开上传或转发。

## 7. 验收检查

核心安装完成后，建议检查：

1. 打开 `/Applications/Codex.app`，确认能启动。
2. 打开 `/Applications/OpenClaw.app`，确认能启动。
3. 打开 `/Applications/OpenClaw Dashboard.app`，确认 Dashboard 入口可用。
4. 如果恢复了私密配置，再运行：

```bash
INSTALL_PHASE=validate bash install-files/install-new-macbook.sh
```

## 8. 常见问题

### 提示没有权限

重新运行命令，按提示输入本机登录密码。

### 提示文件不存在

确认已经先执行 `unzip ...`，并且当前目录里有 `install-files/`。

### 安装中断

可以重新进入 `install-files/` 后再次执行：

```bash
bash install-new-macbook.sh
```

脚本会尽量跳过已完成步骤。

### 只想看会做什么，不改机器

```bash
DRY_RUN=1 bash install-new-macbook.sh
```

### 只修 Codex CLI

如果管理员只提供了 `fix-codex-cli.sh`，可以单独执行：

```bash
bash fix-codex-cli.sh
```
