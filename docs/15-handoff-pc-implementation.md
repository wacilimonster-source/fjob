# PC 伴生端实施交接与素材复用计划

版本 1.0 · 2026-11-10 · 状态：**决策已确认；M9-PC0 可开工**。关联 `docs/13`、`docs/14`、`prototype/pc.html`、`docs/09`、`prototype/ANIMATION-README.md`。

## 0. 已确认的决策

| # | 决策 | 结论 |
| --- | --- | --- |
| 1 | 首版平台 | Windows 10 1809+ / Windows 11 x64；macOS 后续 |
| 2 | 技术栈 | Flutter Windows，复用 `finance_core`；不采用 Tauri/Electron |
| 3 | 数据路线 | v0.1 本地账本 + `.fjob` 导入/导出；v1.1 局域网配对；云同步暂不做 |
| 4 | PC 编辑权 | 可编辑配置；明确主账本设备；冲突不自动合并财务实体 |
| 5 | 固定窗尺寸 | M 320 × 220；L 420 × 390；S 220 × 76 |
| 6 | 隐私边界 | 金额隐身作用于固定窗、配置预览、托盘提示、窗口标题、固定窗无障碍文案；主窗保持可见 |
| 7 | 素材与动效 | **必须复用手机端的 Dart painter、调色板、图标、显示映射和动效常量**；不复制原型 HTML Canvas，不把截图/关键帧当生产素材 |

### 0.1 PC0 实测结论（2026-11-10）

- Flutter 3.47.9 stable 的官方实验性 windowing 能创建原生窗口，但 Flutter 内容区空白；stable 工具链的 `enable-windowing` 为 Unavailable。不能作为产品路线。
- 已切到 `desktop_multi_window 0.3.1` + `window_manager 0.5.1`。主窗、第二个原生窗口、老板键、托盘、点击穿透样式可用。
- **已修复**：secondary engine 通过 `DesktopMultiWindowSetWindowCreatedCallback` 注册 `window_manager` 和 `screen_retriever`；`screen_retriever` 返回物理工作区、`window_manager` 使用逻辑坐标，定位前除以 `scaleFactor`。
- PC0 核心通过：主窗 + 固定窗、125% DPI 完整显示、老板键、点击穿透、托盘、单实例。剩余全屏/睡眠/多显示器/性能见 `docs/17-pc0-spike-report.md`。

### 0.2 工具链预检（2026-11-10 实际执行）

- Flutter 3.47.9 / Dart 3.13.7，SDK 位于 `G:lutter`；`flutter`/`dart` 未加入 PATH，命令使用绝对路径或先补 PATH。
- Flutter 已启用 Windows desktop；`flutter doctor` 识别到 `Windows (desktop) • windows-x64`。
- Visual Studio 生成工具 2022 17.14.37 + Windows 10 SDK 10.0.26100 已安装，满足 Flutter Windows 构建前置条件。
- `HTTP_PROXY` 已设置，`NO_PROXY` 未设置；依赖下载、GitHub Releases 与镜像访问需在 PC0 中实际验证，不能默认通畅。
- 尚未执行 `flutter create` / `flutter build windows`；尚无 spike app、exe、托盘或窗口行为实测。本节只证明工具链存在，不证明窗口能力。

## 1. 复用原则

1. **代码就是素材。** 手机端的角色、房子、车、办公室、硬币、天气全部由 Flutter `CustomPainter` 绘制，没有可复用的位图场景资源。复用 = 共享 Dart 代码，不是搬 PNG。
2. **一套逻辑坐标系。** 场景沿用 380 × 238 逻辑坐标；PC 只做等比缩放、裁切或重新排布，不改人物/房车的比例和线宽。
3. **一套动效时钟。** 拍肩 3200 ms、低动效 2400 ms、离场 2200 ms、离场窗口 2000 ms、环境循环 8 s，全部来自共享常量；PC 不另写时长。
4. **一套颜色。** `FjobPalette` 的十个 token 是唯一色源；PC 只增加布局尺寸，不新增角色/场景配色。
5. **一套显示映射。** `HomeMetricsModel` 和 `format.dart` 决定标签、金额字符串、进度与无障碍语义；PC 固定窗直接消费，不重写一套“差不多”的文案。
6. **原型只做评审。** `prototype/pc.html` 的 Canvas JS 是视觉参照，不是生产资产；生产端不得逐行移植 JS 绘制。
7. **PC 只允许改构图。** 主窗布局、固定窗三档、紧凑场景的裁切/排布是 PC 专属；角色、房车、硬币、图标、动效本身必须同源。
8. **位图谨慎。** `assets/brand/app-icon-concept-v1.png` 是概念图，未确认可用于正式图标；生产图标另行设计/导出，不直接把概念图打进安装包。

