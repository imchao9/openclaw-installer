# OpenClaw Installer Agent Notes

## 安装执行约定

- 新电脑安装要优先完成主链路：系统设置、基础软件、App、配置恢复、启动项和最终状态汇总。
- 如果某个非关键步骤耗时异常或卡住，不要一直阻塞主安装。应设置明确超时，记录为 warning/problem，继续安装后续步骤。
- 可后置排查的步骤包括 Codex CLI npm fallback、OpenClaw/ClawHub skills、媒体/office skills、Codex smoke、Clash Party helper、Seedream key 注入等。
- 最终回复必须说明哪些步骤完成、哪些步骤被跳过/超时/失败、问题日志路径、以及可单独重跑的命令。
- 只有系统基础依赖、必需 App 安装、私有配置恢复、CLIProxy/OpenClaw/Clash 基础可用性这类主链路问题，才应影响整机安装结论。

## 构建目录清理约定

- `.package-build/<profile>/` 是可重建的 profile staging，不是最终交付物；最终交付物以 `upload-packages/*.tar.zst` 及对应 `.sha256` 为准。
- 构建失败或尚未完成验包时保留当前 profile 的 staging，供定位 manifest、资产、架构或 DMG 问题。
- 只有在 archive、checksum、manifest、目标架构及必要 DMG 验证全部通过后，才清理本次 `.package-build/<profile>/`。
- 清理时只删除本次 profile 的 staging，不默认删除整个 `.package-build/`，避免影响其它正在构建或等待验收的 profile。
- CLIProxy 等可复用编译缓存放在独立的 `.build-cache/` 并保留，不应随 profile staging 一起删除。
- 自动化清理必须显式启用（例如 `CLEAN_BUILD_AFTER_SUCCESS=1`），验证失败时不得执行清理；在该开关尚未实现前，验包成功后再手动删除对应 profile 目录。
