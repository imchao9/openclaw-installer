# 下载源与更新清单

更新时间：2026-06-19

这个文件记录 `upload-packages/source-assets/openclaw-team/` 里离线安装包的公开来源，方便后续定期更新。真正给脚本读取的清单在 `scripts/assets/download-sources.yml`。

当前策略：平时只保存下载源；准备重新打上传包前，再手动刷新公开直链资产。

## 更新原则

- 可稳定 `HEAD` 的直链可以定期检查，发现 SHA 变化后下载到 `upload-packages/source-assets/openclaw-team/`，再跑安装验证。
- GitHub Release 类软件优先看最新 release，再选择 macOS arm64/aarch64 的 `.dmg` 或 `.pkg`。
- 钉钉、向日葵这类厂商页的最终文件 URL 可能临时变化，先记录官方下载页，更新时人工下载。
- Apple Command Line Tools 属于 Apple Developer 下载，当前按固定人工来源处理；它不进入定期直链检查。
- 豆包输入法不打进安装包，也不自动安装；用户需要时从官方页面手动下载。

## 可定期检查的直链

下表的 `openclaw-team/...` 是资产文件名；实际存放根目录统一为
`upload-packages/source-assets/openclaw-team/`。

| 软件 | 当前文件 | 当前版本 | 下载地址 | 来源页 | 本地 SHA256 |
| --- | --- | --- | --- | --- | --- |
| Codex App | `openclaw-team/Codex.dmg` | latest | <https://persistent.oaistatic.com/codex-app-prod/Codex.dmg> | <https://developers.openai.com/codex/app> | `c9a9ee11986a0f880158b81e459b64b684642396f49eaf7fa0e018f4a8c37b42` |
| Node.js | `openclaw-team/node-v24.16.0.pkg` | 24.16.0 | <https://nodejs.org/dist/v24.16.0/node-v24.16.0.pkg> | <https://nodejs.org/en/download/archive/v24.16.0> | `65843aafbab48999c9d5f072746836965340c9ef2fbf17a377d3f919dcb0cb7a` |
| Obsidian | `openclaw-team/Obsidian-1.12.7.dmg` | 1.12.7 | <https://github.com/obsidianmd/obsidian-releases/releases/download/v1.12.7/Obsidian-1.12.7.dmg> | <https://github.com/obsidianmd/obsidian-releases/releases> | `3b85c13b4ce55512e86e170a7cd2a494e2db695ac888c0601e153cb85b77881b` |
| Homebrew pkg | `openclaw-team/Homebrew.pkg` | latest | <https://github.com/Homebrew/brew/releases/latest/download/Homebrew.pkg> | <https://brew.sh/> | `4e84f5f9eea65fed4179d7e2125e7266aea406f9b850e006d69d0bfdcb0a5a85` |
| Google Chrome | `openclaw-team/googlechrome.dmg` | stable | <https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg> | <https://support.google.com/chrome/a/answer/9915669> | `e92b5182e9c018ac448fc157c2929e60e98ad507c88ddbeb598d154bd9156aaa` |
| CC-Switch | `openclaw-team/CC-Switch-v3.15.0-macOS.dmg` | 3.15.0 | <https://github.com/farion1231/cc-switch/releases/download/v3.15.0/CC-Switch-v3.15.0-macOS.dmg> | <https://github.com/farion1231/cc-switch/releases> | `137c9a970d8ea8736cf042de5f36865729b33ff37e99f1d3971b86fcc731ee87` |
| Clash Verge Rev | `openclaw-team/Clash Verge 2.5.1.dmg` | 2.5.1 | <https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.1/Clash.Verge_2.5.1_aarch64.dmg> | <https://github.com/clash-verge-rev/clash-verge-rev/releases> | `a2016a77922b67ac058b6c247aad7809893b429f238ee7aeee1fee6e3bf70e2b` |
| Clash Party | `openclaw-team/clash-party-macos-1.9.5-arm64.pkg` | 1.9.5 | <https://github.com/mihomo-party-org/clash-party/releases/download/v1.9.5/clash-party-macos-1.9.5-arm64.pkg> | <https://github.com/mihomo-party-org/clash-party/releases> | `8ee492664162468e1cd8345b163c1e0e04936a8dff494f6f7c334a409bf7f414` |
| OpenClaw | `openclaw-team/OpenClaw-2026.5.26.dmg` | 2026.5.26 | <https://github.com/openclaw/openclaw/releases/download/v2026.5.26/OpenClaw-2026.5.26.dmg> | <https://github.com/openclaw/openclaw/releases> | `ea8a2b40a6b7b943402e3f948a938e7860071cda8b67e80c949ff28ca5778b1e` |

