# 实现说明与交付验证（M0–M5 开发版）

版本 0.1 · 2026-11-04 · 对应交付包 docs/01–06 与 contracts。

本文件记录本轮实际落地的工程结构、工具链、已执行命令、与交付文档的偏差以及尚未验证项。业务口径未做改写；所有计算以 `docs/04-data-and-calculation-contracts.md` 和 `fixtures/calculation-cases.json` 为准。

## 1. 已交付内容

| 任务 | 状态 | 主要产物 |
| --- | --- | --- |
| M0 建项 | 完成（Android 实构建） | `apps/mobile`、`packages/finance_core`、`toolchain.lock.json`、CI 工作流、`build/app/outputs/flutter-apk/app-debug.apk` |
| M1 领域引擎 | 完成 | `packages/finance_core`，20 条 fixture + 55 条边界回归全部通过 |
| M2 本地账本与引导 | 完成 | SQLite v1、草稿恢复、幂等提交、事务失败保留草稿、V0 迁移、六步引导 |
| M3 主页面与动画 | 完成（开发版） | 四页、设置、手绘办公室/房子/车、硬币与天气状态、减少动效、暗色 |
| M4 小部件 | Android 完成；iOS 源码就绪 | Kotlin 解析器/RemoteViews/WorkManager + 11 项 JVM 测试；Swift/WidgetKit 源码、App Group、深链；iOS target 待 macOS CI 接线 |
| M5 行情 | 契约级完成 | FastAPI 网关、fixture 适配器、默认停用的公开候选适配器、缓存/single-flight/限速/429、11 项 pytest |
| M6 发布 | 模板就绪 | 签名配置读取 `key.properties`、Android/iOS release 工作流；签名与商店上传未执行 |

## 2. 工程结构

```text
apps/mobile/
  lib/app/                 启动、主题、Riverpod 装配、深链
  lib/data/                SQLite、账本仓库、行情客户端、小部件快照与桥
  lib/domain/              设置/账本聚合、引导草稿与校验、示例账本、格式化
  lib/features/onboarding/ 六步引导、草稿控制器
  lib/features/dashboard/  求生现场、办公室场景绘制
  lib/features/assets/     A股与黄金持仓
  lib/features/expenses/   住房三选一与独立车贷
  lib/features/widgets/    小部件预览、隐私、手动刷新
  lib/features/settings/   主题、动效、语气、数据管理、来源说明
  lib/features/shell/      四个底部标签
  android/                 Kotlin 小部件、桥接、WorkManager、布局与单测
  ios/                     WidgetBridge、共享快照模型、WidgetExtension 源码
packages/finance_core/     纯 Dart 领域与计算（无 Flutter 依赖）
services/market_gateway/   FastAPI 行情网关与测试
tools/                     契约校验与会话交付脚本
```

## 3. 工具链与实际构建

详见根目录 `toolchain.lock.json`。实际验证过的组合：

- Flutter 3.47.9 stable（revision `c197ca5199`），Dart 3.13.7。
- Temurin JDK 17.0.20.1，Gradle 9.3.1，AGP 9.1.0，Kotlin 2.4.0。
- Android SDK：compileSdk/targetSdk 36，minSdk 26，build-tools 36.0.0；WorkManager 2.10.1。
- Python 3.12.10，FastAPI 0.138.0，httpx 0.28.1，pytest 9.2.0。

