# 验收标准与交付验证

版本 0.2 · 2026-11-04。

## 1. 功能验收

| 编号 | 场景 | 预期 |
| --- | --- | --- |
| AC-ONB-01 | 首次冷启动 | 出现欢迎入职，无预填真实月薪 |
| AC-ONB-02 | 月薪空或非法 | 留在当前步骤并指出字段，可填0 |
| AC-ONB-03 | 午休越界、区间重叠 | 阻止提交，指明冲突 |
| AC-ONB-04 | 不添加资产与支出 | 可完成引导，相关分项为已知0 |
| AC-ONB-05 | 选择房租与车贷 | 住房展示租金，车贷独立计入 |
| AC-ONB-06 | 本金未知 | 可保存，拆分为待补充，主月供仍计入 |
| AC-ONB-07 | 中途退出和重启 | 恢复步骤及输入，不重复写正式数据 |
| AC-ONB-08 | 重复点击确认 | 同 setupSessionId 仅提交一次 |
| AC-ONB-09 | 提交时磁盘写入失败 | 保留草稿，正式配置事务回滚 |
| AC-ONB-10 | 示例模式 | 固定时钟、清楚模拟标记、与正式账本隔离 |
| AC-ONB-11 | 重走引导后取消 | 返回原配置，账本修订未改变 |
| AC-CALC-01 | 完整月出勤 | 月薪守恒，tick 不影响总额 |
| AC-CALC-02 | 午休、未上班、下班 | 工资只在有效计薪区间增长 |
| AC-CALC-03 | 跨日跨月班次 | 分别纳入对应日期和月份 |
| AC-CALC-04 | 28/29/30/31天月份 | 费用使用真实天数，整月分摊守恒 |
| AC-CALC-05 | 房贷/房租月内切换 | 有效期互斥，分段统计，历史可解释 |
| AC-CALC-06 | 房租与贷款同时存在 | 租金独立，不计为贷款利息 |
| AC-CALC-07 | 缺行情或缺基准 | 显示待更新和不完整小计 |
| AC-CALC-08 | 前后台、进程重启 | 按真实时间重算，恢复准确金额 |
| AC-ASSET-01 | 多只A股和黄金 | 分别显示今日/持有盈亏、单位、时间 |
| AC-ASSET-02 | 证券休市和停牌 | 市场日历驱动，估值与今日项语义正确 |
| AC-ASSET-03 | 黄金夜盘 | 明示参考交易日与基准 |
| AC-ASSET-04 | 持仓盘中修改 | 快照重估，用户可看到重估说明 |
| AC-ASSET-05 | 同代码重复添加 | 引导合并或编辑，避免重复统计 |
| AC-ASSET-01-FUND | 场外基金录入、日终净值与合计 | FND-01～22 全部通过；股票/基金同码不串用；旧 v1/v2/v3 账本与草稿升级保留原数据 |
| AC-API-01 | 乱序返回 | 新报价不被旧响应覆盖 |
| AC-API-02 | 单标的失败、429、超时 | 分项保留状态，遵守退避 |
| AC-API-03 | 断网冷启动 | 本地计算可用，无缓存资产显示待报价 |
| AC-API-04 | 生产来源 | 访问稳定性、基准和展示许可有记录 |
| AC-UI-01 | 房、车、人物 | 粗线条扁平手绘一致 |
| AC-UI-02 | 系统深色下的固定浅色、大字、320dp | 不跟随系统变色，无溢出、遮挡、错误截断 |
| AC-UI-03 | 减少动效和后台 | 停循环运动，业务数值仍正确 |
| AC-WIDGET-01 | 三种信息密度 | 有时间、金额、状态和正确深链 |
| AC-WIDGET-02 | 隐私开关 | 快照、UI 和可访问文本都遮蔽金额 |
| AC-WIDGET-03 | 晚到快照与清空 | ledgerRevision 和 tombstone 防止旧数据复活 |
| AC-WIDGET-04 | App 被杀、更新时间推迟 | 显示可用快照及真实时间 |
| AC-IOS-01 | macOS CI | Runner 与扩展同时编译，锁定工具链 |
| AC-IOS-02 | TestFlight 安装 | App、扩展、App Group 与深链真机通过 |
| AC-DATA-01 | V1 升级及迁移失败 | 数据可读或可回滚，房贷迁移成住房方案 |
| AC-DATA-02 | 清空 | 正式账本、草稿、缓存、共享快照与任务一并失效 |

