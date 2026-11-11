# PC 端开发交接说明（续 docs/18）

版本 1.0 · 2026-11-10 · 用途：交给下一个 agent 继续产出 Windows PC 程序。

> 先读 `AGENTS.md`、`README.md`、`docs/13`–`docs/18`，再读本文。本文记录截至交接时的**真实进度**、**确切命令**、**已知坑**与**下一步**。所有结论以实际运行输出为准；本文标注「未验证」的项不要当成已通过。

## 0. 目标与范围

最终目标：产出可运行的 **Windows 10 1809+ / 11 x64** PC 伴生端（便携 zip 先行），复用手机端账本、计算与视觉素材。技术栈 Flutter Windows + 共享 Dart 包，**不重写金融算法**。首版不做云同步、局域网同步（PC6）、macOS、自动更新器与代码签名（外部依赖）。**不自动发布、不改 CI/CD 工作流（需用户确认）、不提交 secrets。**

任务编号沿用 `docs/16`：PC0→PC1→PC2→PC3→PC4→PC5→PC6→PC7。

## 1. 已完成并验证

### PC0（先前会话，见 docs/17）
窗口技术验证核心通过：主窗+固定窗（desktop_multi_window 0.3.1 + window_manager 0.5.1）、置顶/不抢焦点、老板键、点击穿透、托盘、单实例、125% DPI 完整显示。**官方实验性 windowing 在 stable 内容区空白，禁止回退该路线。**

### PC1 共享层与 `.fjob`（本会话完成，门禁通过）
新增四个共享包（`packages/`），手机端已改为消费共享包并删除重复实现：

| 包 | 内容 | 测试 |
| --- | --- | --- |
| `ledger_model` | 纯 Dart：`AppSettings/LedgerState/AppTone/LedgerJson`、`format.dart`、`HomeMetricsModel`、`SetupDraft`、`ScheduleCodec`、`instrument`、`demo_ledger`、`LedgerBundle`（.fjob v1 + 严格校验 + SHA256 排序键校验和 + merge） | `dart test` **77 通过** |
| `ledger_store` | Dart + sqflite_common：`AppDatabase`（schema **v6**）、`LedgerRepository`、`home_metrics_preference_store`、`LedgerBundleRepository` 扩展（export/import/backup/restore/saveConfiguration） | `dart test` **12 通过** |
| `fjob_ui` | Flutter：`FjobPalette/FjobTheme/PaperCard/SectionLabel/MoneyText`、`HandDrawnClockIcon/HandDrawnBillIcon/BrandMark`、`OfficeScene/CompactOfficeScene(380×112)/WorkerPainter/DebtArtPainter/SceneInteractionController/SceneMotion` | `flutter test` **35 通过** |
| `market_data` | 纯 Dart：`MarketClient/AppConfig/GatewayMarketClient/EastmoneyMarketClient/FixtureMarketClient/QuoteRepository`、日历、`applyQuoteFreshness`；补齐网关 429 Retry-After/401-403 停用/退避/最多30标的/拒收 fixture | `dart test` **65 通过** |

- `finance_core` 未改口径：`dart test` **110 通过**（消费 `fixtures/calculation-cases.json`）。
- **手机端门禁通过**：`apps/mobile` `flutter analyze` 无问题；`flutter test` **176 通过 + 1 跳过**（基线 172 + 新增 4：3 个交换页测试 + 1 个更新通道隔离测试）。
- 手机新增 `.fjob` 入口：`apps/mobile/lib/features/settings/ledger_transfer_page.dart`（设置页「手机与电脑交换账本」+ 首次引导欢迎页「已有账本？导入 .fjob」）。含摘要预览、替换/合并、导入前备份、原子写入、校验和、旧修订拒绝、16MiB 流式上限、示例模式禁用。
- `python -X utf8 tools/verify_handoff.py` 通过（24 参考计算 + OpenAPI + v1/v2 schema + 隐私反例 + 文档链接）。