只检查直链是否可用，不下载：

```bash
bash scripts/check-download-sources.sh
```

打包前重新下载公开直链资产：

```bash
bash scripts/refresh-download-assets.sh
```

如果使用 profile 打包脚本，也可以让打包前自动刷新：

```bash
REFRESH_DOWNLOAD_ASSETS=1 OVERWRITE_DIST=1 bash scripts/build-dist.sh all
```

先预览会刷新哪些资产：

```bash
bash scripts/refresh-download-assets.sh --dry-run
```

只刷新某一个资产：

```bash
bash scripts/refresh-download-assets.sh --asset codex-app
```

## 人工来源

| 软件 | 当前文件 | 当前版本 | 下载 / 来源页 | 说明 |
| --- | --- | --- | --- | --- |
| 豆包输入法 | 不打包 | manual | <https://srf.doubao.com/pc> | 用户手动下载安装。 |
| 钉钉 | `openclaw-team/DingTalk_v8.3.30-Installer_55620621_arm64.dmg` | 8.3.30 | <https://www.dingtalk.io/download/> | 厂商下载页更新，直链不保证稳定。 |
| 向日葵 AweSun | `openclaw-team/AweSun_v16.5.0.30757_arm64.dmg` | 16.5.0.30757 | <https://sunlogin.oray.com/en/download/> | 厂商下载页更新，直链不保证稳定。 |
| 向日葵 AweSun Intel | `openclaw-team/AweSun_v16.5.0.30905_x86_64.dmg` | 16.5.0.30905 | <https://dw.oray.com/sl/mac/AweSun_v16.5.0.30905_x86_64.dmg> | 固定 Intel 直链并校验 SHA-256。 |
| Apple Command Line Tools for Xcode 16.4 | `openclaw-team/Command_Line_Tools_for_Xcode_16.4.dmg` | 16.4 | <https://developer.apple.com/download/all/> | Apple Developer 手动下载，当前固定不做定期更新。 |
| Apple Command Line Tools 26.5 Apple Silicon | `openclaw-team/Command_Line_Tools_26.5_Apple_silicon.dmg` | 26.5 | <https://developer.apple.com/download/all/> | Apple Developer 手动下载，当前固定不做定期更新。 |

## 更新后验收

1. 先运行 `bash scripts/refresh-download-assets.sh --dry-run` 预览会下载哪些公开直链资产。
2. 准备打包时运行 `bash scripts/refresh-download-assets.sh`，脚本会下载到 `upload-packages/source-assets/openclaw-team/` 并更新 `scripts/assets/download-sources.yml` 里的 SHA。
3. 人工来源的软件按表格下载或保持不变：Apple Command Line Tools、钉钉、向日葵、豆包输入法。
4. 如果下载后的文件名或版本号变化，手动更新 `scripts/assets/download-sources.yml` 和本文件中的版本、URL、文件名。
5. 下载资产统一保存到 canonical `upload-packages/source-assets/openclaw-team/` 后重新打包；可以直接用 `REFRESH_DOWNLOAD_ASSETS=1 OVERWRITE_DIST=1 bash scripts/build-dist.sh all`。
6. 至少在一台测试 Mac 上跑：

```bash
bash install-openclaw.sh --skip-secrets
```

如果改动 Node、Codex、OpenClaw、CLIProxyAPI 或 Clash 相关包，再补跑：

```bash
INSTALL_PHASE=validate bash install-files/install-new-macbook.sh
```