## 2. 测试层次

纯 Dart 单元测试覆盖计算 fixture、日期区间、精度与完整性。数据库集成测试覆盖迁移、事务、并发修订和幂等提交。Flutter 组件与集成测试覆盖引导、表单、导航、离线和主题。原生扩展测试覆盖 JSON 解析、时间线选择、隐私、深链与乱序。

模拟器截图用于布局与自动化，Android 真机和 iPhone TestFlight 用于实际安装、系统调度、小部件和性能。源接口接入需要单独在线验证记录，写明日期、来源、品种、单位、限制和公开展示条件。

## 3. 本交付已执行的验证

验证对象为 HTML 交互原型和开发材料。原型在 Windows 上使用 Playwright 驱动无头 Edge，并在独立页面中的 iframe 内测试。

- 首次进入、月薪必填、无效午休拦截、草稿页面刷新恢复。
- 房租录入后切换车贷开关，租金输入保持，最终核对和首页同步。
- 房租 + 车贷、本金未知、房贷与房租切换、租金不进入贷款利息。
- 小部件隐私、重新引导后取消、完成后的再次进入。
- 引导六步在320、360、440、736像素宽下检查横向溢出。
- 此前四个主页面与减少动效状态已经进行浏览器检查（当前产品固定浅色，不再要求暗色）。当前迭代继续检查引导、住房切换及保存行为。
- HTML 页面执行期间未记录到 JavaScript pageerror。

`tools/verify_handoff.py` 用高精度 Decimal 独立核对24个参考计算样例（含基金持有/今日浮动与部分可计算合计），并检查 OpenAPI、v1/v2 JSON Schema、隐私反例和文档相对链接。`finance_core` 的 fixture 测试实际读取同一文件并执行新增基金样例；基金样例通过真实 `AssetCalculator` 求值。基金专项验收编号见 [国内基金持仓设计](10-design-domestic-fund-holdings.md) 的 FND-01～22。

执行参考验证需要 Python 3.10+，安装 PyYAML、jsonschema 和 openapi-spec-validator，随后运行 `python tools/verify_handoff.py`。

### 3.1 M7-FUND 本轮验证（2026-11-09）

环境：Flutter 3.47.9 / Dart 3.13.7、JDK 17.0.20.1、Python 3.12.10、Android SDK 见 `toolchain.lock.json`。以下命令均在仓库根目录或标注的工作目录实际执行。

| 命令 | 结果 |
| --- | --- |
| `cd packages/finance_core && dart test test/asset_test.dart test/dashboard_test.dart test/calculation_fixture_test.dart` | 59 passed |
| `cd apps/mobile && flutter test test/holding_editor_test.dart test/setup_draft_test.dart test/database_test.dart test/quote_repository_test.dart` | 53 passed |
| `cd apps/mobile && flutter test test/eastmoney_client_test.dart test/widget_snapshot_test.dart` | 16 passed |
| `cd packages/finance_core && dart test` | 110 passed |
| `cd apps/mobile && flutter analyze` | No issues found |
| `cd apps/mobile && flutter test` | 131 passed，1 skipped（既有跳过项） |
| `cd apps/mobile && flutter test tool/dump_widget_timeline_test.dart` | passed，生成 v2 时间线 |
| `python tools/check_widget_payloads.py` | 8 个条目通过 v1/v2 schema |
| `cd apps/mobile/android && gradlew.bat testDebugUnitTest` | BUILD SUCCESSFUL，v1/v2 解析与乱序测试通过 |
| `python -m pytest -q services/market_gateway` | 18 passed |
| `python tools/verify_handoff.py` | PASS 24 reference calculations、OpenAPI、v1/v2 schema、隐私反例与文档链接 |
| `cd apps/mobile && flutter build apk --debug --dart-define=FJOB_ENABLE_FUND_PUBLIC_SOURCE=true` | 成功，产物见下 |

数据库从 v3 平滑升级到当前 schema v5：v4 迁移段新增 `fund_nav_cache`，v5 迁移段新增并行任务使用的 `ui_preferences`；保留股票、黄金、工资、费用、草稿、名称、账本修订与 `quote_cache`。升级路径由 `database_test.dart` 的真实 v3 库验证。旧持仓/草稿中的基金不会被转成股票，份额四位小数保留。修改代码时旧 `holding_versions` 行关闭、新行新增在同一事务内，目标代码已存在则整体回滚。

