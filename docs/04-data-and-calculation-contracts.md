# 数据与计算契约

版本 1 · 2026-11-04。接口与原生桥以本契约为依据。

## 1. 数据类型约定

金额、价格、数量在 JSON 中使用规范十进制字符串。货币 CNY，价格与数量相乘后保留足够精度，最终显示金额使用四舍五入到分。内部推荐 Decimal 或有理数计算，禁止逐 tick 以浮点累加。

月薪、月供、租金最多两位小数。股票价格和每股成本最多三位小数，股数为非负整数。黄金数量三位小数，每克参考价及成本两位小数。乘积和除法保留至少 12位有效小数，汇总前不对分项分别取整。`-0.00` 统一显示 `0.00`。

时间戳使用 RFC3339 UTC，例如 `2026-11-04T06:36:00Z`。业务日期使用 `YYYY-MM-DD` 并附时区标识。生效区间为左闭右开。ID 采用 UUID，revision 为单调递增整型。数据库业务写入需要 expectedRevision。

## 2. 领域实体

| 实体 | 关键字段 | 约束 |
| --- | --- | --- |
| AppSettings | schemaVersion, ledgerRevision, salaryTimezone, theme, motion, tone, widgetPrivacy, onboardingCompletedAt | 时区默认 Asia/Shanghai |
| OnboardingDraft | setupSessionId, draftVersion, step, rawFields, updatedAt | 草稿保留非法原始文本，正式对象通过校验生成 |
| SalaryVersion | id, monthlyNetCny, effectiveFrom, effectiveTo, scheduleVersionId | 不同版本有效期不重叠 |
| ScheduleVersion | timezone, weeklyIntervals, effectiveFrom, effectiveTo, calendarSourceVersion | 区间可跨夜，休息通过区间空集表示 |
| ScheduleOverride | localDate, paidIntervals, reason, confirmed | 覆盖该日期的默认排班 |
| HoldingVersion | id, instrumentId, quantity, costPerUnit, effectiveFrom, effectiveTo | 修改后标记快照重估，不生成隐含交易 |
| HousingVersion | id, mode, effectiveFrom, effectiveTo | mode 为 mortgage/rent/none，同期互斥 |
| MonthlyBill | id, expenseId, month, monthlyAmountCny, principalCny, status, revision | 贷款本金可 null，房租本金为 null |
| Quote | instrumentId, priceCny, baselineCny, quoteAt, fetchedAt, tradingDate, dayBasis, marketState, quality, source | 缺失基准与真实零区分 |
| DashboardSnapshot | computedAt, ledgerRevision, wage, stock, gold, housing, car, principal, interest, rent, total, completeness | 纯计算结果，可重建 |

instrumentId 采用 `CN.SZ.000001`、`CN.SH.600000` 和 `GOLD.CNY_GRAM.AU9999` 等内部规范。供应商代码映射仅在适配器维护。A股市场由目录或明确代码规则校验，避免把代码前导零丢掉。

MonthlyBill.status 为 confirmed、carriedForwardEstimate、missing。未填写下一月时可按用户已接受规则沿用上一月，产生新月份估算记录并标记。没有有效支出配置与缺失账单为两种不同状态。

## 3. 计薪算法 CALC-WAGE

输入为 nowUtc、salaryTimezone、有效工资版本和不可重叠的计薪区间。

对每个工资版本 v，展开该版本引用的排班模板及日期覆盖，跨夜班按自然日和月份边界切开。当前月计薪总秒数为 `D(v,m)`。版本月薪为 `S(v)`，其每秒工资率为 `S(v) / D(v,m)`。

当天工资为所有有效片段 `I` 与 `[当日零点, now)`、对应版本有效期的交集秒数乘每秒工资率之和。午休通过从区间中剔除实现。月累计以月初取代当天零点。

同一月版本不变、全部排班完成时，月累计等于设定月薪。工资或排班月内变更时，每个有效片段采用所属版本的月薪和整月排班分母，界面展示“按分段配置估算”。每个版本保存自己的排班快照，后续模板修改不能静默改变历史版本。

例为 12000 元、21个工作日、每日8小时，分母 604800秒，09:00—12:00、13:00—18:00。当日14:36时完成16560秒，工资为328.571428…元。12:00—13:00期间工资保持不变。

当 `D=0` 且 `S>0` 为无效配置，计算返回 `invalidSchedule`。`S=0` 时工资为0，允许无计薪区间。一天多班次需去重并拒绝重叠，工作日历与市场日历独立。

## 4. 自然日支出算法 CALC-EXPENSE

对每种有效费用版本，在当前自然月的标准整月金额 `B(v,m)`，月天数 `N(m)`，某天 d 的真实长度 `L(d)`，以及版本在当天已经经过的有效秒数 `E(v,d,now)`，分摊为 `B(v,m) / N(m) × E / L`。

全天有效且已结束的一天得到 B/N。整月版本不变时，所有天的全日分摊之和等于 B。Asia/Shanghai 通常一天为86400秒，算法仍按实际时区边界求日长度。

若房贷和房租月内切换，分别对其版本生效时间分摊，任意时刻仅一项住房费用有效。输入金额表示该方案的标准整月对应金额。遇到实际半月合同，应在确认页说明分摊比例，并允许用户在账单说明中记录实际支付额，避免把支付日金额当成每日费用。

2026年11月共30天，住房房贷4800、车贷1800，每日220。当日14:36已过52560秒，当日分摊133.833333…元。

贷款本金分摊使用相同系数乘账单中的本金。利息为月供减本金，再乘系数。房租直接计入 rent，不参与本金与利息。当有效贷款本金未知，该贷款本金/利息为 unknown，汇总显示可知部分及“拆分不完整”。主综合值仍可按已知月供计算。

