# desktop-v0.1.1 · 托盘图标与小窗最小化修复

发布日期：2026-11-12 · Tag：`desktop-v0.1.1` · 版本 `0.1.1` · 平台：Windows 10 1809+ / 11 x64。

从 `desktop-v0.1.0` 可直接覆盖安装，账本（`%APPDATA%\FJOB`）与显示设置保留。本版修复两项用户反馈，并合入上一轮 PC 体验打磨。

## 托盘图标

- 修复托盘区图标空白：Windows 端改用多尺寸 `.ico`（16/20/24/32/40/48/64）。此前传入 PNG，`LoadImage(IMAGE_ICON)` 返回空句柄，系统只留下一个无图标的托盘占位项。
- 托盘菜单现会随固定窗状态自动刷新：点击「最小化」后文案切换为「显示固定窗」，可直接召回。
- Windows 11 会把新托盘图标收进 `^` 溢出区；如需固定在任务栏，从溢出区拖出，或在「设置 → 个性化 → 任务栏 → 其他系统托盘图标」中打开。应用不会修改系统托盘设置。

## 固定窗

- 右键菜单新增「最小化」。固定窗仍不进任务栏（PC3-01 契约）；最小化后从托盘菜单「显示固定窗」或主窗「桌面 → 显示固定窗」恢复。
- 恢复路径改为固定窗 engine 的 `window_manager.show()`（内部先 `restore()` 再显示），修复已最小化窗口只收到 `SW_SHOW`、无法还原的问题。
- 系统级最小化（Win+Down / 系统菜单）同样会同步主窗状态与托盘菜单文案。

## 主窗体验（同步合入 docs/22）

- 资产/账单表格恢复完整布局：表头、「添加持仓」按钮与操作列在默认窗口一屏可见，不再出现列粘连或整页布局作废。
- 桌面页「固定窗预览」在默认 1000×680 窗口即左右分栏同屏可见，不再被挤到折叠线以下。
- 新增表格布局、桌面页分栏、托盘 ICO、固定窗最小化/恢复回归测试。

## 验证

| 检查 | 结果 |
| --- | --- |
| `flutter analyze`（apps/desktop） | No issues found |
| `flutter test`（apps/desktop） | 35 通过 |
| `flutter build windows --release` | 成功 |
| 真机（Windows 11，125% 缩放） | 托盘图标已注册并显示于溢出区；固定窗最小化后可从托盘恢复；主窗托盘图标左键可恢复并置前 |

截图与根因记录见 [docs/23-pc-tray-and-card-minimize.md](../23-pc-tray-and-card-minimize.md)；表格/预览修复见 [docs/22-pc-experience-polish-walkthrough.md](../22-pc-experience-polish-walkthrough.md)。

## 安装与卸载

- 安装：`FJOB-Setup-0.1.1.exe`，当前用户安装，无需管理员权限；可选桌面快捷方式。
- 便携版：解压 `fjob-desktop-0.1.1-win-x64.zip` 直接运行；数据目录同为 `%APPDATA%\FJOB`。
- 卸载：设置 → 应用 → 今日又白干 → 卸载，只移除程序文件，账本与显示设置保留。

## 已知边界

- 未配置代码签名时首次运行可能出现 SmartScreen 提示；配置 `WINDOWS_CERTIFICATE_BASE64` / `WINDOWS_CERTIFICATE_PASSWORD` 后由 CI 自动 Authenticode 签名。
- Windows 11 托盘图标默认位于 `^` 溢出区，属系统行为。
- 真实行情来源（东方财富公开接口）为 developmentOnly，展示许可仍为发布门禁。
- 200% 缩放、多显示器拔插、Narrator、睡眠/唤醒与全屏自动隐藏未在本版重新验收。
- 局域网同步（PC6）、macOS 不在本版范围。

## 校验

`SHA256SUMS` 随 Release 提供，包含安装包与便携 zip；设置页「检查更新」使用同一 SHA-256 校验安装包。