## 4. 实际执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `cd packages/finance_core && dart test` | 75 项通过（含 `fixtures/calculation-cases.json` 20 条） |
| `cd apps/mobile && flutter analyze` | No issues found |
| `cd apps/mobile && flutter test` | 28 项通过（DB 迁移/幂等/修订、草稿、快照 schema、端到端引导） |
| `cd apps/mobile/android && gradlew.bat testDebugUnitTest` | 11 项通过（JSON 解析、隐私反例、时间线选择、乱序修订） |
| `cd apps/mobile && flutter build apk --debug` | 成功，产物 `build/app/outputs/flutter-apk/app-debug.apk` |
| `cd services/market_gateway && python -m pytest -q` | 11 项通过 |
| `python tools/verify_handoff.py` | PASS 20 calculations / OpenAPI / widget schema / privacy / links |
| `python tools/check_widget_payloads.py` | 8 个引擎生成的快照条目通过真实 JSON Schema 校验 |
| `flutter test tool/generate_office_art_test.dart` | 生成 Android 大号小部件静态场景 `res/drawable-nodpi/office_static.png` |
| `flutter test tool/capture_screens_test.dart` | 生成 `apps/mobile/build/screenshots/` 五张界面截图 |
| `adb install` + `am start` + `input` 流程 | 在 1080×1920 Android 模拟器（Android 16, 暗色）安装并启动成功；完成工资→排班→资产→住房→核对→提交；强杀重启后草稿恢复到上次步骤与输入 |
| `adb shell run-as ... cat shared_prefs/fjob_widget_snapshot.xml` | 提交后原生收到 `payload_kind=timeline`、`ledgerRevision=1` 的时间线，证明 MethodChannel→Kotlin→SharedPreferences 链路可用 |
| GitHub Actions `ci` | 5/5 jobs 成功（finance_core、Flutter analyze/test、Android debug + Kotlin、gateway、iOS simulator），run `41832316918` |
| GitHub Actions `android-release` | 按设计在缺少 `ANDROID_KEYSTORE_BASE64` 时失败；v0.1.0 产物由本地发布密钥签名并上传到 GitHub Release |

截图同时复制到 `docs/screenshots/`：

- 引擎截图（固定示例时钟、390×844 逻辑尺寸）：`01-dashboard-demo.png`、`02-assets-demo.png`、`03-expenses-demo.png`、`04-widgets-demo.png`、`05-onboarding-welcome.png`。
- 真机（模拟器）暗色截图：`android-welcome.png`、`android-schedule.png`、`android-review.png`、`android-dashboard.png`。

模拟器流程中修正的问题：负号字符在部分字体缺失会导致金额符号消失（改为 ASCII `-`）、星期选择被拉成整行、进入新步骤时提前显示字段错误、内容与状态栏重叠、FilledButton 自定义文字样式丢失中文字体。

## 5. 关键实现决策与偏差

1. **SQLite 访问方式**：文档默认选型为 Drift；本轮使用 `sqflite`（移动端）+ `sqflite_common_ffi`（测试）并手写 SQL/迁移。行为契约不变：UTC 时间戳、业务日期独立列、十进制字符串、`expectedRevision` 校验、单事务提交。选择理由是本环境可实际构建与测试，避免代码生成环节的不确定依赖。
2. **路由与 HTTP**：未引入 go_router 与 Dio，使用自有的四标签外壳 + 深链解析、`package:http` 行情客户端。深链白名单与路由行为按契约实现。
3. **十进制**：未使用 `decimal` 包，改为自实现的有理数 `Rational`（BigInt 分子/分母，HALF_UP 显示取整）。20 条 fixture 全部逐位一致，且避免任何浮点累加。
4. **行情**：默认启用确定性的 fixture 适配器，界面、快照与设置页均标注“模拟行情/模拟数据”。网关客户端与 FastAPI 服务已实现，但真实来源与展示许可未落实，因此生产配置保持关闭。公开候选 `akshare_public` 默认停用，启用时质量标为 `delayed`、许可标为 `unknown`。
5. **交易日历**：fixture 仅按周末规则，不含中国法定节假日与调休；市场日历与工资日历独立，未知日期返回 unknown 而不是猜测。
6. **示例模式**：使用内存账本 + 固定时钟 2026-11-04 14:36（Asia/Shanghai），完全绕过真实数据库与发布流程；退出后回到原账本或未完成引导。
7. **小部件时间线**：每 5 分钟一条、覆盖 24 小时、最多 289 条；原生只选择当前时点之前最近的一条，金额、隐私与 tombstone 全部来自 Dart 预计算。Android 周期性刷新 30 分钟。
8. **iOS**：Runner 已接入 `fjob://` scheme、`WidgetBridge` 与 App Group entitlement；WidgetKit 扩展源码、Info.plist、entitlements 与接线说明就绪。扩展 target 仍需在 macOS/Xcode 中创建，未在本环境编译。
9. **M6 签名**：`android/app/build.gradle.kts` 在存在 `key.properties` 时读取 release 签名，否则退回 debug 签名以保证本地可构建；发布工作流在缺少 Secret 时显式失败。

## 6. 规则偏差与已知限制