## 2. 复用矩阵

| 资产/能力 | 当前来源 | 复用方式 | PC 用途 | 抽取动作 |
| --- | --- | --- | --- | --- |
| 调色板 `FjobPalette` | `apps/mobile/lib/app/theme.dart` | 直接复用 | 主窗、固定窗、图表、表单 | 抽到 `packages/fjob_ui`；手机改为 import |
| 字体/字重/数字特性 | `theme.dart`、`docs/02` | 复用 token；PC 增加桌面字号档 | 主窗与固定窗排版 | 抽 `FjobTypography`；PC 只加 desktop scale |
| 手绘时钟/账单图标 | `dashboard_page.dart` 内 `_HandDrawnClockIcon`、`_HandDrawnBillIcon` | 直接复用 | 固定窗标签、主窗指标卡 | 抽到 `fjob_ui/icons.dart`，手机与 PC 共用 |
| 角色 `WorkerFrame` / `WorkerPainter` | `worker_painter.dart` | 直接复用 | 主窗 Today 场景；L 档紧凑场景 | 抽到 `fjob_ui/scene/worker_painter.dart` |
| 房子/车 `DebtArtPainter` / `DebtArt` | `office_scene.dart` | 直接复用 | 主窗场景、住房/车贷页、L 档场景 | 抽到 `fjob_ui/scene/debt_art.dart` |
| 办公室 `OfficeScene` / `_OfficePainter` | `office_scene.dart` | 直接复用 | 主窗 Today 完整场景 | 抽到 `fjob_ui/scene/office_scene.dart` |
| 拍肩/离场控制器 | `scene_interaction_controller.dart` | 直接复用 | 主窗“拍拍他”；离场 | 抽到 `fjob_ui/scene/scene_interaction_controller.dart` |
| 拍肩文案池 `PatResponses` | 同上 | 直接复用 | 主窗语气反馈 | 同包导出；`AppTone` 抽到 `ledger_model` |
| 环境动画（呼吸 4 s、打字 2 Hz、硬币 2–4 s） | `office_scene.dart` / `worker_painter.dart` | 直接复用 | 主窗 Today | 不改参数；PC 只控制 `active`/`reduceMotion` |
| 动效常量 | `scene_interaction_controller.dart` | 抽 `SceneMotion` 常量类 | 主窗、引导、测试 | 3200/2400/2200/2000/8000 ms 单一来源 |
| 显示映射 `HomeMetricsModel` | `home_metrics_model.dart` | 直接复用 | 主窗双卡、固定窗 S/M/L | 抽到 `packages/ledger_model`（纯 Dart） |
| 金额/时间格式 `format.dart` | `domain/format.dart` | 直接复用 | 主窗、固定窗、账单 | 抽到 `ledger_model` |
| `AppTone` | `domain/ledger.dart` | 抽到 `ledger_model` | 语气设置、拍肩文案 | 手机 import 改为包 |
| 品牌标记 | 原型为 `(－_－)` 便签 | 代码绘制 `BrandMark` | 标题栏、托盘、任务栏 | 抽到 `fjob_ui`；不使用概念 PNG |
| 动画关键帧 PNG | `prototype/animation-keyframes` | **不复用** | 仅评审参考 | 不打包、不上架、不当生产素材 |
| Android 小部件快照 | `contracts/widget-snapshot-v2` | 不复用为 PC UI | 仅参考数据字段 | PC 固定窗直接消费 `DashboardSnapshot`，不经过 Android RemoteViews |
| 手机端页面布局 | `dashboard_page.dart` | 不复用 | — | PC 主窗按 `docs/14` 重新排版 |

## 3. 共享包结构

```text
packages/
  finance_core/          # 纯 Dart 计算，不变
  ledger_model/          # 领域实体、AppTone、format、HomeMetricsModel、.fjob bundle
  fjob_ui/               # Flutter：palette、type、icons、BrandMark、scene、controller
apps/
  mobile/                # import fjob_ui / ledger_model
  desktop/               # import fjob_ui / ledger_model / finance_core
```

依赖方向：

```text
finance_core
   ↑
ledger_model（纯 Dart，无 Flutter）
   ↑
fjob_ui（Flutter，依赖 finance_core + ledger_model）
   ↑
apps/mobile、apps/desktop
```

