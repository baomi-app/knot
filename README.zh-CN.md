# Knot

[English](README.md) | 简体中文

**把日常 Mac 工具，串联在一起。**

Knot 是一款轻量的原生 macOS 工具，将常用功能集中在一个快捷入口中。

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

## 隐私

剪贴板历史在 Mac 上加密保存，OCR 在设备端完成。详见[隐私政策](docs/privacy-policy.md)。

自动检查更新会连接 GitHub，可在设置中关闭。

第三方项目说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
