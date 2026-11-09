# 国内基金持仓 · 开发交接任务

版本 1.0 · 2026-11-09 · 任务 `M7-FUND` · 状态：已实施；验证结果见 [验收与验证记录](06-acceptance.md) 的 M7-FUND 小节。

下面的任务可直接复制给另一个具有本仓库访问权限的开发 agent。完整规则与编号以 [10-design-domestic-fund-holdings.md](10-design-domestic-fund-holdings.md) 为准；用户后续明确要求优先。

## 可复制的开发任务

```text
请在仓库 G:\game\nw\FJOB 实施 M7-FUND 国内基金持仓功能，并完成
开发验证。如果工作区根目录不同，以实际打开的 FJOB 仓库为准。

先读 AGENTS.md、README.md、docs/01-product-requirements.md 至
docs/06-acceptance.md，再读 docs/10-design-domestic-fund-holdings.md、
本交接文档、相关 contracts、fixtures/calculation-cases.json 和
prototype/index.html；随后核对现有实现和工作区状态。保留用户已有改动。

目标：在“资产风浪”按股票相同方式添加、编辑和删除国内普通场外
基金。用户填写 6 位基金代码、持有份额、每份成本；自动查询名称，
无法联网时允许保存待确认。资产页展示已公布单位净值、净值日期、
今日浮动和持有盈亏。首页及 Android 小部件合计纳入基金。

按 docs/10 的范围与口径实施：场外人民币开放式基金；ETF 联接符合
条件时支持，货币基金、场内 ETF、外币份额等本期不按普通基金计算。
不得把累计净值、盘中估值、场内价或万份收益当单位净值。日终净值
没有时间戳时只记录净值日期和真实抓取时间，不伪造报价时间。
上一个净值日的收益不能当成今天收益；日历、基准、基金资格或
分红/拆分情况未知时按设计显示待更新/待确认，而不是置 0。

关键实现要求：
1. 新增 FUND.CN.<代码> 身份和基金类型，份额与成本支持四位小数，
   本地和跨接口使用十进制字符串及项目已有精确计算。股票同码
   不与基金冲突；旧股票和黄金行为不得回归。
2. 日终基金净值与现有股票 Quote 分开表达，使用同源最新/前一净值、
   日期、资格、事件状态、真实抓取时间和可空发布时间。部分基金
   未更新时保留其他已知基金/股票/工资等小计并标不完整。
3. 扩展资产页及首次引导/重走引导，旧草稿默认股票。重走或迁移不
   得将基金转成股票、截断小数或删除原持仓。修改代码涉及旧记录
   关闭和新记录新增时使用原子事务并防止重复。
4. 检查现有数据库当前版本；按设计从 v3 平滑迁移，新增基金净值
   缓存，保留所有原数据。补足迁移、草稿和账本回归测试。
5. 当前默认客户端是东方财富开发直连，也存在 FJOB_MARKET_GATEWAY
   模式。两条路径都按设计接入基金目录、净值和分项错误；同步
   OpenAPI、网关模型、fixture 与测试。行情请求只发送标的 ID，
   不发送数量、成本、工资或其他个人账本数据。
6. 基金按日终数据低频刷新，缓存和失败状态真实；混合请求的一个
   标的失败不能阻止其他标的更新；处理旧请求晚到、来源切换、
   来源修订、限流和分红拆分信息不完整。不要执行上游 JavaScript。
7. 按设计增加 Android 小部件快照 v2，保留并解析 v1；Dart 预计算
   股票+基金金额，Kotlin 只展示。同步 JSON Schema、Kotlin 解析、
   隐私、tombstone、旧快照与乱序/旧任务测试。不实现 iOS。
8. 先同步 docs/01、02、04、05、06 中受本功能影响的口径及
   contracts 和 fixtures，再实现代码。新增 fixture 必须由
   finance_core 实际读取执行；更新现有固定 20 条的数量断言及
   tools/verify_handoff.py 对应计算。不得仅写入未消费的样例。
9. 开发候选数据源只作开发验证，记录在线访问时间、样例、字段、
   缺陷和展示许可状态；许可不明不能标 verified 或用于生产启用。
   绝不把模拟/未知值显示为真实报价。不提交凭据，不自动发版、
   推送、部署或更改与本任务无关的代码。

按 docs/10 的 FND-01～FND-22 实施并核对验收；先运行对应测试，
再按本交接的命令运行必要回归、契约验证和 Android debug APK 构建。
如环境、来源授权或设备不可用，继续完成可独立验证的内容，并在
交付报告中准确列出未完成及未验证项，不得声称已成功。

最终报告包含：任务/需求编号、修改文件、实际命令及结果、截图或
APK 绝对路径、数据迁移和规则偏差、在线来源与授权情况、未执行的
构建/模拟器/真机测试、下一步外部依赖。
```

