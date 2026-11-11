# 后续 Agent 任务指引

版本 1.0 · 2026-11-10 · 用途：交接给其他开发 agent 继续 PC 端开发。

## 可直接复制的任务指引

```text
你在 G:\game\nw\FJOB 继续开发「今日又白干」Windows PC 伴生端。先读 AGENTS.md、
README.md、docs/13、docs/14、docs/15、docs/16、docs/17，再读 contracts/、
fixtures/calculation-cases.json、apps/mobile 与 apps/desktop 当前代码。

当前状态（2026-11-10）：
- M9-PC0 已核心通过：Windows 主窗 + 固定窗、置顶、不抢焦点、老板键、点击穿透、
  托盘、单实例、125% DPI 下完整显示。报告见 docs/17-pc0-spike-report.md。
- 工程 apps/desktop 已存在；Flutter 3.47.9；依赖锁定 desktop_multi_window 0.3.1、
  window_manager 0.5.1、tray_manager 0.5.2、screen_retriever 0.2.2、
  win32 6.4.0、hotkey_manager 0.3.0、windows_single_instance 1.2.0。
- 官方 Flutter 实验性 windowing 在 stable 不可用，不要回退到该路线；不要升级
  window_manager 到 0.6（它走官方 windowing）除非重新完成 PC0 验证。
- 固定窗 secondary engine 已在 windows/runner/flutter_window.cpp 通过
  DesktopMultiWindowSetWindowCreatedCallback 注册 window_manager 和 screen_retriever。
- screen_retriever 返回物理工作区，window_manager.setPosition 用逻辑坐标；
  定位前除以 scaleFactor，见 apps/desktop/lib/card_window.dart。
- PC0 临时项：主窗启动 1 秒后自动 showCard()、诊断日志、未使用的
  card_native_window.dart。PC1 时清理或改为显式开发开关。
- 当前 flutter analyze 无问题，debug 构建成功；PC0 后应用已停止，不要假设它还在运行。

本阶段任务：M9-PC1「共享层与 .fjob」。按 docs/16 执行，不得跳过手机回归。
1) 建 packages/ledger_model（纯 Dart）：
   - 从 apps/mobile/lib/domain/format.dart 迁 formatMoney/formatAmount/formatSigned/
     formatHours/formatPercent/formatClock/formatDuration/formatDate/formatMonth/
     weekdayLabel。
   - 从 apps/mobile/lib/domain/ledger.dart 抽 AppTone。
   - 从 apps/mobile/lib/features/dashboard/home_metrics_model.dart 迁 HomeMetricsModel、
     HomeTimeState、HomeTimeDisplay、HomeBalanceDisplay；只改 import，不改逻辑。
   - 定义 .fjob LedgerBundle：格式版本、导出时间、ledgerId、ledgerRevision、
     app、timezone、salary/schedule/holding/housing/car/monthlyBills/settings、
     checksum。只含账本与配置，不含行情缓存/派生快照/日志/设备标识。
2) 建 packages/fjob_ui（Flutter，依赖 finance_core + ledger_model）：
   - 迁 FjobPalette/FjobTheme；抽出 _HandDrawnClockIcon/_HandDrawnBillIcon。
   - 迁 WorkerFrame/WorkerPainter、OfficeScene/_OfficePainter、DebtArtPainter/DebtArt、
     SceneInteractionController/ScenePresentation/PatResponses、SceneMotion 常量。
   - 不复制 prototype/pc.html 的 Canvas JS；不使用 prototype/animation-keyframes 作生产素材。
   - 新增 CompactOfficeScene 380×112，复用同一 WorkerPainter/DebtArtPainter，只改构图。
3) 手机端改为 import 共享包；删除重复实现；保持双卡、场景、拍肩、离场、图标视觉不变。
4) 新增手机 .fjob 导出/导入入口（设置页）：预览摘要、替换/合并、导入前备份、
   原子写入、校验和；较旧 ledgerRevision 不静默降级。
5) 手机端与共享包测试：
   - 共享包：WorkerFrame 参数 parity、palette token、HomeMetricsModel fixture、
     CompactOfficeScene smoke。
   - 手机：cd packages/finance_core && dart test；cd apps/mobile && flutter analyze && flutter test。
   - 截图对比首页双卡、办公室、拍肩、离场、房车插画。
6) PC1 验收：手机 172 个测试仍通过；共享包测试通过；PC 能解析手机导出的 .fjob；
   PC 不重算工资/分摊/盈亏；固定窗/主窗可直接使用共享 painter 与格式化函数。

PC1 完成后再做 M9-PC2：
- 主窗五页（今日/配置/桌面/数据/设置）、SQLite（sqflite_common_ffi）、
  收入排班/资产/住房车贷/账单、配置实时预览、导入导出、校验与 expectedRevision。
- PC 测试必须消费 fixtures/calculation-cases.json，与手机同一 fixture 到分一致。
- 完成后再做 M9-PC3 固定窗 S/M/L、状态矩阵、隐私、托盘/热键、紧凑场景。

硬约束：
- 同源：PC 只消费 DashboardSnapshot/WorkSessionContext/finance_core；不重写算法。
- 素材：角色、房车、办公室、硬币、图标、动效必须来自 fjob_ui；不搬截图/关键帧。
- 隐私：金额不进日志、标题、托盘提示；固定窗/预览/托盘/无障碍遮蔽，主窗可见。
- 数据：金额与数量用规范十进制字符串；未知不写 0；导入原子、失败不部分写入。
- 不破坏手机；不提交 secrets；不改无关文件；不自动发布。
- 当前 apps/desktop、docs/13–17、prototype/pc.html 都是未提交的工作区改动，
  先 git status 看清，不要覆盖。

命令：
- Flutter 不在 PATH：G:\flutter\bin\flutter.bat
- cd apps/desktop && flutter analyze && flutter build windows --debug
- cd packages/finance_core && dart test
- cd apps/mobile && flutter analyze && flutter test
- python -X utf8 tools/verify_handoff.py

已知坑：
- 官方 windowing 在 stable 内容区空白；不要用。
- secondary engine 不注册应用插件；新增卡窗插件必须在 flutter_window.cpp 回调里注册。
- screen_retriever 物理坐标 vs window_manager 逻辑坐标；定位必须除 scaleFactor。
- Ctrl+Alt+M 在本机被占用；热键冲突要有提示/改键，不能静默失败。
- debug 双 engine 约 500 MB；release 需重测性能。
- 固定窗自动 showCard、诊断日志、card_native_window.dart 是 PC0 临时物，PC1 清理。

交付报告按 AGENTS.md：需求/任务编号、修改文件、实际命令与结果、截图/产物、
规则偏差、未验证项。PC1 结束时明确说明手机测试是否通过、.fjob 是否可往返、
哪些视觉/素材对比未验证。
```

