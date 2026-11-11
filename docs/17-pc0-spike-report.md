# PC0 窗口技术验证报告

版本 1.1 · 2026-11-10 · 状态：**核心通过；可进入 PC1/PC2，PC3 解除阻塞**。剩余全屏/睡眠/多显示器/性能等外部项见第 6 节。

对应任务：`docs/16-pc-development-plan.md` M9-PC0。代码位置：`apps/desktop`。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| Flutter 3.47.9 stable 官方实验性 windowing | **不可用**：能创建原生窗口，Flutter 内容区空白；`enable-windowing` 在 stable 为 Unavailable |
| `desktop_multi_window` + `window_manager 0.5.1` 回退 | **通过** |
| 主窗 | **通过**：1000×680，页面正常渲染；关闭到托盘；单实例恢复 |
| 固定窗 | **通过**：320×220 逻辑，125% DPI 下完整可见，右下角定位，无裁切 |
| 置顶 / 不抢焦点 | **通过**：topmost + toolwindow + noactivate |
| 老板键 | **通过**：Ctrl+Alt+H 同时隐藏/恢复两窗 |
| 点击穿透 | **通过**：Ctrl+Alt+L 切换 `WS_EX_TRANSPARENT + WS_EX_LAYERED`，可解 |
| 托盘 | **通过**：图标与菜单初始化 |
| 全局热键 | **2/3**：H、L 成功；M 被系统/其他应用占用，注册失败 |
| 单实例 | **通过**：第二次启动只保留一个进程，并唤起主窗 |
| 全屏检测 / 睡眠 / 多显示器 / 开机启动 / 性能 / 签名 | **未验证** |

**决定：PC0 核心通过，进入 PC1（共享层与 `.fjob`）和 PC2（主窗/账本）。PC3 固定窗不再阻塞。**

## 1. 环境

| 项 | 值 |
| --- | --- |
| OS | Windows 11 / 26H2（10.0.26300） |
| 屏幕 | 2048×1152 逻辑工作区（125% 缩放，任务栏后 2048×1104） |
| Flutter | 3.47.9 stable，Dart 3.13.7，SDK `G:\flutter` |
| Visual Studio | 生成工具 2022 17.14.37，Windows 10 SDK 10.0.26100 |
| 工程 | `apps/desktop`，Windows x64，debug |
| 依赖栈 | `desktop_multi_window 0.3.1`、`window_manager 0.5.1`、`tray_manager 0.5.2`、`hotkey_manager 0.3.0`、`screen_retriever 0.2.2`、`win32 6.4.0` |

## 2. 尝试一：官方实验性 windowing（失败）

- 在 binding 前设置 `isWindowingEnabled = true`，runner 改为 `flutter/examples/multiple_windows` 的 engine-only runner。
- 构建成功；原生窗口创建成功，但 Flutter 内容区为空白。
- `flutter config --list` 显示 `enable-windowing: (Not set) (Unavailable)`。
- 结论：Dart flag 只绕过断言，stable 引擎不支持多视图。放弃。

## 3. 尝试二：desktop_multi_window（通过）

### 3.1 主窗

- 默认 Windows runner + `desktop_multi_window`；主窗由 `window_manager 0.5.1` 管理。
- 1000×680，定位 (40,40)；关闭到托盘；单实例第二次启动只保留一个进程并唤起主窗。
- 托盘初始化成功；老板键、穿透热键注册成功。

### 3.2 固定窗

- 主窗用 `WindowController.create(WindowConfiguration(arguments: '{"role":"card"}', hiddenAtLaunch: true))` 创建第二个 Flutter engine。
- **关键修复**：`desktop_multi_window` 创建 secondary engine 时不会运行应用的 `generated_plugin_registrant`，导致 `window_manager` 抛 `MissingPluginException`。在 `windows/runner/flutter_window.cpp` 中注册：
  ```cpp
  void RegisterSecondaryPlugins(void* controller_ptr) {
    auto* controller = static_cast<flutter::FlutterViewController*>(controller_ptr);
    auto registrar = controller->engine()->GetRegistrarForPlugin("WindowManagerPlugin");
    WindowManagerPluginRegisterWithRegistrar(registrar);
    auto screenRegistrar = controller->engine()->GetRegistrarForPlugin(
        "ScreenRetrieverWindowsPluginCApi");
    ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(screenRegistrar);
  }

  DesktopMultiWindowSetWindowCreatedCallback(RegisterSecondaryPlugins);
  ```
  卡窗 engine 即可使用 `window_manager` 设置 320×220、frameless、alwaysOnTop、skipTaskbar、transparent。
