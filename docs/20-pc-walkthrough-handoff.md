# PC 端走查与修复交接说明（续 docs/19）

版本 1.0 · 2026-11-10 · 用途：交给下一个 agent 继续 Windows PC 端「运行实测」与收尾。

> 先读 `AGENTS.md`、`docs/16`、`docs/18`、`docs/19`，再读本文。本文只记录**本会话实际运行输出**证实的结论；标注「未验证」的项不要当成已通过。命令退出码均单独核对（`> log 2>&1; echo EXIT=$?`），不凭记忆。

## 0. 背景与目标

最终目标见 docs/16：Windows 10 1809+/11 x64 便携 PC 伴生端，Flutter Windows + 共享 Dart 包，复用手机账本/计算/视觉，**不重写金融算法**。任务序 PC0→PC1→PC2→PC3→PC4→PC5→PC6→PC7。docs/19 交接时：PC0/PC1 完成、PC2/PC3 主体已写、release 构建与便携 zip 已产出，但**功能级真机走查未做**。本会话的任务就是 docs/19 §3.4「运行实测」，并在走查中修复发现的 bug。

硬约束（沿用）：不自动发布、不改 CI/CD（需用户确认）、不提交 secrets、不破坏手机、金额不进日志/标题/托盘。

## 1. 本会话已完成并验证

### 1.1 起始状态复核（exit 0）
- 桌面 `flutter analyze`：No issues found。
- 桌面 `flutter test`：**10 通过**（fixture_parity 3 + card_privacy 3 + preferences 4）。
- 便携 zip SHA-256 与 docs/19 一致：`6c4421faf0cf37b512557a06c459f1ddc34008e6f13c446fc6830146d913d19e`。
- 环境：Windows 11 专业版 10.0.26300，单显示器 2560×1440 物理 @125% DPI（逻辑 2048×1152），16 核。

### 1.2 走查发现并修复的 bug（均已改码 + 回归测试 + 重建验证）

| # | 问题 | 修复文件 | 验证 |
| --- | --- | --- | --- |
| 1 | **首次启动死路**：未配置账本时任何导航页都仍显示欢迎面板，欢迎页「从手机导入/从零开始」按钮只改 `_index` 但 build 忽略它，用户无法离开欢迎页 | `apps/desktop/lib/main_window.dart`：条件改为 `if (!configured && !sample && _index == 0)` | 新增 `test/welcome_navigation_test.dart` 2 测试通过；真机 rail 导航与导入入口可用 |
| 2 | **双标题栏**：原生黑色标题栏 + 自绘标题栏并存 | `apps/desktop/lib/main.dart`：`WindowOptions.titleBarStyle: TitleBarStyle.hidden`；`main_window.dart`：自绘标题栏包 `DragToMoveArea`（可拖动） | 截图 `19-pc-02-welcome.png` 单标题栏 |
| 3 | **ListTile 墨水断言**：`PaperCard`(DecoratedBox) 内的 Checkbox/Switch/ListTile 触发 debug 断言、墨水不可见 | `config_page.dart`（3 处单独包 Material）、`desktop_page.dart`/`data_page.dart`（Column 外包 `Material(type: transparency)`） | 桌面测试通过 |
| 4 | **`.fjob` 导入失败（关键）**：真机导入报通用错误。临时暴露异常后实为 `SQLITE_MISUSE(21) on BEGIN IMMEDIATE`。根因：`sqflite_common_ffi` 默认 `singleInstance:true`，主窗与卡窗两个 Flutter engine 共用同一 Database 对象，卡窗每秒读事务与主窗写事务嵌套→MISUSE。**不是 winsqlite3.dll 线程问题**（实测 `PRAGMA compile_options` THREADSAFE=1、版本 3.50.1） | `packages/ledger_store/lib/data/app_database.dart`：`OpenDatabaseOptions(singleInstance: false)` + onConfigure 增 `PRAGMA journal_mode=WAL` 与 `PRAGMA busy_timeout=5000` | 新增 `ledger_store_test.dart`「a second connection reading concurrently never blocks an import」通过；**真机导入成功**（账本 #0→#2，生成导入前备份 #0，截图 `19-pc-06-import-result.png`） |

> 修复 4 同时满足 docs/16 PC2-02 早就要求的 WAL。`singleInstance:false` 让两端各开独立连接，WAL 让读不阻塞写，busy_timeout 吸收短暂写竞争。**不要回退这三项。**

### 1.3 修复后测试结果（exit 0）
- 桌面 `flutter test`：**12 通过**（10 + welcome_navigation 2）。
- `packages/ledger_store` `dart test`：**13 通过**（12 + 并发回归 1）。
- `packages/market_data` `dart test`：**65 通过**（PC4 单元层，含断网/冷缓存/部分/陈旧/429/401-403）。
- 手机 `flutter analyze`：No issues；`flutter test`：**176 通过 + 1 跳过**（共享库改 WAL/singleInstance 后重跑确认无回归）。
- 桌面 release 重建成功（最终 `data/app.so` 时间戳 23:30，BUILD_EXIT=0）。

