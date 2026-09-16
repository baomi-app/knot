# Show HN 演示录制脚本

状态：待录制真实产品画面。本文是制作说明，不是已完成的演示；没有使用模拟 UI 或占位图片。

## 目标

用约 35 秒展示“一处入口，多个日常操作”。为英文 README 和 Show HN 使用简短英文字幕；不要编造创作经历、性能数据或没有验证的兼容性承诺。

## 录制前准备

- 使用准备发布的真实 Knot 版本，记录版本号、macOS 版本及 Mac 芯片。
- 建议使用干净的演示账户，打开勿扰模式，隐藏个人文件、账号、通知及其他敏感信息。
- 仅复制演示文字，例如 `Meet at 10:30 — bring the prototype.`，不要用真实剪贴板历史。
- 先完成辅助功能及屏幕录制授权，另在视频说明中注明权限要求；不要剪辑成无需权限的效果。
- 在 Settings → Shortcuts 确认当前启动器快捷键，录制和字幕使用实际配置。
- 准备 TextEdit 文档，内容为 `Knot demo / Local OCR / Screenshot notes`；截屏和 OCR 都对这份文档操作。
- 使用系统录屏工具录制，不要在公开桌面上打开证书、Secrets、开发者账号或发布日志。

## 35 秒镜头表

| 时间 | 真实操作 | 英文字幕 |
| --- | --- | --- |
| 0–4 秒 | 桌面上按实际启动器快捷键，显示 Knot 面板 | One entry point for everyday Mac tasks |
| 4–9 秒 | 搜索 TextEdit 并打开 | Launch apps |
| 9–16 秒 | 复制演示句子，打开 Clipboard History，选中该条目 | Find copied text and images |
| 16–22 秒 | 聚焦 TextEdit，通过 Knot 执行 Left Half | Arrange windows |
| 22–32 秒 | 执行 Capture & Annotate，拖选演示文档，加一个箭头或矩形并完成 | Capture and annotate |
| 32–35 秒 | 展示结果及简短结束字幕 | Native macOS · No account · MIT source |

可选：单独录制 8–10 秒 OCR 小片段，使用 Capture Area and Extract Text，再将结果粘贴到空白演示文档。主视频不要为了塞入所有功能而加速到无法看清。

## 导出和接入 README

1. 保留原始录像，导出 1280×720 或相近分辨率的 MP4，确保搜索文本清晰；保留自然节奏，剪掉等待即可，非实时加速需注明。
2. 从真实视频截取一帧作为封面，建议存为 `Assets/knot-demo-poster.png`。不能将应用图标或设计稿冒充产品截图。
3. 将 MP4 上传到 GitHub 支持的视频附件位置，取得可公开访问的链接；也可另导出短 GIF 放入仓库，注意文件体积。
4. 只有在文件和视频链接真实存在后，才在两份 README 的首屏说明之后插入带链接的封面：英文替代文本用 `Watch Knot launch an app, browse clipboard history, arrange a window, and annotate a screenshot`，中文描述同样概括实际操作。
5. 在视频旁注明录制版本、macOS 版本、硬件，以及“Window management and direct paste require Accessibility; capture requires Screen Recording.”
6. 退出 GitHub 登录状态验证视频和下载入口可访问，检查手机端封面可读性。

## 发布前检查

- 视频展示的功能与发布 DMG 一致，没有展示尚未发布的修复。
- 画面没有个人剪贴板内容、密码、私钥、邮箱或敏感文件名。
- README 的联网更新、权限和隐私边界说明仍然可见。
- 不使用“完全离线”“绝不记录密码”等不符合实现的宣传。
- 发帖前确认 CI 和真实安装测试结果；本文本身不证明构建、签名或公证已通过。