### PC2/PC3 桌面主体（本会话已写，整包 analyze 通过）
`apps/desktop` 已从 PC0 验证壳重构为正式结构（**注意：apps/desktop 整个目录尚未纳入 git，是未提交工作区**）。当前 `flutter analyze` **No issues found**。文件地图：

```
apps/desktop/lib/
  main.dart                 # 入口：主/卡窗分流、单实例、托盘、热键、ProviderScope、initDesktopDatabase
  main_window.dart          # 主窗外壳：标题栏窗口控制 + 五页导航 rail + 首次启动欢迎面板
  desktop_controller.dart   # 主/卡窗生命周期、偏好应用、setDisplay 推送、卡→主调用、全屏自动隐藏
  desktop_preferences.dart  # 本机显示偏好（原子写、串行、失败回滚、校验）；DesktopPreferencesStore
  native_desktop.dart       # Win32：真全屏判定（纯函数可测）、当前用户开机启动注册表、原子替换文件
  card_window.dart          # 卡窗引擎：直接读共享 SQLite 算快照 + 接收显示配置 + S/M/L + 右键菜单/拖拽
  state/database.dart       # initDesktopDatabase：Windows 用 winsqlite3.dll + databaseFactoryFfi
  state/providers.dart      # Riverpod：clock/calendar/db/repository/market/quote/calculator/tick(1s)/dashboard/preferences
  state/ledger_controller.dart # 账本变更/报价刷新/.fjob 导入导出/备份恢复（无原生小部件桥）
  widgets/metric_cards.dart # TimeMetricCard/BalanceMetricCard/StatusChip（消费 HomeMetricsModel，隐私遮蔽）
  widgets/fixed_card_view.dart # FixedCardView S(220×76)/M(320×220)/L(420×390)，L 用 CompactOfficeScene
  pages/today_page.dart     # 今日：双卡并排 + OfficeScene + 分项 + 刷新/拍肩
  pages/config_page.dart    # 配置：收入排班/资产/住房车贷/账单四子页 + 实时预览（子代理实现，已 analyze 通过）
  pages/desktop_page.dart   # 桌面：显示项/密度/隐私/置顶/穿透/锁定/透明度/全屏隐藏/低动效 + 预览
  pages/data_page.dart      # 数据：.fjob 导入导出 + 最近5份备份恢复 + 清空
  pages/settings_page.dart  # 设置：版本/来源/数据目录/更新通道说明（手动）
apps/desktop/test/
  fixture_parity_test.dart  # 消费同一 fixture，demo 账本复现 CALC-01/09 到分
  card_privacy_test.dart    # 三档密度隐私遮蔽、metrics 模式
  preferences_test.dart     # 偏好校验/不可变更新/位置校验
```

## 2. 交接时确切状态

- 桌面 `flutter analyze`：**No issues found**（含 config_page）。
- 桌面 `flutter test`：**10 通过**（fixture_parity 3 + card_privacy 3 + preferences 4）。过程中修了两类问题：① 测试期望值把 Unicode 减号 `−¥55.26` 误写成 ASCII `-¥55.26`（产品行为正确，与手机一致）；② **真实布局 bug**：固定窗 M/S 档在 320×220 / 220×76 内内容溢出抛 RenderFlex 异常，已用 SingleChildScrollView（M）与 ClipRect+OverflowBox（S）兜底修复。详见第 4 节。
- **Windows release 构建成功**：`flutter build windows --release`（283.7s）→ `apps/desktop/build/windows/x64/runner/Release/todayagain_desktop.exe`（61KB）+ `flutter_windows.dll` + 各插件 DLL + `data/`。
- **冒烟启动通过**：exe 启动后存活 5 秒无闪退（仅证明能加载运行，**未做界面走查**）。
- **便携包已产出**：`apps/desktop/build/fjob-desktop-0.1.0-win-x64.zip`（13,736,956 B）。
  - SHA-256：`6c4421faf0cf37b512557a06c459f1ddc34008e6f13c446fc6830146d913d19e`
  - 校验文件：`apps/desktop/build/fjob-desktop-0.1.0-win-x64.zip.sha256`