### 1.4 性能采样（release，空闲 30s，16 核归一化）
- 修复前构建：CPU **0.719%**，工作集 197.2MB，私有 270.3MB。
- 修复后构建：CPU **0.524%**，工作集 **168.7MB**，私有 243.8MB。
- 结论：**CPU<1% 达标**；**内存<150MB 未达标**（工作集 168.7MB）。双 engine（主窗+卡窗）固有开销，记为 PC7-04 性能缺口，未优化。

### 1.5 真机走查已覆盖（release exe，PowerShell UI 自动化 + PrintWindow 截图）
- 首次启动欢迎页 ✓（`19-pc-02-welcome.png`）。
- rail 导航到数据页 ✓（`19-pc-03-data-empty.png`）。
- 原生文件选择器选 `.fjob` ✓（**中文输入法会把反斜杠打成顿号，必须用剪贴板粘贴**，见 §4）。
- 导入核对对话框 ✓（月薪¥12,000、时区 Asia/Shanghai、本月排班 168.0 小时、2 项资产、房贷、账单 2026.11；`19-pc-05-import-dialog.png`）。
- 确认导入成功 ✓（账本 #2、备份 #0；`19-pc-06-import-result.png`）。
- 今日页 ✓（11月10日 周二 23:32，已下班，今日计薪 8.0/8.0 小时，今日生存结余 ¥77.22；`19-pc-07-today.png`）。

### 1.6 走查用测试数据
- `apps/desktop/build/walkthrough-mobile.fjob`：由 `tool/make_walkthrough_bundle.dart` 用 `buildDemoLedger` 锚定 2026-11 生成，platform=android，ledgerId `7f3a9c2e-1111-4b2a-9c3d-a1b2c3d4e5f6`，revision 1，checksum `sha256:9b2eabee7da524572686f67bbb048f6fdf2f31377859686c51aa6fbed9707340`。月薪 12000、标准办公周、房贷 4800/本金 2800、车贷 1800/本金 1500、持仓 000001×1000@13 与黄金×20@850。**.fjob 不含行情**，导入后持仓 pendingQuote，app 会拉真实 Eastmoney 报价。

## 2. 交接时确切状态

- 当前有一个 release 实例**正在运行**，已导入上述账本（#2），停在今日页。继续走查可直接用；若要重建先停进程（见 §4）。
- 真实数据库 `%APPDATA%\FJOB\fjob_ledger.db` 已是 WAL 模式（有 -wal/-shm），revision 2，含 1 份备份。
- **便携 zip 尚未用修复后的构建重新打包**：`apps/desktop/build/fjob-desktop-0.1.0-win-x64.zip`（SHA 6c44…）仍是**修复前**的旧构建，**不可作为交付物**，必须重打 + 重算 SHA-256。
- 临时诊断 catch（data_page 兜底曾改成显示 `$e`）**已还原**为正式文案「操作未完成，当前账本未被部分写入；请重试。」。

## 3. 后续计划（按优先级）

1. **数字到分 parity（下一步重点，被打断处）**：今日页向下滚动看「今日分项」（工资估算/A股今日/基金今日/黄金今日/住房分摊/车贷分摊/今日生存结余）。用 `tool/parity_check.dart <file.fjob> <isoUtc>` 按界面显示的时钟计算期望值核对。注意：工资/住房/车贷不依赖行情可直接比；股票/黄金因 .fjob 无行情、app 拉了真实报价，合计含真实行情，不能直接用 .fjob 的合计比。住房/车贷按自然日已逝秒数分摊（每秒约 +0.00185 元），核对需取界面同一时刻。fixture 锚点 CALC-01/CALC-09 已由 `fixture_parity_test.dart` 在固定时刻证明到分一致。
2. **配置页走查**：四子页（收入与排班/资产/住房与车贷/账单）编辑→保存→实时预览→今日页重算；行内校验、本金>月供拒绝、expectedRevision。
3. **桌面页 + 固定窗走查**：S/M/L 密度切换（220×76/320×220/420×390）、显示项 both/time/balance、金额隐身/置顶/点击穿透/锁定/透明度/全屏自动隐藏/减少动效、右侧实时预览；固定窗右键菜单、拖拽贴边、双击开主窗、隐私遮蔽。
4. **数据页往返**：导出 .fjob→再导入（替换/合并）往返一致；备份恢复；旧修订拒绝；清空。
5. **设置页**：版本/来源/数据目录/更新通道说明核对。
6. **PC4 真机行情**：断网/缓存/部分小计/陈旧标记观察（单元层 65 已过）；真实来源公开展示许可仍是发布门禁。
7. **PC7**：200% 缩放、键盘全流程、Narrator、性能（内存缺口已记）。
8. **重打便携 zip + SHA-256**（修复后构建），回写 `docs/16` 状态表与 `docs/06` §3.3「M9-PC 本轮验证」。
9. 收尾：决定 `tool/repro_*.dart`、`build/check_sqlite.dart` 等调试脚本去留（`tool/make_walkthrough_bundle.dart`、`tool/parity_check.dart` 建议保留作走查工具）。

