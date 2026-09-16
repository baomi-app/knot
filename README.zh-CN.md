# Knot

[English](README.md) | 简体中文

**把应用启动、剪贴板历史、窗口管理和截图，放进同一个原生 macOS 工具。**

[下载 Mac 版](https://github.com/baomi-app/knot/releases/latest) · [隐私说明](docs/privacy-policy.zh.md) · [MIT 许可证](LICENSE) · [反馈问题](https://github.com/baomi-app/knot/issues)

**macOS 14+ · Apple Silicon 和 Intel · 无需账号 · 源码采用 MIT 许可**

Knot 用一个键盘入口串起日常 Mac 操作：打开应用、找回复制过的文字、排列窗口，以及截图和标注，不必在多个独立工具间切换。界面使用 SwiftUI 和 AppKit 构建。

核心处理在 Mac 本地完成。**默认开启的自动更新检查会连接 GitHub**，可在 Settings → General 中关闭；打开 Quicklink 会访问对应网站。

## 一分钟上手

1. 下载 DMG，将 Knot 移入「应用程序」并打开。
2. 使用 Settings → Shortcuts 中显示的启动器快捷键，搜索应用，或输入 `12 * 8` 计算。
3. 复制一句不含敏感信息的示例文字，再搜索 **Clipboard History** 找回它。
4. 尝试 **Left Half** 排列窗口，或使用 **Capture & Annotate** 截图标注；两者分别需要辅助功能和屏幕录制权限。

Knot 的目标是把常用工具集中在一起，而不是替代专业启动器或截图编辑器的全部功能。

## 功能

- 搜索应用、命令、文件和 Quicklinks
- 整理菜单栏图标
- 用快捷键移动窗口、调整窗口大小
- 在本地加密保存剪贴板历史
- 截图、标注和识别屏幕文字
- 自定义全局快捷键
- 在应用内检查并安装更新

Knot 的核心功能在本地运行，无需注册账号，仅在相关功能需要时请求系统权限。

## 安装

从 [Releases](https://github.com/baomi-app/knot/releases/latest) 下载 DMG，将 Knot 拖入「应用程序」文件夹。

需要 macOS 14 或更高版本，支持 Apple Silicon 和 Intel Mac。

## 构建

需要 macOS 14 或更高版本、Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
xcodegen generate
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## 测试与 CI

生成项目后，可在 macOS 上运行单元测试：

```sh
xcodebuild -project Knot.xcodeproj -scheme Knot -configuration Debug \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

[GitHub Actions](https://github.com/baomi-app/knot/actions/workflows/ci.yml) 会在推送和 Pull Request 时使用 macOS 15、Xcode 26.0 构建应用并运行单元测试，也支持手动触发。构建、测试日志和 XCTest 结果包作为构件保留 7 天。普通 CI 不执行签名或发布，也不验证交互式截图、辅助功能权限及菜单栏实际行为。推送到 `release` 分支时，测试通过后会额外执行签名、公证并发布 GitHub Release；所需 Secrets 和操作流程见[发布配置](docs/UPDATES.md#automatic-releases-from-the-release-branch)。

## 隐私与权限

- 无需账号，不含广告或分析服务。剪贴板历史使用 AES-GCM 在本地加密，密钥保存在 macOS 钥匙串；OCR 使用 Apple 的设备端 Vision 框架。
- 辅助功能权限用于窗口管理和直接粘贴；屏幕录制权限用于截图及 OCR；登录时启动为可选功能。
- 自动更新检查会连接 GitHub 及其下载 CDN，对方会接收 IP 地址等常规连接信息。可在 Settings → General 关闭自动检查；手动检查和下载更新仍需联网。
- Quicklinks 会打开外部网站；使用搜索类 Quicklink 时，你主动提交的查询会发送到目标网站。
- 剪贴板过滤不能保证绝不记录密码或秘密。清空历史不会删除已有的加密恢复副本。截图文件不由 Knot 加密，清空截图索引也不会删除截图文件。

保留规则、本地数据位置和删除方式详见[隐私政策](docs/privacy-policy.zh.md)。

## 许可证

Knot 自有源码（包括来自 Pop 的共享截图实现）采用 [MIT 许可证](LICENSE)。第三方组件保留各自的许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
