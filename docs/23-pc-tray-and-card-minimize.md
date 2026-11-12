# PC 托盘图标与小窗最小化修复

版本 1.0 · 2026-11-12 · 用途：记录本轮两项用户反馈（小窗支持最小化、托盘区图标未显示）的根因、修复与实测。关联 `docs/16`、`docs/21`、`docs/22`。

## 1. 反馈

1. 小窗（固定窗）也需要支持最小化。
2. Windows 托盘区图标未显示。

## 2. 根因

### 2.1 托盘图标：PNG 不能作为 `IMAGE_ICON` 加载

`tray_manager 0.5.2` 的 Windows 实现直接调用 Win32：

```cpp
LoadImage(nullptr, iconPath, IMAGE_ICON,
          GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
          LR_LOADFROMFILE);
```

`LoadImage(IMAGE_ICON)` 只接受 `.ico` / `.bmp`（图标或位图文件），项目此前传入的是
`assets/tray_icon.png`。本机实测：

| 文件 | `LoadImage(..., IMAGE_ICON, 16, 16, LR_LOADFROMFILE)` |
| --- | --- |
| `assets/tray_icon.png` | `handle=0`（失败，且 `GetLastError` 为 0） |
| `assets/tray_icon_32.png` | `handle=0` |
| `windows/runner/resources/app_icon.ico` | 有效句柄 |

插件不会把 `NULL` 当作错误上报，仍会 `Shell_NotifyIcon(NIM_ADD)`，于是任务栏出现一个
没有图标的占位项——表现为“托盘区图标未显示”。

另外，Windows 11 默认把**新**托盘图标放进 `^` 溢出区；图标本身有效也不会自动固定到
任务栏。应用无法通过公开 API 替用户固定，需用户在溢出区拖出或通过“任务栏设置 →
其他系统托盘图标”打开。

### 2.2 小窗最小化：没有入口，且恢复路径不还原最小化状态

- 固定窗无边框、`skipTaskbar: true`，右键菜单只有“隐藏到托盘”，没有“最小化”。
- `WindowController.show()`（`desktop_multi_window`）只发 `SW_SHOW`；对已最小化的窗口
  不会还原。即使窗口被系统最小化（Win+Down），原 `showCard()` 也无法把它叫回来。
- 主窗控制器不知道固定窗被最小化，托盘菜单仍显示“隐藏固定窗”，状态不一致。

## 3. 修复

| 文件 | 修改 |
| --- | --- |
| `apps/desktop/assets/tray_icon.ico`（新） | 由 64×64 PNG 生成的多尺寸 ICO：16/20/24/32/40/48/64，覆盖 100%–200% 缩放与菜单场景 |
| `apps/desktop/tool/generate_tray_icon.ps1`（新） | 可重复生成 ICO 的 PowerShell 脚本；文件保持 ASCII，避免 Windows PowerShell 5 把无 BOM UTF-8 当 ANSI 读取 |
| `apps/desktop/pubspec.yaml` | 打包 `assets/tray_icon.ico` |
| `apps/desktop/lib/main.dart` | Windows 使用 `.ico` 设置托盘图标；托盘菜单监听控制器状态变化自动刷新；清理监听的时机修正 |
| `apps/desktop/lib/card_window.dart` | 右键菜单新增“最小化”；engine 处理 `minimize`；`show` 走 `window_manager.show()`（内部先 restore）；`onWindowMinimize` 通知主窗 |
| `apps/desktop/lib/desktop_controller.dart` | 新增 `minimizeCard()`；`showCard()` 改为调用固定窗 engine 的 `show`（先还原再显示），原生 `WindowController.show()` 仅作兜底；`cardMinimized` 同步 `cardVisible` |
| `apps/desktop/test/tray_icon_test.dart`（新） | 校验 ICO 目录、尺寸集合（含 16/20/24/32）与内嵌 PNG 帧 |
| `apps/desktop/test/card_minimize_test.dart`（新） | 控制器经 engine 发送 `show`/`minimize`，最小化后 `cardVisible=false`，恢复仍走 engine 而非 `window_show` |

行为约定：

- 固定窗“最小化”后不进入任务栏（保持 PC3-01 固定窗契约），通过托盘菜单
  “显示固定窗”、主窗桌面页“显示固定窗”或再次显示来召回；`showCard()` 会先
  `restore()` 再 `show()`。
- 系统级最小化（Win+Down / 系统菜单）同样会同步主窗状态并刷新托盘菜单文案。
- “隐藏到托盘”仍保留：与最小化相比只是不保留最小化状态，恢复入口一致。

## 4. 验证（本机实际执行）

环境：Windows 11（10.0.26300 x64），2560×1440 / 125% 缩放，Flutter 3.47.9。

| 检查 | 结果 |
| --- | --- |
| `flutter analyze`（apps/desktop） | No issues found |
| `flutter test`（apps/desktop） | 35 通过（新增 2 项） |
| `flutter build windows --release` | 成功；`data/flutter_assets/assets/tray_icon.ico` 已打包 |
| Win32 `LoadImage` 逐尺寸探测 | 16/20/24/32/40/48/64 均返回有效句柄 |
| `Shell_NotifyIconGetRect`（主窗 hWnd，uID=1） | `S_OK`，图标已注册；Windows 11 默认位于 `^` 溢出区，图标为品牌便签 |
| 固定窗右键 → 最小化 | `IsIconic(card)=True` |
| 托盘菜单（最小化后） | 文案为“显示固定窗”；点击后 `IsIconic(card)=False`，固定窗恢复显示 |

截图：`docs/screenshots/23-pc-card-menu.png`（右键菜单含“最小化”）、
`23-pc-tray-overflow.png`（溢出区图标）、`23-pc-tray-menu.png`（最小化后的托盘菜单）、
`23-pc-card-restored.png`（从托盘恢复后的固定窗）。

## 5. 发布与未验证

- `desktop-v0.1.1`（prerelease）由 `desktop-release` CI 构建并发布；安装包 `FJOB-Setup-0.1.1.exe` 11,761,991 B / `8935e505…`，便携 zip `fjob-desktop-0.1.1-win-x64.zip` 14,053,487 B / `a39e0c61…`，与 `SHA256SUMS` 一致（docs/06 §3.3）。
- 未配置代码签名 Secrets，安装包与 exe 均为 `NotSigned`。
- Windows 11 托盘“固定到任务栏”属于系统用户设置，应用不写入注册表、不替用户更改。
- 200% 缩放、多显示器拔插、Narrator 下的托盘/最小化流程未本轮复测。