- 桌面真机走查（首次启动流程、五页交互、配置保存、固定窗三档、隐私/老板键/穿透、多屏/DPI/全屏/睡眠/性能）**未验证**。
- 配置页由并行子代理实现并已 analyze/test 通过；**功能级走查未做**（表单保存/校验/实时预览需实测）。

## 3. 下一步计划（按优先级）

1. ✅ 桌面测试全绿（10 通过）。
2. ✅ Windows release 构建成功（见第 2 节产物路径）。若日后报插件/registrant 问题：卡窗 secondary engine 已在 `windows/runner/flutter_window.cpp` 注册 `window_manager` + `screen_retriever`（PC0 修复，勿删）；主引擎插件由 `generated_plugin_registrant.cc` 注册。
3. ✅ 便携 zip + SHA-256 已产出（见第 2 节）。
4. **运行实测（下一步重点）**：解压 zip 或直接跑 `Release/todayagain_desktop.exe`，走查首次启动→导入手机 `.fjob`（或从零配置）→今日页双卡/场景→配置四子页保存与实时预览→固定窗 S/M/L→金额隐身/老板键/穿透/右键菜单/拖拽→数据页导出再导入往返→设置页。截图存 `docs/screenshots/19-pc-*.png`。**重点核对 PC 数字与手机到分一致**（用同一 `.fjob`）。
5. **PC4 行情完整性实测**：market_data 已抽出并补退避；桌面 providers 已接 Eastmoney/Gateway。实测断网/缓存/部分小计/陈旧标记与手机一致；真实来源许可仍是发布门禁。
6. **PC5 其余**：更新器（settings 页目前仅手动 release 链接）、诊断日志脱敏、Windows CI（**改 CI/CD 需用户确认**）、代码签名（外部依赖）。
7. **PC7 验收**：键盘全流程/Narrator/200% 缩放/空闲 CPU<1% 内存<150MB/PC-D01–D22 记录。
8. 回写 `docs/16` 状态表与 `docs/06` 验证记录；`toolchain.lock.json` 已加 windows 段（本会话）。

## 4. 关键架构决策（本会话所做，偏离 docs/18 处）

- **卡窗金额来源**：卡窗引擎**直接读共享本地 SQLite**（`%APPDATA%\FJOB\fjob_ledger.db`）并用同一 `finance_core` 算 `DashboardSnapshot`，每 1s 重算、每 3s 重读账本。主窗只通过方法通道 `setDisplay` 推送**显示配置**（privacy/density/metricsMode/reduceMotion/opacity/locked + 单调 sequence），不序列化金额。满足「PC 不重算」（同一引擎）。主窗与卡窗各开一个 FFI 连接读同一文件。
- **schema v6**：新增 `ledger_metadata`（稳定 UUID ledgerId）与 `ledger_backups`（最近5份）。`_createLedgerMetadata` 用 `CREATE TABLE IF NOT EXISTS` + `INSERT OR IGNORE` 保证幂等（修复手机迁移测试「先升 v6 再降 user_version 重升」重复建表崩溃）。
- **`.fjob` v1 明文**：含校验和（防损坏，非防伪），**未做口令加密**（刻意延后）。只含账本与配置，不含行情缓存/快照/日志/设备标识。导入原子、失败整笔回滚、同账本旧修订拒绝、merge 冲突不自动覆盖。
- **额外抽出 `ledger_store` 与 `market_data`**：docs/18 的 PC1 主要求 ledger_model/fjob_ui；本会话按 docs/13/15 建议把存储与行情也抽成共享包，供手机与 PC 共用。手机已删除对应重复源文件。
- **桌面 updater / CI / 签名未做**：settings 页显示手动 release 链接；未新增 CI 工作流（需用户确认）；便携 zip 待构建。
- **M 档固定窗布局**：320×220 内用「紧凑时间卡（dense，含倒计时/状态/说明）+ 完整结余卡（金额/语气/报价时间）」并以 SingleChildScrollView 兜底防溢出。为落在 220px，M 档时间卡**暂不显示计薪进度条**（进度在主窗今日页与 L 档可见）；这是相对 docs/14 M 线框的小简化，后续可按原型 7–9px 小字恢复进度。修复了首版 M 档结余区被挤到 23px 溢出的真实 bug。

