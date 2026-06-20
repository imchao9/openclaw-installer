# Mac 开机后自动恢复 OpenClaw、CLIProxyAPI 和 Clash Party

在目标 Mac 上手动执行一次：

```bash
bash scripts/installer-core-mac-autostart.sh
```

脚本会做这些事：

1. 设置接电时不系统休眠，只允许息屏；
2. 配置 `localhost`、`127.0.0.1`、`::1`、`0.0.0.0`、`*.local` 不走系统代理/Clash Party；
3. 将 OpenClaw 默认工具权限设为 `full`，允许其修改自身配置和执行必要命令；
4. 执行 `openclaw gateway install` 和 `openclaw gateway start`；
5. 写入用户级 LaunchAgent，用户登录后自动打开 Clash Party。

CLIProxyAPI 的 LaunchAgent 由 `install-new-macbook.sh` 配置：

```bash
INSTALL_PHASE=cliproxy bash install-new-macbook.sh
```

推荐长期运行状态：

- Mac 接电；
- 不合盖，或使用外接显示器/键鼠的合盖模式；
- 用户保持登录；
- 屏幕可以关闭，但系统不能 sleep。

验证命令：

```bash
pmset -g custom
openclaw gateway status
openclaw status --deep
openclaw config get tools.profile
openclaw config get tools.exec.security
openclaw config get agents.defaults.elevatedDefault
networksetup -getproxybypassdomains Wi-Fi
launchctl print "gui/$(id -u)/local.openclaw-installer.clash-party"
launchctl print "gui/$(id -u)/local.openclaw-installer.cliproxy"
lsof -nP -iTCP:8317 -sTCP:LISTEN
curl --noproxy '*' -I http://127.0.0.1:8317/
```

如果 Clash Party 的 App 名称不是 `Clash Party.app`，手动指定：

```bash
CLASH_APP_NAME="Clash Verge" bash scripts/installer-core-mac-autostart.sh
```

注意：用户级 LaunchAgent 在“用户登录后”生效。机器刚开机但没人登录时，Clash Party 这类 GUI App 不会启动；CLIProxyAPI 也会在用户登录会话加载后启动。