## 4. 本会话新增的工具与坑（务必遵守）

### 工具（均在 `apps/desktop/`，未纳入 git）
- `build/pc20-ui.ps1`：UI 自动化。动作 `front/frontshot/shot/click/clickmain/rclick/key/rect`；`-Target print` 用 **PrintWindow(PW_RENDERFULLCONTENT=2)** 抓 Flutter 窗口内容（**抗遮挡**，优于 CopyFromScreen）；脚本已 `SetProcessDPIAware()`，坐标为**物理像素**。`clickmain` 会先置前主窗再点。
- `build/pc20-launch-sample.ps1`：启动 exe + 全屏截图 + 空闲 CPU/内存采样（`-SampleSeconds`）。
- `build/pc20-enum-windows.ps1`：枚举进程顶层窗口。
- `tool/make_walkthrough_bundle.dart`、`tool/parity_check.dart`、`tool/repro_import.dart`、`tool/repro_concurrent.dart`。

### 坑
- **中文输入法**：系统 IME 处于中文态，`SendKeys` 直接打路径会把 `\` 变成 `、`。输入文件路径必须 `Set-Clipboard -Value '<path>'` 后 `SendKeys("%n^a^v")`（Alt+N 聚焦文件名框→全选→粘贴）再 `{ENTER}`。
- **窗口坐标**：主窗物理原点约 (655,265)、1250×850；卡窗 M 档 400×275 物理、右下角。PrintWindow 截图原点=窗口 rect 左上角，点击坐标=原点+图内坐标。每次重建/重启后先 `-Action rect` 重新读坐标。
- **停进程有延迟**：`Stop-Process -Force` 后 `Get-Process` 计数可能短暂仍为 1；重建前确认计数 0（否则 `data/app.so` 被占用）。必要时 `taskkill /F /PID <pid>`。
- **Flutter/Dart 不在 PATH**：`G:/flutter/bin/flutter.bat`、`G:/flutter/bin/dart.bat`。
- **Bash 工作目录每次重置为 `G:\game\nw\eatgemini`**：每条命令自带 `cd /g/game/nw/FJOB/...`。
- 沿用 docs/19 §5 全部坑（官方 windowing 禁用、secondary engine 插件注册、screen_retriever 物理 vs window_manager 逻辑坐标、winsqlite3.dll override、Write 对已存在文件偶发报错改用 Edit）。

## 5. 命令清单

```bash
# 桌面门禁
cd apps/desktop && G:/flutter/bin/flutter.bat analyze && G:/flutter/bin/flutter.bat test
cd apps/desktop && G:/flutter/bin/flutter.bat build windows --release
# 共享包
cd packages/ledger_store && G:/flutter/bin/dart.bat test
cd packages/market_data  && G:/flutter/bin/dart.bat test
# 手机回归
cd apps/mobile && G:/flutter/bin/flutter.bat analyze && G:/flutter/bin/flutter.bat test
# 走查工具
cd apps/desktop && G:/flutter/bin/dart.bat run tool/make_walkthrough_bundle.dart build/walkthrough-mobile.fjob
cd apps/desktop && G:/flutter/bin/dart.bat run tool/parity_check.dart build/walkthrough-mobile.fjob 2026-11-10T15:32:00Z
# UI 自动化（物理坐标）
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action rect
powershell -NoProfile -ExecutionPolicy Bypass -File apps/desktop/build/pc20-ui.ps1 -Action shot -Name 19-pc-07-today -Target print
```

## 6. 未验证 / 外部依赖（发布门禁）
- 配置/桌面/固定窗/数据往返/设置页的**功能级走查未做完**（本会话只走到今日页）。
- PC 与手机**同账本数字到分一致**的真机核对未完成（fixture 锚点已证）。
- 内存<150MB **未达标**（168.7MB）；200% 缩放/键盘/Narrator 未测。
- 真实行情来源稳定性与**公开展示许可**（Eastmoney developmentOnly）。
- 代码签名、自动更新器、Windows CI（需用户确认）、局域网同步 PC6、macOS。
- **修复后的便携 zip 尚未重打**。

## 7. 交付报告要求（AGENTS.md）
报告需求/任务编号、修改文件、实际命令与结果、截图/产物路径与 SHA-256、规则偏差、未验证项；明确手机测试是否通过、`.fjob` 是否可往返、哪些视觉/素材对比未验证。