## 5. 已知坑（务必遵守）

- 官方 Flutter 实验性 windowing 在 stable 内容区空白，**不要用**；不要升级 window_manager 到 0.6（走官方 windowing）除非重做 PC0。
- secondary engine 不自动注册应用插件；新增卡窗插件必须在 `windows/runner/flutter_window.cpp` 的 `DesktopMultiWindowSetWindowCreatedCallback` 里注册。
- `screen_retriever` 返回**物理**工作区，`window_manager.setPosition/setSize` 用**逻辑**坐标；定位前除以 `scaleFactor`（见 card_window.dart `_placeBottomRight`）。
- `Ctrl+Alt+M` 在本机被占用；热键注册失败要容忍并可从托盘操作（HotkeyService 已捕获冲突）。
- Windows 无 `sqlite3.dll`：`initDesktopDatabase()` 用 `winsqlite3.dll` override（主窗与卡窗都要调）。
- debug 双 engine 约 500MB；release 需重测内存/CPU。
- **工具坑**：本会话 Write 工具对「已存在文件」偶发报「File has not been read yet」（会话压缩重置读取跟踪所致）；改用 **Edit** 增量修改，或先 Read 再 Write。新文件 Write 正常。
- 会话会被自动压缩；**结论必须指回已读输出**，不要凭记忆声称通过。子代理/自写脚本可能假绿；交付前重跑命令看真实退出码（注意 `cmd | tail` 会掩盖退出码，用 `> log 2>&1; echo EXIT=$?`）。
- 派子代理「只读」后必须 `git status` 复核越界写入。

## 6. 命令清单

```bash
# Flutter/Dart 不在 PATH
G:/flutter/bin/flutter.bat --version
G:/flutter/bin/dart.bat --version

# 共享包
cd packages/finance_core && G:/flutter/bin/dart.bat test
cd packages/ledger_model && G:/flutter/bin/dart.bat test
cd packages/ledger_store && G:/flutter/bin/dart.bat test
cd packages/market_data  && G:/flutter/bin/dart.bat test
cd packages/fjob_ui      && G:/flutter/bin/flutter.bat test

# 手机回归（门禁）
cd apps/mobile && G:/flutter/bin/flutter.bat analyze && G:/flutter/bin/flutter.bat test

# 桌面
cd apps/desktop && G:/flutter/bin/flutter.bat analyze
cd apps/desktop && G:/flutter/bin/flutter.bat test
cd apps/desktop && G:/flutter/bin/flutter.bat build windows --release

# 契约
python -X utf8 tools/verify_handoff.py
```

## 7. 未验证 / 外部依赖（发布门禁）

- 桌面**功能级/真机走查**：首次启动流程、五页交互、配置保存与实时预览、固定窗三档视觉、隐私/老板键/穿透/拖拽、多屏/DPI 100/150/200%、全屏自动隐藏、睡眠/改时恢复、空闲 CPU<1%/内存<150MB。（构建与便携 zip 已完成，冒烟仅证明能启动。）
- PC 与手机**同账本数字到分一致**需实测（用同一 `.fjob` 往返）。
- 真实行情来源访问稳定性与**公开展示许可**（Eastmoney 为 developmentOnly）。
- 代码签名（SmartScreen 提示）、自动更新器、Windows CI（需用户确认后才改工作流）。
- 局域网同步（PC6，v0.2）、macOS（P2）。
- M 档固定窗暂不显示计薪进度条（简化，见第 4 节）。

## 8. 交付报告要求（AGENTS.md）

每次交付报告：需求/任务编号、修改文件、实际命令与结果、截图/产物路径与 SHA-256、规则偏差、未验证项。明确说明手机测试是否通过、`.fjob` 是否可往返、哪些视觉/素材对比未验证。