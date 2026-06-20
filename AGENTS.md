# OpenClaw Installer Agent Notes

## 安装执行约定

- 新电脑安装要优先完成主链路：系统设置、基础软件、App、配置恢复、启动项和最终状态汇总。
- 如果某个非关键步骤耗时异常或卡住，不要一直阻塞主安装。应设置明确超时，记录为 warning/problem，继续安装后续步骤。
- 可后置排查的步骤包括 Codex CLI npm fallback、OpenClaw/ClawHub skills、媒体/office skills、Codex smoke、Clash Party helper、Seedream key 注入等。
- 最终回复必须说明哪些步骤完成、哪些步骤被跳过/超时/失败、问题日志路径、以及可单独重跑的命令。
- 只有系统基础依赖、必需 App 安装、私有配置恢复、CLIProxy/OpenClaw/Clash 基础可用性这类主链路问题，才应影响整机安装结论。
