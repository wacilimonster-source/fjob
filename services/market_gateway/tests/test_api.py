from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from app import main


@pytest.fixture()
def client():
    main.cache = main.QuoteCache(ttl_seconds=15.0)
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


def test_public_source_is_disabled_by_default(client):
    body = client.get("/v1/provider/status").json()
    assert body["provider"] == "fixture"
    assert body["publicSourceEnabled"] is False
    assert body["licenseStatus"] == "developmentOnly"