- **坐标修复**：`screen_retriever` 在该环境返回**物理**工作区 2048×1104、缩放 1.25；`window_manager.setPosition` 使用**逻辑**坐标。必须先除以 scale：
  ```dart
  final logicalWidth = area.width / scale;
  final logicalHeight = area.height / scale;
  final x = logicalWidth - 320 - 28;
  final y = logicalHeight - 220 - 22;
  ```
  修复后卡窗完整出现在右下角，内容不裁切。
- 卡窗内容使用 320×220 设计；`FittedBox` 作为额外保险；拖拽使用 `windowManager.startDragging()`。

### 3.3 实测通过项

- 卡窗 HWND 可见、topmost、toolwindow、noactivate；屏幕截图完整显示。
- 主窗与卡窗同时存在；主窗 1000×680，卡窗 320×220；右侧预览与桌面卡一致。
- Ctrl+Alt+H：两窗同时隐藏，再按恢复。
- Ctrl+Alt+L：卡窗 exstyle 从 `0x108` 切到 `0x80128`（transparent+layered），再按恢复。
- 主窗 WM_CLOSE：隐藏到托盘，进程保留；再次启动 exe：进程数仍为 1，主窗恢复。

## 4. 代码与临时项

```text
apps/desktop/
  lib/main.dart                 # 主窗/卡窗分流、窗口启动、托盘、热键、单实例
  lib/main_window.dart          # PC0 主窗 UI
  lib/card_window.dart          # 卡窗 engine UI、FixedCard、方法通道
  lib/desktop_controller.dart   # 主窗控制卡窗、老板键、隐私、状态
  lib/card_native_window.dart   # Win32 备用实现（当前未使用，保留作降级参考）
  lib/theme.dart                # PC0 临时 token；PC1 替换为共享 fjob_ui
  windows/runner/flutter_window.cpp # secondary engine 注册 window_manager/screen_retriever
```

临时行为：

- 主窗启动 1 秒后自动 `showCard()`，用于无人值守走查；PC1 前删除或改为参数开关。
- `card_window.dart` 保留 `card media/display area` 诊断日志；PC1 清理。
- 隐私热键 Ctrl+Alt+M 在本机被占用；正式版需要改键或冲突提示。主窗“金额隐身”开关仍可切换，卡窗通过方法通道更新。
- `card_native_window.dart` 是 Win32 降级实现，当前未调用；若后续移除，需同步删 `win32/ffi` 直接依赖。

## 5. 证据

- 双窗口：[17-pc0-two-windows.png](screenshots/17-pc0-two-windows.png)
- 固定窗：[17-pc0-card-window.png](screenshots/17-pc0-card-window.png)
- 主窗：[17-pc0-main.png](screenshots/17-pc0-main.png)

## 6. 未验证 / 剩余外部项

- 全屏应用自动隐藏、睡眠/唤醒、系统改时。
- 多显示器（当前仅单屏 125%）、DPI 100/150/200%。
- 开机启动、代码签名、便携 zip/安装包。
- Release 性能：debug 双 engine 约 500 MB；需 release 重测 CPU/内存。
- Ctrl+Alt+M 冲突来源与可改键方案。
- 卡窗拖拽后的位置记忆、贴边；PC3 实现。
- 隐私开关的卡窗视觉（方法通道已接，未做自动截图）。
- 真机/远程桌面/不同 Windows 版本的窗口行为。

## 7. 命令记录

```powershell
G:\flutter\bin\flutter.bat --version
G:\flutter\bin\flutter.bat doctor -v
cd G:\game\nw\FJOB\apps\desktop
G:\flutter\bin\flutter.bat analyze          # No issues found
G:\flutter\bin\flutter.bat build windows --debug
G:\flutter\bin\flutter.bat run -d windows --debug
python -X utf8 tools/verify_handoff.py      # PASS
```

实测日志摘录：

```text
[FJOB PC0] tray initialized
[FJOB PC0] hotkey fjob.pc0.privacy failed: PlatformException(register_failed, ...)
[FJOB PC0] 2 hotkeys registered
[FJOB PC0] card engine ready
[FJOB PC0] display area=Size(2048.0, 1104.0) scale=1.25 -> logical 1290.4,641.2
[FJOB PC0] 固定窗已就绪（独立 engine）
[FJOB PC0] 固定窗已显示
```

## 8. 交付判定

- PC0 **核心通过**：主窗、固定窗、置顶、不抢焦点、老板键、点击穿透、托盘、单实例、125% DPI 下完整显示。
- 可以进入 **PC1**（共享包/`.fjob`）和 **PC2**（主窗/账本）；PC3 固定窗不再阻塞。
- 全屏/睡眠/多显示器/性能/签名在 PC4–PC7 及发布前关闭，不能以本次单屏走查替代。