并行工作说明：M7-FUND 完成时点（约 18:01）全量 `flutter test` 为 131 passed、1 skipped。随后同一工作区的 M8-HOME 会话在 18:04 改写了 `dashboard_page.dart`，其 `dashboard_scene_test.dart` 出现 8 个与基金无关的离场动画/安慰文案失败；排除该文件后其余 120 项仍全部通过，M7-FUND 定向测试不受影响。上述 debug APK 构建于该并行改写之前。M7-FUND 未修改或回退 M8-HOME 的代码与测试。

产物：

- `G:\game\nw\FJOB\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- SHA-256：`7b7bc14452fd936a527a8488cb55f1abb9a25faa37126cc202f5d33cb402228c`
- 隔离模拟器安装并启动截图：[13-m7-fund-onboarding.png](screenshots/13-m7-fund-onboarding.png)。仅覆盖安装与首屏；资产/基金页面的设备交互与原生小部件桌面渲染未在模拟器走查。

在线只读抽样（2026-11-09，本地时间，未输入任何个人持仓）：

- 基金目录 `https://fund.eastmoney.com/js/fundcode_search.js`：HTTP 200，约 3,223,149 字节；真实类型为 `混合型-灵活`、`债券型-混合二级` 等复合标签，分类已按前缀匹配。
- 基金历史净值 `https://api.fund.eastmoney.com/f10/lsjz?fundCode=000001&pageIndex=1&pageSize=2`：最新 `FSRQ=2026-11-06`、`DWJZ=0.9780`，前一行为 `2026-11-05`、`1.0000`，`FHSP` 为空。按设计，空 `FHSP` 不足以证明区间无分红/拆分，因此该来源的今日浮动保持待核实；持有估值仍使用 11-06 净值。

未验证项：公开基金源的长期稳定性、字段覆盖、分红/拆分完整覆盖与**公开展示许可**；资产/基金页面的模拟器交互走查、Android 真机安装、原生小部件在桌面的实际渲染与 30 分钟调度；release 签名与发布；iOS（已移出范围）。`FJOB_ENABLE_FUND_PUBLIC_SOURCE` 默认关闭，本次 debug APK 显式开启仅用于开发验证。

### 3.2 M8-HOME 本轮验证（2026-11-09）

环境同 3.1；Android 14（API 34）模拟器 1080 × 2400 @ 420 dpi。

| 命令 | 结果 |
| --- | --- |
| `cd packages/finance_core && dart test` | 110 passed |
| `cd apps/mobile && flutter analyze` | No issues found |
| `cd apps/mobile && flutter test` | 172 passed、1 skipped（既有跳过项） |
| `cd apps/mobile && flutter build apk --debug` | 成功 |

覆盖：HD-01/02/03/04/05/06/08/09/11/12/15/16/17/18/19 的领域与组件断言；恰好 18:00 与 06:00、17:59:59.900、跨夜跨月、休息日、排班未知、部分小计、不可用、陈旧报价、长金额、320 dp、200% 字体、三种显示模式、隐藏卡语义、连续选择/迟到失败/写入失败回滚、示例隔离、schema v5 迁移与清空重置。M7-FUND 的基金已知小计与首页完整性提示保持兼容。

模拟器走查：默认双卡、显示设置展开、仅下班、仅结余、200% 系统字体；截图见 `docs/screenshots/12-implementation-*.png`。双卡首屏同时可见两个主值；单卡模式不保留空位或装订细节；200% 字体下选项纵排、卡片增高且可滚动。

产物（同一路径已被 M8-HOME 构建覆盖）：

- `G:\game\nw\FJOB\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk`
- 大小：163,026,082 B；SHA-256：`26d42142f3bee5d8bf2c6fd44dd0df610887811e47c6dbe8e2e8b5bf40b85b70`；`versionName=0.1.10`、`versionCode=11`
- 3.1 的 SHA-256 记录对应 M8-HOME 合并前的 M7-FUND 构建，不再对应当前文件。

未验证：物理真机、真实行情来源展示许可、原生小部件桌面实装、release 签名产物（由 tag CI 构建）。

### 3.3 M9-PC 本轮验证（2026-11-11）