`fjob_ui` 只依赖 `flutter`、`finance_core`、`ledger_model`，不依赖 `dart:io`、平台通道、数据库或行情客户端。这样它可以在 Windows、Android 和测试环境中复用。

### 3.1 `fjob_ui` 导出面

```dart
// palette & type
FjobPalette, FjobTypography, FjobTheme

// icons & brand
HandDrawnClockIcon, HandDrawnBillIcon, BrandMark

// scene
OfficeScene, CompactOfficeScene
SceneInteractionController, ScenePresentation,
SceneMood, Presence, TransientKind, PatResponses
WorkerPainter, WorkerFrame, DebtArtPainter, DebtArt, DebtArtType
SceneMotion
```

### 3.2 `ledger_model` 导出面

```dart
AppTone
formatMoney, formatAmount, formatSigned, formatHours, formatPercent,
formatClock, formatDuration, formatDate, formatMonth, weekdayLabel
HomeMetricsModel, HomeTimeState, HomeTimeDisplay, HomeBalanceDisplay
LedgerBundle（.fjob 格式）
```

`HomeMetricsModel` 目前依赖 `finance_core` 与 `AppTone`；抽取时不改逻辑，只改 import。

## 4. 抽取步骤（M9-PC1）

1. 建 `packages/fjob_ui` 与 `packages/ledger_model`，加入 workspace/路径依赖。
2. 把 `FjobPalette`、`FjobTheme` 抽到 `fjob_ui`；手机端改为 import；运行 `flutter analyze` 与 `flutter test`。
3. 把 `format.dart`、`AppTone`、`home_metrics_model.dart` 抽到 `ledger_model`；运行手机端测试，确认双卡文字/金额不变。
4. 把 `worker_painter.dart`、`office_scene.dart`、`scene_interaction_controller.dart` 抽到 `fjob_ui`；把 `_HandDrawnClockIcon`、`_HandDrawnBillIcon` 抽到 `fjob_ui/icons.dart`。
5. 手机端 `dashboard_page.dart` 改为 import 共享包；删除重复实现；保留页面布局代码。
6. 运行：`packages/finance_core: dart test`、`apps/mobile: flutter analyze && flutter test`；对比手机首页截图（双卡、场景、拍肩、离场）。
7. 新增 `CompactOfficeScene`（380 × 112），复用 `WorkerPainter`、`DebtArtPainter`、`FjobPalette`；不新增角色/房车画法。它只负责紧凑构图：房子、车、半身角色、桌面、显示器、咖啡/绿植、硬币、天气。
8. 新增共享包测试：
   - `WorkerFrame.resolve` 对同一 `ScenePresentation` 输出相同参数；
   - `HomeMetricsModel` 对固定 fixture 输出与手机相同的标签/金额字符串；
   - `FjobPalette` 十个 token 与设计值一致；
   - `OfficeScene` 在 380 × 238 的 smoke test；
   - `CompactOfficeScene` 在 380 × 112 的 smoke test。
9. 可选：在 Windows CI 生成 `OfficeScene` 的 golden；只作为视觉 smoke，不跨平台卡像素。

## 5. PC 场景适配

| 位置 | 使用组件 | 适配 |
| --- | --- | --- |
| 主窗 Today | `OfficeScene` | 固定 380:238 比例，按容器宽度缩放；传入 `phase`、`completeness`、`total`、`reduceMotion`、`controller`、`showHousing`、`showCar`、`housingLabel`、`carLabel` |
| 主窗“拍拍他” | `SceneInteractionController` + `headShoulderRect` | 点击头肩或按钮；同一 3.2 s 回应；PC 无触觉反馈 |
| 主窗下班离场 | `SceneInteractionController` | `visible` 取主窗可见性；只在主窗可见时跨过班次终点播放；隐藏/恢复不补播 |
| L 档固定窗 | `CompactOfficeScene` | 380 × 112 紧凑构图；同一 `ScenePresentation`、同一调色板、同一角色/房车 painter |
| 引导/首启插画 | `OfficeScene(interactive:false)` | 静态或低动效，不启用拍肩 |
| 托盘/任务栏图标 | `BrandMark` 或代码标记 | 16/32 px 简化版；不直接缩小复杂场景 |

PC 不允许：

- 为固定窗重画一套角色或房车。
- 用手机截图裁切后贴进 PC 卡片。
- 另写一套“PC 版拍肩”时长。
- 把 `prototype/pc.html` 的 Canvas 绘制移植成生产代码。

