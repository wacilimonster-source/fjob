# PC 体验打磨走查与修复说明（续 docs/21）

版本 1.0 · 2026-11-12 · 用途：记录本轮「配置页表格 / 桌面页预览」体验打磨的发现、根因与修复，交给下一个 agent 继续收尾。

> 先读 `AGENTS.md`、`docs/16`、`docs/21`，再读本文。所有结论均来自本会话**实际运行输出**（退出码逐一核对）；标注「未验证」的项不要当成已通过。

## 0. 本轮目标（用户指令）

不断打磨 PC 端产品体验，但**不做复杂化**，保持精简精致与现有丧萌手绘风格、主线设计。本轮聚焦主窗四页的走查与修复，不动固定窗主线与视觉资产。

## 1. 走查方法与发现

用 release 构建（真机 125% DPI，`pc20-ui.ps1` PrintWindow 截图）逐页走查：配置四子页、桌面页、数据页、设置页、L 档固定窗。数据/设置/住房与车贷/固定窗四页均状态良好；发现两处体验问题：

| # | 问题 | 现象（走查前截图 `21-pc-62-assets.png`、`21-pc-64-bills.png`） |
| --- | --- | --- |
| 1 | **资产/账单表格整页布局作废** | 资产页「资产持仓」标题与「添加持仓」按钮完全不可见（空白条占位）；列头 `标的持仓成本今日持有状态操作` 全部粘连；行数据 `1000 股13 元/股-150.00-1290.00正常` 粘连；账单页列头同样粘连。release 下静默发生，debug 下抛 `BoxConstraints forces an infinite width` |
| 2 | **桌面页「即时预览」在默认窗口看不到** | 页面副标题承诺「所有设置即时预览」，但预览面板（`固定窗预览`）被挤到折叠线以下，须滚过全部开关才能看到 |

## 2. 根因

**#1 两层叠加，根因相同（无界宽度）：**

1. `_hScrollTable`（`config_page.dart`）用 `ConstrainedBox(minWidth)` 包裹横向滚动容器。横向 `SingleChildScrollView` 本身给子级传**无限最大宽**，`ConstrainedBox` 只抬高下限不下压上限；外层 `Column(crossAxisAlignment: stretch)` 便把 `tightFor(width: ∞)` 传给每个表格行，`Expanded` 列退化为文字自然宽 → **列塌缩粘连**（debug 下为无限宽崩溃）。
2. 资产表头 `Row(Expanded(SectionLabel), FilledButton.icon)`：Row 的**非 flex 子项按设计拿无界宽**（flex.dart `_constraintsForNonFlexChild`）。无界宽的 `FilledButton.icon`（M3 有 Material/PhysicalShape 装饰层）在 TabBarView 页重排时会以无限宽参与该行伸缩计算，把 `Expanded` 拖成负数可用空间，**整页布局作废**——这就是 release 下表头与空状态不可见的直接原因。独立 widget 测试矩阵证明：同一结构仅在给按钮一个有界宽度后即恢复（screenshots 中间的复现测试已被删除）。
3. 另发现资产/账单操作列 `SizedBox(width: 88/92)` 装两个默认 `IconButton`（各 48 最小宽）**右溢出 8px**。

**#2** 桌面页 `LayoutBuilder` 分栏阈值 860，而默认窗口（1000 逻辑宽 − 导航 168 − 页边距 44）可用仅 788，永远走堆叠分支；配置页 `_tabWithPreview` 的阈值是 800 且 padding 在分支内部（LayoutBuilder 拿到整幅 832），桌面页却把 padding 放在 LayoutBuilder 外层。

## 3. 修复（全部为最小改动，不动视觉风格）

| 文件 | 修改 |
| --- | --- |
| `apps/desktop/lib/pages/config_page.dart` | `_hScrollTable` 改用 `SizedBox(width: max(minWidth, constraints.maxWidth))` 给表格列**有界紧约束**；资产表头按钮包 `IntrinsicWidth`（按钮收窄到自身固有宽，视觉不变，伸缩计算不再发散）；操作列 88/92 → 100（消除 8px 溢出）；资产表 minWidth 880 → 780（默认窗口 788 一屏放下全部列，操作列不再需要横向滚动；账单表 840 保持设计横向滚动兜底） |
| `apps/desktop/lib/pages/desktop_page.dart` | 标题区自带左右留白，`LayoutBuilder` 拿整幅 832；阈值 800、预览宽 300，与配置页 `_tabWithPreview` 几何完全一致；默认窗口即左右分栏 |
| `apps/desktop/test/config_table_layout_test.dart`（新） | sample 模式驱动真实资产/账单表格：断言**无布局异常**、「资产持仓」标题与「添加持仓」按钮可见、列列距 >120（防塌缩回归） |
| `apps/desktop/test/desktop_page_layout_test.dart`（新） | 主窗默认 1000×680 逻辑尺寸下，桌面页「固定窗预览」与设置卡**左右分栏且同屏可见**（防折叠线回归） |

