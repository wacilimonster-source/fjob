# PC 固定窗走查与修复交接说明（续 docs/20）

版本 1.0 · 2026-11-11 · 用途：记录本轮「固定窗为主」的真机走查结论，交给下一个 agent 继续收尾。

> 先读 `AGENTS.md`、`docs/16`、`docs/19`、`docs/20`，再读本文。所有结论均来自本会话**实际运行输出**（退出码逐一核对）；标注「未验证」的项不要当成已通过。

## 0. 本轮目标（用户指令）

1. 不做今日页 parity（docs/20 §3.1 顺延）。
2. 重点走查**固定窗**。
3. 固定窗视觉层级：**下班时间是主核心视觉，今日生存结余是次核心**。

## 1. 视觉层级落地（已完成 + 真机验证）

按 docs/14 §7 线框与用户新指令对齐：

| 档 | 下班时间（主核心） | 结余（次核心） | 验证截图 |
| --- | --- | --- | --- |
| S 220×76 | 倒计时 21px（20→21） | 金额 18px（17→18） | `20-pc-26-card-s-final.png` |
| M 320×220 | 倒计时 40px（34→40）+ **恢复迷你计薪进度条**（4px 条 + 9px 说明） | 金额 34px（30→34），收起语气句与长说明（部分状态由「部分小计」chip 表达），保留报价时间行 | `20-pc-25-card-m-final.png` |
| L 420×390 | 倒计时 40px（38→40），无进度条（spec L 无进度） | 金额 34px（32→34），收起语气句与长说明；**分项行（工资/投资/支出）回到一屏内**（此前被挤出可视区） | `20-pc-27-card-l-final.png` |

改动文件：`widgets/metric_cards.dart`（`CardProgressMode full/mini/none`、`showFlavor` 收口语义、说明行 maxLines 1）、`widgets/fixed_card_view.dart`（三档字号与进度模式）、`test/card_privacy_test.dart`（新增层级回归：M 档进度可见、固定窗语气句缺席、L 档分项 hitTestable）。主窗今日页不受影响（默认参数不变）。

## 2. 走查发现并修复的 bug（均有回归测试 + 真机复验）

| # | 问题 | 根因 | 修复 | 验证 |
| --- | --- | --- | --- | --- |
| 5 | 桌面页任何显示设置都报「显示设置没存上，请重试」；`%APPDATA%\FJOB\pc_preferences.json` 从未创建 | `_writeFile` 用 `Directory.createTemp` 建暂存目录：本机 dart run/flutter test/release exe 下对**混合分隔符前缀**（`…\FJOB/.pc-preferences-`）一律 `ERROR_PATH_NOT_FOUND`（errno 3）；而 `Directory.create` 与 `MoveFileExW`（混合分隔符目标）实测正常 | 改为确定性暂存目录（plain `Directory.create`）+ 进程内唯一文件名；Windows 上所有交给原生调用的路径统一反斜杠规范化。回归：`test/preferences_real_io_test.dart`（真实 IO 读写往返 + 暂存清理 + 二次保存） | 真机：密度/显示项/隐身/锁定/透明度全部即时落盘（`pc_preferences.json` 逐项核对） |
| 6 | 桌面页显示的是默认值而非持久化值（盘上 density=l 页面显示 m；点「已选中」分段不触发保存 → 假象「切换失败」，卡窗与页面不一致） | `preferencesProvider` 初始为 defaults，启动加载后**从未同步** | `FjobDesktopApp` 改 `ConsumerStatefulWidget`，`_bootstrap` 加载后 `ref.read(preferencesProvider.notifier).state = prefs` | 真机：重启后页面正确显示持久化的 L 档；`20-pc-23-desktop-page.png` |
| 7a | 卡窗右键菜单永不弹出（`showMenu` 抛 `Null check operator used on a null value` @ MaterialLocalizations.of） | `_showMenu` 传的是 **State.context（在 MaterialApp 之上）** | `body: Builder` 捕获 MaterialApp 内部 context 传给 `_showMenu` | 真机：菜单四项完整弹出 `20-pc-45-menu-fixed.png`；「隐藏到托盘」菜单项生效 |
| 8 | 位置记忆整体缺失：拖拽后 position 永远 null，启动永远贴右下角（PC3-06/09） | 卡窗只有 `onPanStart → startDragging`，无移动结束上报、无恢复逻辑 | 卡窗挂 `WindowListener.onWindowMoved` → 上报主窗存盘；`setDisplay` 携带 position；恢复时校验显示器工作区指纹（`W{left},{top},{w},{h}`），不匹配回退贴角；首次配置延迟 150ms 沉降 + `getPosition` 读回校验 + 重试一次；程序性贴角（密度切换/重置）后主动上报（SetWindowPos 不触发 onWindowMoved）；密度切换锚定右下（spec）。指纹换屏/改缩放自动回退（多显示器身份延后 PC6/PC7） | 真机：拖到 (1620,675) → 重启精确恢复 (1620,675)（`20-pc-49-card-restored-final.png`）；拖动中位置实时落盘（1472/540、1486.4/729.6 均与物理坐标 ÷1.25 吻合） |
| 9 | 双 `DesktopPreferencesStore` 实例（main.dart 传入的 A 与 `preferencesStoreProvider` 自建的 B）共用同一文件互覆盖：页面保存的 density/locked 被卡窗 savePosition（走 A 的启动旧快照）静默回滚，位置也被旧值带回贴角 | 两个实例各自持有 `_value` 快照交叉写盘 | `ProviderScope` 增加 `preferencesStoreProvider.overrideWithValue(preferences)`，全局单实例 | 真机：locked:true 落盘后不再被回滚；density/position 稳定 |
| 附 | `packages/finance_core` 2 处 analyze 遗留（未用 import、悬空库注释） | 前序会话遗留 | 清理；`dart analyze` 无问题、110 测试通过 | 回归通过 |

