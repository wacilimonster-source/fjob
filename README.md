# 今日又白干 · 开发交付包

版本 0.2 · 2026-11-05 · Android 单平台，通过 GitHub Release 分发 APK。

## 开发入口

按顺序阅读以下材料。

1. [产品需求](docs/01-product-requirements.md)。定义范围、首次引导、页面、统计口径和异常行为。
2. [交互与视觉规范](docs/02-interaction-and-visual.md)。定义页面状态、文案、丧萌手绘和动画。
3. [技术架构](docs/03-technical-architecture.md)。定义 Flutter、数据层、行情网关、原生小部件和 CI。
4. [数据与计算契约](docs/04-data-and-calculation-contracts.md)。定义实体、精度、算法、行情及快照语义。
5. [开发任务与模型交接](docs/05-development-plan.md)。按依赖安排可独立验收的开发任务及提示词。
6. [验收与验证记录](docs/06-acceptance.md)。定义完成标准及原型实测结果。
7. [实现说明与交付验证](docs/07-implementation-notes.md)。记录本轮 M0–M5 实际落地的结构、命令结果、偏差与未验证项。
8. [拍拍他与下班离场设计](docs/09-design-comfort-and-clock-out.md)。定义3.2秒拍肩回应、2.2秒离场、空工位、跨夜班、关键帧和可执行开发任务，状态为待实施。
9. [国内基金持仓详细设计](docs/10-design-domestic-fund-holdings.md)与[开发交接任务](docs/11-handoff-domestic-fund-implementation.md)。定义场外基金的录入、日终净值、收益、兼容迁移和验收；M7-FUND 已实施，公开基金源仍为开发验证状态。
10. [首页双核心指标设计与开发交接](docs/12-design-home-dual-metrics.md)。定义下班倒计时与今日生存结余的首屏布局、三种显示配置、时间边界和验收；M8-HOME 已实施，双卡、单项显示与本地偏好已有自动化测试和模拟器截图。
11. [PC 伴生端设计方案](docs/13-design-pc-companion.md)。定义 Windows PC 端的竞品参考、固定窗、配置管理、同步路线与技术选型；决策已确认，生产未实施。
12. [PC 伴生端详细产品设计与交互原型](docs/14-design-pc-detailed.md)。定义主窗五页、固定窗 S/M/L、状态矩阵、配置实时预览、文案、数据映射和 PC-D01–D22 验收；状态为设计交付，生产未实施。
13. [PC 伴生端实施交接与素材复用计划](docs/15-handoff-pc-implementation.md)。定义共享 painter/动效抽取、M9-PC0 窗口技术验证清单、任务拆分与风险；素材复用为硬约束。
14. [PC 端开发任务清单](docs/16-pc-development-plan.md)。定义 M9-PC0–PC7 的交付物、验收、依赖与当前状态。
15. [PC0 窗口技术验证报告](docs/17-pc0-spike-report.md)。记录官方 windowing 失败、desktop_multi_window 回退、固定窗 DPI 修复与核心通过结论。
16. [后续 Agent 任务指引](docs/18-next-agent-task-guide.md)。可直接复制的交接提示词，覆盖 PC1 共享层/`.fjob`、PC2 主窗、已知坑与命令。
17. [PC 端开发交接说明](docs/19-pc-handoff.md)。记录 PC0/PC1 已完成状态、架构决策与已知坑。
18. [PC 端走查与修复交接](docs/20-pc-walkthrough-handoff.md)。记录首次运行实测发现的问题与修复（WAL、导入、双引擎）。
19. [PC 固定窗走查与修复记录](docs/21-pc-fixed-window-walkthrough.md)。记录固定窗真机走查、视觉层级、位置记忆与检查更新。
20. [PC 体验打磨走查与修复说明](docs/22-pc-experience-polish-walkthrough.md)。记录配置页表格布局作废、桌面页预览折叠的根因与最小修复，及无界宽度的关键教训。
21. [PC 托盘图标与小窗最小化修复](docs/23-pc-tray-and-card-minimize.md)。记录 PNG 无法作为 Windows 托盘图标、固定窗最小化/恢复路径的根因与实测。
22. [PC 手动配置可用性与手机导出兜底](docs/24-pc-manual-config-and-mobile-export.md)。记录 `isConfigured` 与手机引导解耦、Downloads 免权限导出通道及局域网互传的评估结论。