## 6. 动效一致性表

| 行为 | 手机实现 | PC 要求 | 单一来源 |
| --- | --- | --- | --- |
| 打字 | 约 2 Hz | 同频；低动效停止 | `WorkerFrame` / ambient |
| 呼吸 | 约 4 s | 同频 | `OfficeScene` ambient |
| 环境循环 | 8 s | 同频；不可见时暂停 | `OfficeScene` AnimationController |
| 拍肩 | 3200 ms | 同长；无触觉 | `SceneMotion.pat` |
| 低动效拍肩 | 2400 ms 静态回应 | 同长；只更新表情/文案 | `SceneMotion.patReduced` |
| 下班离场 | 2200 ms | 同长；只在主窗可见时播放 | `SceneMotion.departure` |
| 离场窗口 | 2000 ms | 同窗口；恢复前台不补播 | `SceneMotion.departureWindow` |
| 硬币 | 2–4 s 一批，数量有上限 | 同参数；低动效停止 | `OfficeScene` |
| 状态切换 | 200–350 ms | 同区间 | `docs/02` + shared transitions |

PC 的窗口出现、页面切换、固定窗密度切换属于桌面交互，可单独定义；但一旦进入“人物/房车/硬币/拍肩/离场”，必须走上表。

## 7. 测试与 CI

### 手机回归

- `cd packages/finance_core && dart test`（必须消费 `fixtures/calculation-cases.json`）。
- `cd apps/mobile && flutter analyze && flutter test`（当前 172 passed、1 skipped）。
- 截图回归：首页双卡、办公室、拍肩、离场、住房/车贷插画。

### 共享包

- `fjob_ui`：`flutter test`；`WorkerFrame` 参数、`CompactOfficeScene` smoke、palette token。
- `ledger_model`：`dart test`；`HomeMetricsModel` fixture、金额格式、`.fjob` 校验。
- 不把 `prototype/animation-keyframes` 当 golden；它们是手机画面参考，不是组件输出。

### PC

- `apps/desktop: flutter analyze && flutter test`。
- 领域测试消费同一 `fixtures/calculation-cases.json`；PC 与手机对同一 fixture 输出到分一致。
- 窗口行为（置顶/穿透/多屏/DPI/全屏/睡眠）以 M9-PC0 的实测报告为准，不用组件测试替代。
- CI：`windows-latest` 构建 zip；共享包测试在 Linux/Windows 都跑；签名密钥只放 Secrets。

### 视觉对比

- 在同一逻辑尺寸 380 × 238 下分别渲染手机与 PC 的 `OfficeScene`，人工对比人物、房子、车、线宽、颜色。
- 不要求跨平台像素完全一致（字体栅格化可能不同）；要求构图、比例、色值、线宽、动效参数一致。
- PC 固定窗 L 的紧凑场景单独评审，但角色/房车必须来自同一 painter。

## 8. M9-PC0 技术验证清单

目标：用最小 demo 验证 Windows 窗口能力，不接账本、不接行情。产出 `docs/16-pc0-spike-report.md`（或等价记录），含系统版本、命令、截图、通过/失败、降级方案。

| # | 验证项 | 通过标准 | 失败时降级 |
| --- | --- | --- | --- |
| 1 | Flutter Windows 构建 | `flutter build windows` 成功；VS 2022 C++ 工具链可用 | 锁定工具链版本；补 CI 镜像 |
| 2 | 主窗 + 固定窗同时存在 | 两个顶层窗口同时可见、共享状态、无闪烁 | 单窗口 + 卡片模式；或卡片原生窗口 |
| 3 | 无边框 + 圆角 | Win11 圆角正常；Win10 可接受方形/透明回退 | 方形纸面 + 自绘边 |
| 4 | 置顶 + 不抢焦点 | 覆盖普通窗口；启动不抢当前输入焦点 | 置顶可关；首次显示 inactive |
| 5 | 点击穿透 | `WS_EX_TRANSPARENT` 生效；热键/托盘可解 | 取消穿透，保留“锁定” |
| 6 | 托盘 + 单实例 | 托盘菜单、显示/隐藏、退出；第二次启动唤起主窗 | 任务栏图标兜底 |
| 7 | 全局热键 | 老板键/金额隐身/穿透可用；冲突可检测/改键 | 仅托盘菜单 |
| 8 | 开机启动 | 当前用户启动项，无需管理员；可关闭 | 手动启动 |
| 9 | 多显示器 + DPI | 100/125/150/200% 不裁切；拔插后回主屏 | 固定主屏 |
| 10 | 全屏检测 | 真全屏应用自动隐藏，退出恢复；最大化窗口不误判 | 手动“演示模式” |
| 11 | 睡眠/唤醒/改时 | 恢复即重算；不补播；跨日正确 | 恢复时提示手动刷新 |
| 12 | 性能 | 空闲 CPU < 1%、内存 < 150 MB、场景 60 fps | 降帧/静态帧/减少阴影 |
| 13 | 安装/分发 | 便携 zip 可运行；安装包/签名方案可评估 | 仅便携 zip |
| 14 | 素材复用 | `OfficeScene`/`WorkerPainter` 在 Windows 渲染正常，与手机同源 | 修正 painter 的平台无关性，不重画 |