另：docs/20 §4 的 `pc20-ui.ps1` 本轮新增 `wheel`/`drag`/`dclick` 动作与 `-Notches` 参数；新增 `pc20-probe-point.ps1`（WindowFromPoint/NCHITTEST 探测，已内置 DPIAware）、`pc20-foreground.ps1`、`pc20-window-styles.ps1`、`fullscreen_probe.ps1`（全屏探针，判定不可靠仅留参考）。

## 3. 走查覆盖结论（release，真机）

已通过：S/M/L 三档（尺寸 275×95 / 400×275 / 525×487 物理，均无裁切/溢出）、显示项三模式、金额隐身（结余遮蔽、下班时间保留、chip 变「金额隐身」）、老板键 Ctrl+Alt+H 双窗隐身/恢复、点击穿透开启（右键无菜单）与关闭恢复交互、锁定位置防拖拽、拖拽移动 + 位置记忆持久化/重启恢复、右键菜单弹出及「隐藏到托盘」生效、双击卡窗拉起主窗（前台变 FLUTTER_RUNNER）、纸面透明度 85%/100%、贴角定位（右边距 35px/下边距 28px 物理 = 逻辑 28/22，双重除 scale 竞态已由 `resolveWorkAreaLogical` + SPI 工作区锚定修复）、125% DPI 完整显示、首次启动导入 .fjob 与今日页（沿用 docs/20 结论）。

注意：Ctrl+Alt+M 热键在本机被占用（docs/19 已知），金额隐身经 UI/托盘操作；Ctrl+Alt+H 实测有效。

## 4. 关键教训（务必遵守）

- **卡窗坐标排查必须先确认进程 DPIAware**：未声明的 PowerShell 探针坐标会被系统按 1.25 缩放，`WindowFromPoint` 得到空结果，会误判「卡窗不可命中」。`pc20-probe-point.ps1` 已内置 `SetProcessDPIAware`。
- **卡窗与主窗重叠区域**：卡窗置顶会遮住主窗右侧开关区，自动化点击会打到卡窗上（表现为「开关无响应」）。操作前先 `rect` 核对两窗相对位置，必要时把卡窗拖开。
- `Directory.createTemp` 在本机多个 Dart 运行形态下对含 `/` 的前缀直接抛错；涉及原生 Win32 的路径一律 `replaceAll('/', '\\')` 规范化后再传。
- `WindowController.fromWindowId(id).invokeMethod` 的回调依赖主窗 `setWindowMethodHandler` 已注册；卡→主新增调用（如 savePosition）需在 `_handleCardCall` 补分支。
- 程序性 `SetWindowPos` 不会触发 `WM_EXITSIZEMOVE`，window_manager 的 `onWindowMoved` 只对用户拖动生效——程序性定位后需主动上报位置。
- `showMenu`/`MaterialLocalizations.of` 的 context 必须在 MaterialApp 之内（Builder 捕获），否则 release 下静默抛空检查异常。
- 两个 store 实例写同一 JSON 会互相回滚：偏好文件全局只允许一个 `DesktopPreferencesStore` 实例。