- 中国法定节假日与调休数据未内置；fixture 日历只按周末。真实日历需通过网关 `WORK_CN`/`SSE`/`SZSE`/`BSE`/`SGE` 接入并有版本记录。
- 行情来源仍是 fixture；没有任何“实时”伪装。`AD-API-04`（生产来源许可）未关闭。
- 工资版本只支持单次排班模板；节假日导入的版本预览尚未实现。
- 编辑持仓只做快照重估，不还原当日成交、已实现盈亏与费用（与首版契约一致）。
- 备份策略：Android `allowBackup=false`，未实现导出/导入。
- 小部件只实现主页三档密度，锁屏等更小表面未实现。
- 示例模式为单一固定场景，不支持多套示例账本。

## 7. 未验证项（明确状态）

| 项目 | 状态 |
| --- | --- |
| iOS Runner 编译 | 已通过：GitHub Actions macOS runner `flutter build ios --simulator --no-codesign` 成功 |
| iOS Widget 扩展编译 | 未验证：扩展 target 仍需在 Xcode 中创建并接入 App Group/签名，尚未嵌入 IPA |
| iPhone 真机 / TestFlight | 未验证：依赖 Apple 账号、证书、profile |
| Android release 签名 AAB/APK | 未验证：依赖 keystore Secrets |
| Android 真机/模拟器小部件放置与系统调度 | 未验证：已在模拟器完成提交流程并确认原生快照写入，但未把小组件添加到桌面观察 RemoteViews 与 30 分钟刷新 |
| Android 暗色/字体回退 | 已做暗色真机检查；系统字体 200% 与 320dp 仍未逐页截图 |
| 真实行情在线调用与展示许可 | 未验证：公开候选仅按文档形态实现，未在线调用 |
| GitHub Actions 工作流 | 已执行：`ci` 5/5 成功；`android-release` 因未配置签名 Secrets 失败（预期） |
| 320dp / 系统字体 200% / 暗色全套截图回归 | 部分验证：截图在 390×844 逻辑尺寸；320dp 与 200% 尚未逐页截图 |

## 8. 下一任务可用接口

- `finance_core` 的 `DashboardCalculator.calculate(CalculationInput)` 是唯一计算入口；新增页面应消费 `DashboardSnapshot`，不重复实现算法。
- `LedgerRepository` 提供带 `expectedRevision` 的写入、`setupSessionId` 幂等提交、草稿与快照任务队列。
- `WidgetSnapshotBuilder` 生成契约快照；新增平台只需消费 `timeline.entries`。
- `ProviderAdapter`（Python）定义 `search`、`fetch_quotes`、`calendar`、`health`，接入有许可来源时实现该协议并配置 `FJOB_PROVIDER`。

## 9. 回滚

- 本地数据：设置页“清空本地账本”会删除配置、草稿、行情缓存并写入 tombstone 快照；原生端拒绝更低 `ledgerRevision`。
- 版本迁移：v1 之外的迁移尚未存在；打开更高 schemaVersion 的数据库会由 sqflite 的版本检查拒绝，需要先升级 App。
- 发布回滚：Android 使用上一版 AAB；iOS 在 App Store Connect 回退 TestFlight 构建。

## 10. v0.1.0 发布记录

- Tag：`v0.1.0`；GitHub Release 附件：`fjob-0.1.0-universal.apk`、`fjob-0.1.0.aab`、`SHA256SUMS.txt`。
- 发布签名：本地 `.release/fjob-release.jks`（PKCS12，RSA 4096，10,000 天），证书 SHA-256 `4ccda311…0b7b`；密钥与密码不进入仓库。
- 发布版修复：R8 移除 `androidx.work.impl.WorkDatabase_Impl` 构造器导致启动崩溃，新增 `apps/mobile/android/app/proguard-rules.pro` 保留 Room/WorkManager/Startup 反射入口，并在签名包上复测通过。
- CI 修复：提交 Gradle wrapper、为 Linux job 写入 `local.properties` 并先执行 `flutter pub get`；Runner target 加入共享 `WidgetSnapshot.swift`，macOS 模拟器编译通过。
- Release：<https://github.com/wacilimonster-source/fjob/releases/tag/v0.1.0>（prerelease）。
- 校验和与安装说明见 `docs/releases/v0.1.0.md`。
