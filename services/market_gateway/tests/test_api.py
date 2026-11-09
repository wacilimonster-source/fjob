from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from app import main


@pytest.fixture()
def client():
    main.cache = main.QuoteCache(ttl_seconds=15.0)
    main.fund_cache = main.FundNavCache(ttl_seconds=1800.0)
    main.limiter = main.RateLimiter(limit=60)
    with TestClient(main.app) as test_client:
        yield test_client


def test_health_separates_process_and_upstream(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["provider"] == "fixture"
    assert body["upstream"]["status"] == "ok"


def test_search_returns_supported_instruments(client):
    response = client.get("/v1/instruments/search", params={"q": "600", "limit": 5})
    assert response.status_code == 200
    body = response.json()
    assert body["requestId"]
    codes = {item["code"] for item in body["items"]}
    assert "600000" in codes
    for item in body["items"]:
        assert item["currency"] == "CNY"
        assert item["supported"] is True


def test_batch_quotes_keep_request_order_and_decimal_strings(client):
    ids = ["CN.SZ.000001", "GOLD.CNY_GRAM.AU9999"]
    response = client.post("/v1/quotes/batch", json={"instrumentIds": ids})
    assert response.status_code == 200
    body = response.json()
    assert body["refreshAfterSeconds"] >= 5
    assert [item["instrumentId"] for item in body["items"]] == ids
    stock, gold = body["items"]
    assert stock["priceCny"] == "12.05"
    assert stock["baselineCny"] == "12.40"
    assert stock["dayBasis"] == "exchangeTradingDay"
    assert stock["quality"] == "fixture"
    assert stock["sourceLicenseStatus"] == "developmentOnly"
    assert gold["dayBasis"] == "referenceTradingDay"
    assert gold["priceCny"] == "905.00"


def test_unknown_symbol_is_a_per_item_error(client):
    response = client.post(
        "/v1/quotes/batch",
        json={"instrumentIds": ["CN.SZ.000001", "CN.SZ.999999"]},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items[0]["instrumentId"] == "CN.SZ.000001"
    assert items[1]["error"]["code"] == "UNKNOWN_SYMBOL"
    assert items[1]["error"]["retryable"] is False


def test_batch_rejects_too_many_or_duplicate_ids(client):
    too_many = [f"CN.SZ.{index:06d}" for index in range(31)]
    response = client.post("/v1/quotes/batch", json={"instrumentIds": too_many})
    assert response.status_code == 400
    response = client.post(
        "/v1/quotes/batch",
        json={"instrumentIds": ["CN.SZ.000001", "CN.SZ.000001"]},
    )
    assert response.status_code == 400


def test_empty_batch_is_rejected(client):
    response = client.post("/v1/quotes/batch", json={"instrumentIds": []})
    assert response.status_code == 422


def test_cached_quote_keeps_its_original_timestamp(client):
    payload = {"instrumentIds": ["CN.SZ.000001"]}
    first = client.post("/v1/quotes/batch", json=payload).json()["items"][0]
    second = client.post("/v1/quotes/batch", json=payload).json()["items"][0]
    assert first["quoteAt"] == second["quoteAt"]
    assert first["sourceRevision"] == second["sourceRevision"]


def test_calendar_exposes_sessions_and_status(client):
    start = date(2026, 11, 2)
    end = date(2026, 11, 8)
    response = client.get(
        "/v1/calendars",
        params={"market": "SSE", "from": start.isoformat(), "to": end.isoformat()},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["market"] == "SSE"
    assert body["timezone"] == "Asia/Shanghai"
    assert len(body["days"]) == 7
    open_days = [day for day in body["days"] if day["status"] == "open"]
    closed_days = [day for day in body["days"] if day["status"] == "closed"]
    assert open_days and closed_days
    assert open_days[0]["sessions"][0]["tradingDate"] == open_days[0]["localDate"]
    assert closed_days[0]["sessions"] == []

    work = client.get(
        "/v1/calendars",
        params={
            "market": "WORK_CN",
            "from": start.isoformat(),
            "to": end.isoformat(),
        },
    )
    assert work.status_code == 200
    assert {day["status"] for day in work.json()["days"]} == {"work", "rest"}


def test_calendar_range_is_limited(client):
    start = date(2025, 1, 1)
    end = start + timedelta(days=400)
    response = client.get(
        "/v1/calendars",
        params={"market": "SSE", "from": start.isoformat(), "to": end.isoformat()},
    )
    assert response.status_code == 400


def test_rate_limit_returns_retry_after(client):
    main.limiter = main.RateLimiter(limit=1)
    assert client.get("/v1/instruments/search", params={"q": "600"}).status_code == 200
    limited = client.get("/v1/instruments/search", params={"q": "600"})
    assert limited.status_code == 429
    assert int(limited.headers["Retry-After"]) >= 1
    assert limited.json()["code"] == "RATE_LIMITED"


def test_fund_search_separates_same_code_stock_and_fund(client):
    fund = client.get(
        "/v1/instruments/search",
        params={"q": "000001", "kind": "fund"},
    ).json()["items"]
    assert [item["instrumentId"] for item in fund] == ["FUND.CN.000001"]
    assert fund[0]["market"] == "CN_FUND"
    assert fund[0]["unit"] == "fundShare"
    assert fund[0]["eligibility"] == "supported"
    assert fund[0]["code"] == "000001"

    stock = client.get(
        "/v1/instruments/search",
        params={"q": "000001", "kind": "stock"},
    ).json()["items"]
    assert [item["instrumentId"] for item in stock] == ["CN.SZ.000001"]
    assert stock[0]["market"] == "SZSE"


def test_fund_search_reports_confirmed_rejection_vs_unknown(client):
    money_fund = client.get(
        "/v1/instruments/search",
        params={"q": "000198", "kind": "fund"},
    ).json()["items"][0]
    assert money_fund["eligibility"] == "unsupported"
    assert money_fund["supported"] is False
    assert money_fund["unsupportedReason"]

    etf = client.get(
        "/v1/instruments/search",
        params={"q": "510300", "kind": "fund"},
    ).json()["items"][0]
    assert etf["eligibility"] == "unknown"
    assert etf["eligibility"] != "unsupported"


def test_batch_mixes_stock_quote_and_fund_nav(client):
    ids = ["CN.SZ.000001", "FUND.CN.000001", "FUND.CN.000198"]
    response = client.post("/v1/quotes/batch", json={"instrumentIds": ids})
    assert response.status_code == 200
    body = response.json()
    assert body["refreshAfterSeconds"] >= 1800
    assert [item["instrumentId"] for item in body["items"]] == ids
    stock, fund, unsupported = body["items"]
    assert "quoteAt" in stock and "navDate" not in stock
    assert fund["kind"] == "fundNav"
    assert "quoteAt" not in fund
    assert fund["navCny"] == "1.2356"
    assert fund["previousNavCny"] == "1.2256"
    assert fund["navDate"] >= fund["previousNavDate"]
    assert fund["actionStatus"] == "none"
    assert fund["fundCalendar"] == "mainland"
    assert fund["eligibility"] == "supported"
    assert fund["publishedAt"] is None
    assert fund["sourceRevision"] is None
    assert unsupported["kind"] == "fundNav"
    assert unsupported["navCny"] is None
    assert unsupported["navDate"] is None
    assert unsupported["eligibility"] == "unsupported"


def test_fund_nav_cache_keeps_the_real_fetch_time(client):
    payload = {"instrumentIds": ["FUND.CN.000001"]}
    first = client.post("/v1/quotes/batch", json=payload).json()["items"][0]
    second = client.post("/v1/quotes/batch", json=payload).json()["items"][0]
    assert first["fetchedAt"] == second["fetchedAt"]
    assert first["navDate"] == second["navDate"]
    assert first["publishedAt"] is None


def test_partial_fund_failure_does_not_block_other_items(client):
    response = client.post(
        "/v1/quotes/batch",
        json={"instrumentIds": ["CN.SZ.000001", "FUND.CN.999999"]},
    )
    assert response.status_code == 200
    items = response.json()["items"]
    assert items[0]["priceCny"] == "12.05"
    assert items[1]["error"]["code"] == "UNKNOWN_SYMBOL"


def test_batch_rejects_personal_ledger_fields(client):
    response = client.post(
        "/v1/quotes/batch",
        json={
            "instrumentIds": ["FUND.CN.000001"],
            "quantity": "1000.25",
            "costPerUnit": "1.2000",
            "salary": "12000",
        },
    )
    assert response.status_code == 422


def test_fund_calendar_is_available(client):
    response = client.get(
        "/v1/calendars",
        params={
            "market": "FUND_CN",
            "from": "2026-11-02",
            "to": "2026-11-08",
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["market"] == "FUND_CN"
    assert {day["status"] for day in body["days"]} == {"open", "closed"}


def test_public_source_is_disabled_by_default(client):
    body = client.get("/v1/provider/status").json()
    assert body["provider"] == "fixture"
    assert body["publicSourceEnabled"] is False
    assert body["licenseStatus"] == "developmentOnly"