## 5. 命令清单（沿用 docs/20 §5，补充）

```bash
# 固定窗三档截图（物理坐标，先 rect 取窗口原点）
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action rect
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action shot -Name <name> -Target cardprint
# 滚轮（负值向下）/拖拽/双击
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action wheel -X <x> -Y <y> -Notches -3
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action drag -X <x> -Y <y> -Keys "<x2>,<y2>"
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action dclick -X <x> -Y <y>
# 命中/前台/样式探测
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-probe-point.ps1 -X <x> -Y <y>
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-foreground.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-window-styles.ps1
```

## 5.1 范围变更：移除今日页（用户决定，2026-11-11）

PC 端主窗五页改四页：导航删除「今日」，索引重排（0 配置/1 桌面/2 数据/3 设置），默认落配置页；欢迎面板新增 `_welcomeDismissed` 一次性标志（「从零开始配置」与欢迎页同索引 0，必须靠标志脱离）；`lib/pages/today_page.dart` 删除，`main_window.dart` 移除对应 import/分支。今日页 parity（docs/20 §3.1）与 PC↔手机到分核对随之取消。回归：桌面 analyze 无问题、19 测试通过（欢迎导航 2 项在新索引下仍通过）；真机 `20-pc-57-four-pages.png` 四页导航 + 配置页 + 固定窗预览正常。

## 5.2 发布：desktop-v0.1.0（CI，2026-11-11）

- 新增 `.github/workflows/desktop-release.yml`（`desktop-v*` 标签触发）：Windows CI 构建 release、打便携 zip、Inno Setup 安装包、SHA256SUMS 并创建 Release；手机通道 `v*` 不受影响。
- 安装包脚本 `apps/desktop/installer/fjob_setup.iss`：当前用户安装到 `%LOCALAPPDATA%\Programs\FJOB`，无需管理员；卸载只移除程序，`%APPDATA%\FJOB` 账本保留。
- 设置页「检查更新」：desktop-v* 通道、镜像优先、SHA-256 校验（asset digest 优先，SHA256SUMS 回退）、下载后可运行安装程序；11 项单元测试覆盖通道隔离、校验和与下载校验。
- 真机验证：安装包下载 SHA-256 与 Release 一致；静默安装/卸载退出码 0 且卸载干净；应用内检查更新返回「已是最新版本（0.1.0）」。
- 发布直链：`https://github.com/wacilimonster-source/fjob/releases/download/desktop-v0.1.0/FJOB-Setup-0.1.0.exe`。

## 6. 未验证 / 外部依赖（发布门禁，继承 docs/20 §6 并更新）

- 全屏应用自动隐藏：探针受「TopMost 全屏窗 ≠ 前台窗」与卡窗抢前台干扰，需真实全屏应用（游戏/视频）实测；睡眠/唤醒/改时同样未测。
- 托盘菜单逐项点击未自动化（老板键/隐藏到托盘已分别经热键与卡窗菜单验证）。
- 配置四子页、数据页往返、设置页的功能级走查仍未做（本轮按用户指令聚焦固定窗）。
- 今日页已移除，docs/20 §3.1 的今日页分项 parity 随之取消；PC 固定窗与手机同账本到分一致的真机核对仍未做。
- 空闲内存 <150MB 缺口（168.7MB）未复核；200% 缩放/键盘全流程/Narrator 未测。
- 真实行情来源稳定性与公开展示许可（Eastmoney developmentOnly）；代码签名、自动更新器、Windows CI（需用户确认）、PC6、macOS。
- 工具脚本 `apps/desktop/build/pc20-*.ps1`、`tool/make_walkthrough_bundle.dart`、`tool/parity_check.dart` 保留作走查工具；一次性调试脚本（`tool/repro_import.dart`、`tool/repro_concurrent.dart`、临时探针）已删除。

## 7. 交付报告要求（AGENTS.md）

见本轮对话末尾交付报告；需求/任务编号、修改文件、命令与退出码、截图/产物与 SHA-256、规则偏差、未验证项均已记录。
