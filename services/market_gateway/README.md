# FJOB Market Gateway

只为客户端提供公开行情、证券目录与交易日历。请求只包含标的 ID，不接收工资、持仓数量、成本、租金或贷款金额。

## 运行

```bash
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8080
```

默认 `FJOB_PROVIDER=fixture`，返回确定性的模拟报价与模拟交易日历，质量标记为 `fixture`，许可状态为 `developmentOnly`。

## 配置

| 环境变量 | 默认 | 说明 |
| --- | --- | --- |
| `FJOB_PROVIDER` | `fixture` | `fixture` 或 `akshare` |
| `FJOB_ENABLE_PUBLIC_SOURCE` | `false` | 是否启用公开候选源，默认关闭 |
| `FJOB_RATE_LIMIT` | `60` | 每客户端每分钟请求上限 |
| `FJOB_CACHE_TTL_SECONDS` | `15` | 共享报价缓存秒数 |

## 已验证

- `pytest`：批报价顺序与十进制字符串、单标的错误、30 条上限、缓存时间戳稳定、日历会话、范围限制、429 `Retry-After`、公开源默认停用。
- 契约结构与 `contracts/market-gateway.openapi.yaml` 对齐。

## 未验证 / 外部依赖

- `AksharePublicProvider` 只是候选适配器，尚未在本环境实测在线调用。公开访问技术条件与面向公众 App 的展示许可都未落实，因此默认停用，启用时报价质量标为 `delayed`、许可标为 `unknown`。
- 生产前必须完成来源访问频率、字段单位、交易日归属与公开展示许可记录，再决定是否启用。
- 交易日历在 fixture 模式只按周末规则，不包含中国法定节假日与调休。