环境：Windows 11 专业版 10.0.26300，2560×1440 @125% DPI（逻辑 2048×1152），16 核；release 构建 `apps/desktop/build/windows/x64/runner/Release/todayagain_desktop.exe`；走查账本由 `tool/make_walkthrough_bundle.dart` 锚定 2026-11 生成（月薪 12000、房贷 4800/本金 2800、车贷 1800/本金 1500、A股 000001×1000、黄金×20），经 `.fjob` 真机导入。

| 命令 | 结果 |
| --- | --- |
| `cd packages/finance_core && dart analyze` | No issues found |
| `cd packages/finance_core && dart test` | 110 passed |
| `cd packages/ledger_model && dart test` | 77 passed |
| `cd packages/ledger_store && dart test` | 13 passed |
| `cd packages/market_data && dart test` | 65 passed |
| `cd packages/fjob_ui && flutter test` | 35 passed |
| `cd apps/desktop && flutter analyze` | No issues found |
| `cd apps/desktop && flutter test` | 19 passed（12 基线 + 层级回归 1 + 真实 IO 回归 1 + 定位解析 5） |
| `cd apps/mobile && flutter analyze` | No issues found |
| `cd apps/mobile && flutter test` | 176 passed、1 skipped（共享包改动后无回归） |
| `python -X utf8 tools/verify_handoff.py` | PASS（24 参考计算 + OpenAPI + v1/v2 schema + 隐私反例 + 文档链接） |
| `flutter build windows --release` | 成功（最终 data/app.so 于修复后重建） |

固定窗真机走查（PowerShell UI 自动化 + PrintWindow 截图，见 docs/21）：S/M/L 三档切换、显示项都显示/只看下班/只看结余、金额隐身遮蔽（结余 ¥••••、下班时间保留）、老板键 Ctrl+Alt+H 隐身/恢复、点击穿透开启（右键透传、无菜单）与关闭、锁定位置防拖拽、拖拽移动、位置记忆持久化与重启恢复、右键菜单四项（打开主窗/金额隐身/点击穿透/隐藏到托盘）、双击拉起主窗、纸面透明度 85%/100%、125% DPI 无裁切、贴角定位（逻辑边距 28/22 精确换算）。视觉层级按用户要求落地：下班时间为固定窗主核心（M 档 40px 倒计时 + 迷你计薪进度），今日生存结余为次核心（金额 34px、S 档 21/18px）。

本轮修复（真机走查发现，均有回归测试）：偏好保存失败（createTemp 混合分隔符 ERROR_PATH_NOT_FOUND，改为确定性暂存目录 + 规范化路径）；页面偏好与持久化不同步（provider 启动同步）；卡窗右键菜单崩溃（showMenu 使用 MaterialApp 之外的 context）；卡窗位置记忆缺失（onWindowMoved 上报 + 指纹校验恢复 + 程序性贴角后上报）；双 preferences store 实例互覆盖（main 单实例 override）；finance_core 2 处 analyze 遗留。

范围变更（用户决定，2026-11-11）：PC 端**移除今日页**，主窗五页改四页（配置/桌面/数据/设置），默认落配置页；欢迎面板改为一次性 dismiss（`_welcomeDismissed`），`lib/pages/today_page.dart` 删除。今日页相关的 parity 走查与手机到分核对随之取消。

发布（CI，2026-11-11）：`desktop-v0.1.0`（prerelease）由 `desktop-release` 工作流构建并发布：

- 安装包 `FJOB-Setup-0.1.0.exe`：11,755,126 B；SHA-256 `08df558d9c0e3e3b08a6138a3e95168ad5c79d260a31fb27274117c09dad1139`
- 便携 zip `fjob-desktop-0.1.0-win-x64.zip`：14,045,061 B；SHA-256 `1d1b2f5c99aa8fa4d6d5998a293403c25dab3f17e379c1ddf42fc5e3fe165497`
- `SHA256SUMS` 随 Release 提供；真机静默安装/卸载（退出码 0、卸载干净）与「检查更新 → 已是最新版本（0.1.0）」已验证。
- 早期本地包 SHA `6c4421fa…`、`5046fc2e…`、`dc0836df…` 均作废。

发布（CI，2026-11-12）：`desktop-v0.1.1`（prerelease）由 `desktop-release` 工作流（run #3）构建并发布，修复托盘图标与小窗最小化，并合入 docs/22 的表格/预览修复：