不修复/保持现状：数据页、设置页、固定窗与共享视觉资产本轮零改动。

## 4. 验证（全部实际运行，退出码逐一核对）

| 命令 | 结果 |
| --- | --- |
| `cd apps/desktop && flutter analyze` | No issues found（exit 0） |
| `cd apps/desktop && flutter test` | **33 通过**（含新增 3 项回归；exit 0） |
| `packages/finance_core` `dart analyze` + `dart test` | 无问题；110 通过 |
| `packages/ledger_model` `dart test` | 77 通过 |
| `packages/ledger_store` `dart test` | 13 通过 |
| `packages/fjob_ui` `flutter test` | 35 通过（注：fjob_ui 是 Flutter 包，须用 `flutter test`，`dart test` 报缺 dev 依赖） |
| `packages/market_data` `dart test` | 65 通过 |
| `apps/mobile` `flutter analyze` + `flutter test` | 无问题；**176 通过 + 1 跳过**，无回归 |
| `flutter build windows --release` | exit 0（data/app.so 2026-11-12 01:50） |
| 真机复验（release，125% DPI） | 资产页全部列含操作列一屏可见（`22-pc-05-assets-default.png`）；账单页列对齐、利息/状态/操作按设计横向滚动（`22-pc-06-bills-default.png`）；桌面页默认窗口左右分栏、预览即现（`22-pc-04-desktop-default.png`）；L 档固定窗无回归（`22-pc-07-card-default.png`） |

修复前对照：`21-pc-62-assets.png`、`21-pc-64-bills.png`、`21-pc-65-desktop-page.png`。

## 5. 关键教训（务必遵守）

- **横向 `SingleChildScrollView` + `Column(stretch)` 是禁区**：滚动方向上子级拿无限宽，stretch 列塌缩；必须用 `SizedBox(width: …)` 给有界紧约束，不能只用 `ConstrainedBox(minWidth)`。
- **`Row` 的非 flex 子项永远拿无界宽**（flex.dart 设计如此）。`FilledButton.icon` 这类带 Material 装饰层的按钮若与 `Expanded` 同行，须包 `IntrinsicWidth` 或 `ConstrainedBox` 收窄，否则在 TabBarView 重排路径上可把同行 Expanded 拖成负数空间、整页布局作废（release 下静默）。`TextButton`、全 flex 行、无 Expanded 的行均无此问题。
- **表格操作列**：两个默认 `IconButton` 需 ≥96 逻辑宽，`SizedBox(width: 88/92)` 必溢出；本轮统一 100。
- **分栏阈值必须与内容几何同源**：配置页的 padding 在分支内部（LayoutBuilder 拿 832），桌面页此前 padding 在外层（LayoutBuilder 拿 788），同样阈值 800/860 两页行为不一致；本轮已统一为「LayoutBuilder 拿整幅 + 分支内留白」。
- **widget 测试中 TabBar 切页**：`tester.tap` 后必须多次 `pump(100ms)` 推进动画；单次 `pump(2s)` 会让 PageView 动画停在半途。`pumpAndSettle` 会因固定窗/预览里的无限循环办公室动画永不返回，勿用。
- **flutter build 不会更新 runner exe 的 mtime**（只更新 data/app.so）；判断构建新鲜度看 `data/app.so` 时间戳，不要看 exe。

## 6. 未验证 / 外部依赖（发布门禁，继承 docs/21 §6 并更新）

- 配置四子页的**编辑→保存→预览联动**功能级走查仍未做（本轮验证了表格渲染与布局）；数据页导入/导出往返、设置页走查同样未做。
- 「PC 固定窗与手机同账本到分一致」真机核对仍未做；200% 缩放/键盘全流程/Narrator 未测；内存 <150MB 缺口未复核。
- 全屏自动隐藏、睡眠/唤醒/改时未实测（探针不可靠，沿用 docs/21 结论）。
- 真实行情来源稳定性与公开展示许可（Eastmoney developmentOnly）；代码签名、Windows CI 真机联跑、PC6 局域网同步、macOS。
- 本轮改动已随 release 重构建真机验证，但**便携 zip 与安装包尚未重打包**（沿用 docs/21 §5.2 流程，发布前须重打 + 重算 SHA-256）。

## 7. 交付报告要求（AGENTS.md）

见本轮对话末尾交付报告；需求/任务编号、修改文件、命令与退出码、截图与验证记录均已列出。