## 附录：任务顺序与验收

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| PC1a | `ledger_model`：`AppTone`、format、HomeMetricsModel、`.fjob` | 手机改用包；fixture 字符串/金额一致；`.fjob` 校验和往返 |
| PC1b | `fjob_ui`：palette/theme、icons、scene、controller、CompactOfficeScene | 手机场景/拍肩/离场无回归；PC 可使用共享 painter |
| PC1c | 手机导出/导入 | 设置页可导出；导入预览/备份/原子写入；旧修订不降级 |
| PC2 | 主窗五页 + SQLite + 配置实时预览 | 配置保存/重算/校验；fixture 与手机一致 |
| PC3 | 固定窗 S/M/L + 状态矩阵 + 隐私/托盘/热键 | PC-D01–D22 相关项；125%/多屏 |

## 交接注意

- `apps/desktop` 当前是 PC0 验证壳，不是正式产品结构；PC1/PC2 可以重构，但不要丢掉已通过的窗口配置（secondary engine 插件注册、坐标换算、单实例/托盘逻辑）。
- `card_native_window.dart` 是 Win32 降级参考，当前未调用；如保留，需在 docs/17 说明。
- `prototype/pc.html` 是设计参照，不是生产代码；共享包抽取以 `apps/mobile` 的 Dart painter 为准。