## 建议实施顺序

1. **契约和样例**：明确日终基金身份、净值/基准、日期、事件和完整性；更新需求、`docs/04-data-and-calculation-contracts.md`、OpenAPI、v2 schema、计算 fixture 与验收编号。
2. **M1 领域**：先在 `packages/finance_core` 实现基金分类、精确持有/今日盈亏、已知小计和日期状态；使旧 fixture 与新增样例都经真实计算器验证。
3. **M2 账本与引导**：扩展草稿和 v4 迁移，确保旧账本、断网保存、重启和重走引导安全；份额、成本与股票身份不混淆。
4. **M5 行情**：增加基金目录与日终净值适配，直连和网关均可按许可状态工作；保留单标的错误、缓存、正确时间和隐私。先用 fixture/HTTP mock，再做少量在线抽样。
5. **M3 页面**：实现资产页、引导、首页及状态说明，核对大字、键盘、小屏和离线；无持仓时保持原有体验。
6. **M4 Android 桥接**：实现 v1/v2 兼容、Dart 快照、Kotlin 解析与 UI；测隐私、旧队列及倒序。同步 Python 和 Kotlin 合同测试。
7. **验证与交付**：运行下方命令，构建 Android debug APK；记录实际结果及外部依赖。每一步都以 `docs/10` 的验收为准，不依赖其他 agent 补做未完成的必需工作。

## 验证命令

以下示例在仓库根目录的 PowerShell 中运行；依据实际环境调整 SDK 路径，但最终报告必须列出**实际**执行的命令与结果。

```powershell
# 先运行与基金相关的定向测试（按最终新增文件名替换示例）
Push-Location packages/finance_core
dart test test/asset_test.dart test/dashboard_test.dart test/calculation_fixture_test.dart
Pop-Location

Push-Location apps/mobile
flutter test test/holding_editor_test.dart test/setup_draft_test.dart test/database_test.dart
flutter test test/eastmoney_client_test.dart test/widget_snapshot_test.dart
Pop-Location

# 回归和契约验证
Push-Location packages/finance_core
dart test
Pop-Location

Push-Location apps/mobile
flutter analyze
flutter test
flutter test tool/dump_widget_timeline_test.dart
Pop-Location

Push-Location apps/mobile/android
.\gradlew.bat testDebugUnitTest
Pop-Location

Push-Location services/market_gateway
python -m pytest -q
Pop-Location

python tools/verify_handoff.py
python tools/check_widget_payloads.py

# 根据实际的开发候选源开关填写 --dart-define；不得将未授权源启用到生产
Push-Location apps/mobile
flutter build apk --debug
Pop-Location
```

可选的来源只读抽样（使用公开示例代码，不输入个人持仓），记录结果时注明当地时间与来源许可仍未验证：

```powershell
$fundExampleHeaders = @{
    'User-Agent' = 'FJOB/1.0'
    'Referer' = 'https://fundf10.eastmoney.com/jjjz_000001.html'
}
$fundExampleUri = 'https://api.fund.eastmoney.com/f10/lsjz?fundCode=000001&pageIndex=1&pageSize=2'
$fundExampleResponse = Invoke-RestMethod -Uri $fundExampleUri -Headers $fundExampleHeaders
$fundExampleResponse.Data.LSJZList | Select-Object FSRQ, DWJZ, FHSP
```

该抽样仅检查接口与个别字段在当时可访问；分红/拆分覆盖、基金类型、币种、休市规则、长期稳定性及公开展示许可都需要分别验证。若来源要求授权或拒绝访问，不得绕过限制。

本地 debug APK 通常位于 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。只有命令成功且文件实际存在时才能报告产物。若使用模拟器验证，应选择隔离测试设备；不要为了覆盖签名不同的既有安装而删除用户账本。模拟器和真机未使用时分别标记未验证。

建议在实现报告中逐项填写：

| 项目 | 记录 |
| --- | --- |
| 任务和验收 | M7-FUND；ASSET-01-FUND；FND-01～22 的执行结果 |
| 代码与契约 | 实际修改文件、schema/数据库版本、迁移和回滚注意事项 |
| 测试与构建 | 每条实际命令、退出结果、失败原因、APK 与截图绝对路径 |
| 行情来源 | 测试日期、代码、可用字段/失败、来源与许可状态；数据仅验证不能代表生产授权 |
| 环境限制 | 未执行的构建、在线测试、模拟器、Android 真机测试和未关闭的外部依赖 |
