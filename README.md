# 今日又白干 · 开发交付包

版本 0.2 · 2026-11-04 · Android 优先，iOS 通过 GitHub Actions 构建发布。

## 开发入口

按顺序阅读以下材料。

1. [产品需求](docs/01-product-requirements.md)。定义范围、首次引导、页面、统计口径和异常行为。
2. [交互与视觉规范](docs/02-interaction-and-visual.md)。定义页面状态、文案、丧萌手绘和动画。
3. [技术架构](docs/03-technical-architecture.md)。定义 Flutter、数据层、行情网关、原生小部件和 CI。
4. [数据与计算契约](docs/04-data-and-calculation-contracts.md)。定义实体、精度、算法、行情及快照语义。
5. [开发任务与模型交接](docs/05-development-plan.md)。按依赖安排可独立验收的开发任务及提示词。
6. [验收与验证记录](docs/06-acceptance.md)。定义完成标准及原型实测结果。
7. [实现说明与交付验证](docs/07-implementation-notes.md)。记录本轮 M0–M5 实际落地的结构、命令结果、偏差与未验证项。

[打开交互原型](prototype/index.html)。可直接用浏览器打开，首次进入体验引导，进入后底部可重新走流程。`prototype/source.html` 为可编辑源片段，`index.html` 为独立浏览器版本。

## 机器可读材料

- `contracts/market-gateway.openapi.yaml` 为行情网关接口契约。
- `contracts/widget-snapshot.schema.json` 为 Flutter 与 Android、iOS 原生小部件共享的快照格式。
- `fixtures/calculation-cases.json` 为跨语言计算验收样例。
- `AGENTS.md` 为开发代理的项目约束与阅读顺序。

## 已确认的产品决策

- 按当月排班工时分摊到手月薪，前台持续计算与滚动显示。
- 首页突出工资、投资当日变化与固定支出组成的今日生存结余。
- A股与按克黄金，黄金使用统一人民币每克参考价估值。
- 住房支出可选房贷、房租或暂无。车贷独立配置，固定支出按自然日全天分摊。
- 疲惫小人坐在小办公室，硬币流向房子和车。房子、车与人物统一采用粗线条、扁平奶油色手绘。
- 界面固定浅色纸感，不跟随系统深色，也不提供主题切换。
- 支持 Android 与 iOS 桌面小部件。

## 本交付采用的工程默认值

工程默认采用 Flutter + Dart，Android 原生 Kotlin 小部件，iOS SwiftUI + WidgetKit。本地保存个人账本，独立行情网关只处理证券标识、公开价格与交易日历。首版免账号使用。这些是为开工补齐的设计决策，可在建项任务中调整后统一更新文档。

本目录提供需求、设计、契约、原型和开发任务。生产 App、真实行情网关及 GitHub 工作流需按任务实施。原型使用模拟报价和固定演示月份，其简化边界列于验收文档。

## 当前实现状态

已按开发任务落地 M0–M5 的开发版：`packages/finance_core` 纯 Dart 计算引擎、`apps/mobile` Flutter 应用（六步引导、四个主页面、SQLite 本地账本）、Android Kotlin 小部件与 iOS WidgetKit 源码、`services/market_gateway` FastAPI 网关。真实行情来源、iOS 扩展 target 接线、签名与商店发布仍为外部依赖。

- 工具链与命令：[docs/07-implementation-notes.md](docs/07-implementation-notes.md)、[toolchain.lock.json](toolchain.lock.json)。
- 界面截图：[docs/screenshots](docs/screenshots)。
- 快速验证：`cd packages/finance_core && dart test`、`cd apps/mobile && flutter analyze && flutter test`、`cd services/market_gateway && python -m pytest`。

## 可立即开工与外部依赖

可立即开展项目初始化、领域计算、本地数据、引导、动画和小部件快照开发。发布前需要落实真实行情的访问与展示权限、服务域名、包标识、Android 签名、Apple 开发者账号及 iPhone 真机验证。行情源调研见技术架构第 6 节，公开免密钥访问候选已经列入适配计划。