建议 timebox：3–5 个工作日；先做 2、4、5、6，再补 9、10、12。若 2/5 不通过，固定窗方案需要重新评估，不能直接进入 PC3。

## 9. 任务拆分

| 编号 | 任务 | 交付物 | 依赖 |
| --- | --- | --- | --- |
| M9-PC0 | Windows 窗口技术验证 | demo exe + spike 报告 + 降级结论 | 无 |
| M9-PC1 | 共享层与 `.fjob` | `fjob_ui`、`ledger_model` 抽取；手机导出/导入；素材 parity 测试 | PC0 可并行 |
| M9-PC2 | 主窗与配置 | 今日、收入排班、资产、住房车贷、账单、实时预览、本地库 | PC1 |
| M9-PC3 | 固定窗 | S/M/L、状态矩阵、隐私、穿透、托盘、位置记忆、L 紧凑场景 | PC0、PC2 |
| M9-PC4 | 行情与完整性 | 网关客户端、缓存、降频、部分/陈旧、跨端 fixture | PC2 |
| M9-PC5 | 打包发布 | CI、便携 zip、安装包、更新检查、校验和 | PC2–PC4 |
| M9-PC6 | 局域网同步 | 配对、manifest、双向同步、冲突 UI | PC5 |

PC1 的“共享层”必须包含素材抽取；不能把 `fjob_ui` 留到 PC3 再补，否则固定窗会先长出一套 PC 专属角色。

## 10. 风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| Flutter 多窗口不稳定 | 主窗 + 固定窗无法共存 | PC0 先验；退化方案见 docs/14 7.4 |
| 点击穿透/透明/圆角需原生代码 | 工期与稳定性 | 少量 Win32 封装；每项单独验收 |
| 共享包抽取破坏手机 | 回归风险 | 先抽纯代码，不改逻辑；172 测试 + 截图回归 |
| 字体/文本栅格化差异 | 视觉对比不一致 | 共用布局与 token；只做人工/容差对比 |
| 紧凑场景构图不同 | 角色比例被改 | 只复用 painter，不重画角色；单独评审构图 |
| 跨平台 golden 脆弱 | CI 误报 | golden 只做 smoke，不卡跨平台像素 |
| 品牌 PNG 许可/质量 | 图标不可用 | 概念图不直接上架；另行设计/导出 |
| 性能 | 办公本卡顿 | 1 s tick、场景降帧、低动效、报价降频 |

## 11. 下一步

1. 建 `apps/desktop` + 最小 Flutter Windows demo，按第 8 节跑 M9-PC0；先验证多窗口、置顶、穿透、托盘。
2. 并行建 `packages/fjob_ui` 与 `packages/ledger_model` 的空壳，把 palette/format 先迁过去，确认手机测试仍通过。
3. PC0 通过后，按 PC1 → PC2 → PC3 推进；PC3 的 L 档场景必须直接消费 `CompactOfficeScene`，不接受“PC 专属画法”。
4. 每次交付记录：命令、截图、通过/失败、与手机视觉差异、未验证项。

## 12. 参考

- 方案：`docs/13-design-pc-companion.md`
- 详细设计：`docs/14-design-pc-detailed.md`
- 手机场景：`apps/mobile/lib/features/dashboard/office_scene.dart`、`worker_painter.dart`、`scene_interaction_controller.dart`
- 动效规范：`docs/09-design-comfort-and-clock-out.md`、`prototype/ANIMATION-README.md`
- 可视化 token：`apps/mobile/lib/app/theme.dart`、`docs/02-interaction-and-visual.md`
- 显示映射：`apps/mobile/lib/features/dashboard/home_metrics_model.dart`、`apps/mobile/lib/domain/format.dart`