[打开交互原型](prototype/index.html)。可直接用浏览器打开，首次进入体验引导，进入后底部可重新走流程。`prototype/source.html` 为可编辑源片段，`index.html` 为独立浏览器版本。

[打开 PC 端交互原型](prototype/pc.html)。含主窗、固定窗三档、老板键、金额隐身、点击穿透、配置实时预览和演示状态；推荐 1440×900，可离线打开。

[打开动画原型](prototype/animation.html)，可播放拍肩、下班离场和中途下班，暂停并定位关键帧。源文件、时间轴JSON和13张关键帧的使用方法见[动画交接说明](prototype/ANIMATION-README.md)。

## 机器可读材料

- `contracts/market-gateway.openapi.yaml` 为行情网关接口契约。
- `contracts/widget-snapshot.schema.json` 为 v1 小部件快照格式；`contracts/widget-snapshot-v2.schema.json` 为含 `stockFundDaily` 的 v2 格式，原生同时兼容两者。
- `fixtures/calculation-cases.json` 为跨语言计算验收样例。
- `AGENTS.md` 为开发代理的项目约束与阅读顺序。

## 已确认的产品决策

- 按当月排班工时分摊到手月薪，前台持续计算与滚动显示。
- 首页突出工资、投资当日变化与固定支出组成的今日生存结余。
- A股与按克黄金，黄金使用统一人民币每克参考价估值。A股录入 6 位代码后自动识别市场并获取名称，名称可修改。
- 住房支出可选房贷、房租或暂无。车贷独立配置，固定支出按自然日全天分摊。
- 疲惫小人坐在小办公室，硬币流向房子和车。房子、车与人物统一采用粗线条、扁平奶油色手绘。
- 界面固定浅色纸感，不跟随系统深色，也不提供主题切换。
- 支持 Android 桌面小部件。
- 设置页可从 GitHub Releases 检查更新、下载并校验 APK，再交给 Android 系统安装器；iOS 提示通过 TestFlight 更新。

## 本交付采用的工程默认值

工程默认采用 Flutter + Dart 与 Android 原生 Kotlin 小部件。本地保存个人账本，独立行情网关只处理证券标识、公开价格与交易日历。首版免账号使用。这些是为开工补齐的设计决策，可在建项任务中调整后统一更新文档。

本目录提供需求、设计、契约、原型和开发任务。生产 App、真实行情网关及 GitHub 工作流需按任务实施。原型使用模拟报价和固定演示月份，其简化边界列于验收文档。

## 当前实现状态

已按开发任务落地 M0–M5 及 M7-FUND、M8-HOME 的开发版：`packages/finance_core` 纯 Dart 计算引擎、`apps/mobile` Flutter 应用（六步引导、四个主页面、首页双核心指标、SQLite 本地账本）、场外基金持仓与日终净值、Android Kotlin 小部件、`services/market_gateway` FastAPI 网关。真实行情来源、签名与商店发布仍为外部依赖；iOS 与 AAB 已移出当前范围。

- 工具链与命令：[docs/07-implementation-notes.md](docs/07-implementation-notes.md)、[toolchain.lock.json](toolchain.lock.json)。
- 界面截图：[docs/screenshots](docs/screenshots)。
- 快速验证：`cd packages/finance_core && dart test`、`cd apps/mobile && flutter analyze && flutter test`、`cd services/market_gateway && python -m pytest`。

## 可立即开工与外部依赖

可立即开展项目初始化、领域计算、本地数据、引导、动画和小部件快照开发。发布前需要落实真实行情的访问与展示权限、服务域名、包标识、Android 签名、Apple 开发者账号及 iPhone 真机验证。行情源调研见技术架构第 6 节，公开免密钥访问候选已经列入适配计划。
