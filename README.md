# MyScreen

[English](README.en.md)

MyScreen 是一款原生 macOS 菜单栏应用，用来把屏幕边缘保留给指定窗口，并把其他窗口限制在剩余工作区内。它适合需要长期保留 iPhone 镜像、聊天窗口、监控面板、参考资料或其他辅助窗口的工作流。

## 功能

- **屏幕保留区**：在显示器的左、右、上、下边缘创建保留区域。
- **窗口绑定**：从正在运行的应用中选择具体窗口，将其自动移动并适配到保留区。
- **工作区约束**：其他窗口会被限制在剩余工作区内，避免覆盖保留区。
- **多显示器支持**：每个显示器可以拥有独立的保留区配置。
- **多保留区**：同一显示器最多可在四个边缘创建多个保留区。
- **拖拽调整尺寸**：保留区分割线可拖拽调整，并自动保存配置。
- **快速隐藏/显示**：默认全局快捷键为 `⌘⌥M`，可在控制面板中自定义。
- **菜单栏控制面板**：应用以菜单栏图标运行，不占用 Dock。
- **亮度控制**：支持显示器亮度调节；硬件控制不可用时会回退到软件调光。
- **状态恢复**：配置、绑定窗口和快捷键会保存到本机 `UserDefaults`。

## 使用场景

- 在 Mac 上使用 iPhone 镜像时，让镜像窗口始终保持在侧边。
- 写代码或办公时，把聊天、文档、仪表盘固定在屏幕边缘。
- 在外接显示器上给特定工具窗口预留空间，主工作区保持整洁。
- 临时需要全屏工作时，用快捷键隐藏保留区，稍后再恢复。

## 系统要求

- macOS 14.0 Sonoma 或更高版本
- Xcode 16 或兼容版本
- Swift 5.10
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

MyScreen 需要 macOS 辅助功能权限，才能读取、移动和调整其他应用窗口。应用不采集用户数据，不包含截图或录屏功能。

## 构建与运行

```bash
make generate
make build
make run
```

常用命令：

```bash
make generate   # 根据 project.yml 生成 Xcode 工程
make build      # Debug 构建
make run        # Debug 构建并启动应用
make release    # Release 构建
make clean      # 清理构建产物和生成的 Xcode 工程
```

如果构建时遇到签名问题，请在 `Makefile` 或 `project.yml` 中把 `DEVELOPMENT_TEAM` 改成你自己的 Apple Developer Team ID。

## 基本使用

1. 启动 MyScreen。
2. 按系统提示授予辅助功能权限：`System Settings` -> `Privacy & Security` -> `Accessibility`。
3. 点击菜单栏中的 MyScreen 图标打开控制面板。
4. 选择显示器，点击 `+` 添加保留区。
5. 选择保留区边缘和大小，可以使用百分比或像素。
6. 绑定一个正在运行的应用窗口。
7. 使用 `⌘⌥M` 或自定义快捷键隐藏/显示保留区。

## 项目结构

```text
MyScreen/
├── main.swift / AppDelegate.swift
├── Core/          # 屏幕管理、窗口监控、布局计算、快捷键、亮度控制
├── Models/        # 配置、布局、绑定窗口和保留区模型
├── UI/            # 菜单栏控制面板、窗口选择器、快捷键录制、权限引导
├── Utilities/     # 辅助功能、窗口列表和屏幕 ID 工具
docs/              # PRD、竞品分析和发布说明
project.yml        # XcodeGen 配置
Makefile           # 常用构建命令
```

## 技术实现

MyScreen 使用 Swift、AppKit 和 SwiftUI 构建。核心窗口管理依赖 macOS Accessibility API，显示器信息来自 `NSScreen` / `CGDisplay`，窗口变化通过 `AXObserver`、`NSWorkspace` 通知和 `CGWindowList` 轮询组合追踪。应用沙盒已关闭，因为窗口管理、全局事件和部分显示器控制能力需要系统级访问。

## 当前限制

- 只支持 macOS，不支持 iOS 或 iPadOS。
- 不替代 macOS Spaces，也不管理系统全屏模式下的应用。
- 目前仓库没有自动化测试。
- 面向源码构建使用，打包、签名、公证和正式分发流程仍需完善。

## 更多文档

- [产品需求文档](docs/PRD.md)
- [v1.0.1 发布说明](docs/release-notes-v1.0.1.md)
- [v1.0.0 发布说明](docs/release-notes-v1.0.0.md)