- 安装包 `FJOB-Setup-0.1.1.exe`：11,761,991 B；SHA-256 `8935e505615997b61d52e194f5b20588fc077e6caafe28cef253100ec8822340`
- 便携 zip `fjob-desktop-0.1.1-win-x64.zip`：14,053,487 B；SHA-256 `a39e0c61f9de671a4b0d17c6dcc0d8520fba6adf20ffba5178df7662211f4dcd`
- `SHA256SUMS` 随 Release 提供；下载后与 GitHub asset digest、本地 SHA-256 三方一致；便携 exe FileVersion `0.1.1+2`，包内 `data/flutter_assets/assets/tray_icon.ico` 存在。
- 未配置签名 Secrets：安装包与 exe 均为 `NotSigned`；本版未做真机静默安装/卸载与「检查更新 → 0.1.1」复测。

发布（CI，2026-11-12）：`v0.1.12` 与 `desktop-v0.1.2`（prerelease）分别由 `android-release` run #15、`desktop-release` run #4 构建：

- 手机 APK `fjob-0.1.12-universal.apk`：59,513,955 B；SHA-256 `8b0c40bb92e7c2799aecd67ac4e603f333fa247c9bfaae2a99d47fa12badc27e`；`aapt2` 显示 versionName `0.1.12` / versionCode `1015`。
- PC 安装包 `FJOB-Setup-0.1.2.exe`：11,764,052 B；SHA-256 `44e00e4c4044d8d9c1abf302ea6a0c5f745ef0b5f61295ab127217f8afcba408`
- PC 便携 zip `fjob-desktop-0.1.2-win-x64.zip`：14,053,624 B；SHA-256 `e8794baa567e67f05c1eedd05c2cf46eed1d4961b2a8ec330a508f98a24265ad`；exe FileVersion `0.1.2+3`，包内 `data/flutter_assets/assets/tray_icon.ico` 存在。
- 下载后与 GitHub asset digest、`SHA256SUMS`、本地 SHA-256 三方一致；PC 安装包/exe 为 `NotSigned`（未配置 Secrets）。
- 手机端在 Android 16 模拟器完成 release APK 的 `.fjob` 导入 + `下载/FJOB` 兜底导出；PC 端在临时 APPDATA 实跑手动保存工资+排班后固定窗显示金额。

未验证：全屏应用自动隐藏（模拟器探针受焦点竞争干扰，需真实全屏应用实测）、托盘菜单逐项点击、200% 缩放/键盘全流程/Narrator、空闲内存 <150MB（上轮 168.7MB 缺口未复核）、配置/数据/设置页功能级走查、PC 与手机同账本到分一致的真机核对、真实行情来源展示许可、代码签名（未配置 Secrets）、`v0.1.12` 手机真机覆盖安装与应用内更新、`desktop-v0.1.2` 真机安装/卸载与更新器复测。

## 4. 原型的简化边界

| 内容 | 原型状态 | 正式开发要求 |
| --- | --- | --- |
| 时间和月份 | 固定2026年11月演示 | 真实时钟、年月与时区 |
| 排班 | 手填本月天数，同日班次 | 月历、跨夜、日期覆盖和版本 |
| 行情 | 模拟价格 | 适配器、来源、授权与故障策略 |
| 资产 | 一个A股槽位与一笔黄金 | 多证券和版本化持仓 |
| 本地存储 | 浏览器状态与草稿 | SQLite、迁移、事务和修订 |
| 示例隔离 | 浏览器体验入口 | 独立正式/示例命名空间与退出恢复 |
| 住房切换 | 当前演示账本整体重算 | 生效期与历史分段 |
| 小部件 | 布局和同步数据预览 | Kotlin/Swift 原生扩展及系统调度 |
| 发布 | 开发设计和任务 | 真实工作流、签名及商店上传 |

HTML 原型使用 JavaScript 数字进行演示。正式金额、跨平台快照和历史结果按领域契约使用明确精度。引导中的演示昨收输入只为模拟界面提供数据，正式版本自动获取。

## 5. 发布验收记录模板

记录版本号、Git commit、工具链锁、测试设备与系统、执行日期、验收编号、预期、实际、截图/日志、缺陷、修复提交和复验结果。

完成标准为 P0 需求全部通过，真实行情来源具备可用与展示证据，Android 签名产物可安装，iOS TestFlight 与小部件真机运行通过。未验证项保留明确状态，不能用原型演示结果替代生产构建结果。