房贷/房租/暂无选择只决定有效住房方案，切换时旧账单留在历史版本中。车贷独立加入。贷款利率、房价、车价不进入首版综合值。

## 5. 资产盈亏 CALC-ASSET

A股持有盈亏为 `当前有效价 − 用户每股成本` 乘当前数量。今日快照浮动为 `当前有效价 − 当交易日前收参考价` 乘当前数量。报价精度、前收及公司行动处理以同一来源为准。新股或除权日基准缺失时，今日项为 unknown。

A股在统计自然日无交易时，今日项为0，持有盈亏保留最近有效价。正常交易日收盘后保留该交易日今日盈亏，到下一个自然日再由市场日历决定归零或等待当日有效基准。仅靠 device weekday 无法处理法定休市和调休。

黄金持有盈亏为 `人民币每克参考价 − 每克成本` 乘克重。今日参考浮动采用该来源显式返回的同品种交易日参考基准。`dayBasis=referenceTradingDay` 时 UI 显示“参考交易日 YYYY-MM-DD”，夜盘可以与工资自然日不同，主综合值的说明包含这一点。

黄金来源状态 CLOSED 时，若参考交易日早于当前统计日且无有效夜盘会话，今日项为0。存在有效夜盘时按来源交易日口径更新并标交易日。无法判断时今日项为 unknown，禁止把周末证券规则直接套用黄金。

首版持仓编辑采用快照重估，用户数量修改会重算该时点估算值，不还原成交、已实现盈亏和费用。持仓版本记录生效时间，历史查询使用当时版本。

## 6. 综合与完整性 CALC-TOTAL

`total = wage + stockDaily + goldDaily − housingAllocated − carAllocated`。

金融估算金额先汇总高精度数，再取显示精度。分项取整后与合计产生1分差时，说明页展示未取整数与“合计使用完整精度”。本金利息拆分未知只影响拆分完整性；报价或应付金额未知影响 total 的完整性。

`completeness=complete` 表示所有应参与的分项可算。`partial` 表示部分可算，UI 展示已知小计及缺失项目。`unavailable` 表示核心配置无效，主数字使用占位词。零持仓或明确 none 支出视为已知0。

缓存价格可以参与持有估值，但展示 `stale`。当日基准跨交易日失效时该分项今日值设为 unknown。缓存不得伪装实时。用户手动刷新失败时原快照的 computedAt 与 quotesAsOf 分别保留其真实含义。

## 7. 行情网关契约

以 `contracts/market-gateway.openapi.yaml` 为结构定义。

- `GET /v1/instruments/search` 返回明确市场、名称、单位和支持状态。
- `POST /v1/quotes/batch` 返回每标的成功或错误，最多30项。请求不含数量、工资或成本。
- `GET /v1/calendars` 区分 WORK_CN 模板资料与 SSE/SZSE/BSE/SGE 市场会话，返回版本、覆盖时间和实际 UTC 区间。
- 响应包含 `requestId`、服务时间、推荐刷新时间，分项质量和来源元数据。

质量值为 live、delayed、eod、stale、unavailable、fixture。sourceLicenseStatus 为 verified、developmentOnly、unknown。生产配置只允许 verified；fixture 仅用于示例/测试命名空间。

服务不可提供的字段使用 null 和原因。单标的失败用 items[].error，整体请求格式错误为400，超限429，服务故障503。客户端解析失败保持原缓存并显示错误，不将异常值写成0。

客户端按批次序号和 quoteAt 拒绝旧结果覆盖新报价。相同 quoteAt 但源修订变化时采用更高 `sourceRevision`。切换数据源时清除不兼容基准并等待同源组合完整后计算。

## 8. 平台快照契约

`contracts/widget-snapshot.schema.json` 约束一个快照。后台预计算时间线由同结构条目数组构成，外层包含 timelineVersion 和 ledgerRevision，最多289个条目，覆盖时间不超过24小时。每条 computedAt 是展示计算时间，quotesAsOf 保留同一份最后有效行情时间。

原生消费规则如下。

1. schemaVersion 未支持时显示升级或打开 App。
2. 同一账本只接受 ledgerRevision 大于或等于当前版本的条目。
3. tombstone 为 true 时清空内容并显示待配置。
4. privacy 为 true 时金额字段必须为 null，accessibility 文案不得包含金额。
5. 超过 validUntil 仅显示上次更新时间和陈旧状态，不能把旧计算时间改成当前时间。
6. 原生不重新实现领域算法，选择当前时点适用的预计算条目。

深链使用 `fjob://dashboard`、`fjob://expenses/housing`、`fjob://expenses/car` 和 `fjob://widgets`。路由只接受白名单路径，附加参数校验后使用。

## 9. 实现接口建议

```dart
abstract interface class Clock {
  DateTime nowUtc();
}

abstract interface class FinanceCalculator {
  DashboardSnapshot calculate(CalculationInput input);
}

abstract interface class LedgerRepository {
  Future<Ledger> read();
  Future<Ledger> commitSetup(SetupDraft draft, String setupSessionId);
  Future<Ledger> update(LedgerChange change, int expectedRevision);
}

abstract interface class QuoteRepository {
  Stream<QuoteSet> watch(Set<InstrumentId> ids);
  Future<void> refresh(Set<InstrumentId> ids);
}

abstract interface class WidgetBridge {
  Future<void> publish(WidgetTimeline timeline);
  Future<void> clear(int ledgerRevision);
}
```

接口名为建议，行为与数据约束为开发验收依据。`calculate` 对相同输入必须返回相同结果。所有时间计算测试使用固定 Clock，跨平台金额一致性以 fixtures 为准。
