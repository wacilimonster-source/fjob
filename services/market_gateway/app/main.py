"""FJOB market gateway: public market data only.

The service never receives salary, quantities, costs or any other ledger value;
only instrument identifiers and query parameters.
"""

from __future__ import annotations

import asyncio
import hashlib
import time
import uuid
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import date, datetime, time as dtime, timedelta, timezone
from decimal import Decimal
from typing import Literal, Optional, Protocol
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

SHANGHAI = ZoneInfo("Asia/Shanghai")
UTC = timezone.utc


# ---------------------------------------------------------------- contracts


class Instrument(BaseModel):
    instrumentId: str
    code: str
    name: str
    market: Literal["SSE", "SZSE", "BSE", "SGE", "CN_FUND"]
    currency: Literal["CNY"] = "CNY"
    unit: Literal["share", "gram", "fundShare"]
    supported: bool = True
    eligibility: Optional[Literal["supported", "unsupported", "unknown"]] = None
    unsupportedReason: Optional[str] = None


class Quote(BaseModel):
    model_config = ConfigDict(extra="forbid")

    instrumentId: str
    priceCny: Decimal
    baselineCny: Optional[Decimal] = None
    quoteAt: datetime
    fetchedAt: datetime
    tradingDate: date
    dayBasis: Literal["exchangeTradingDay", "referenceTradingDay"]
    marketState: Literal["PREOPEN", "OPEN", "BREAK", "CLOSED", "SUSPENDED", "UNKNOWN"]
    quality: Literal["live", "delayed", "eod", "stale", "fixture"]
    source: str
    sourceRevision: int = 0
    sourceLicenseStatus: Literal["verified", "developmentOnly", "unknown"]
    delaySeconds: Optional[int] = None


class FundNav(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["fundNav"] = "fundNav"
    instrumentId: str
    navCny: Optional[Decimal] = None
    navDate: Optional[date] = None
    previousNavCny: Optional[Decimal] = None
    previousNavDate: Optional[date] = None
    actionStatus: Literal["none", "detected", "unknown"]
    fundCalendar: Literal["mainland", "unknown"]
    eligibility: Literal["supported", "unsupported", "unknown"]
    fetchedAt: datetime
    publishedAt: Optional[datetime] = None
    source: str
    sourceRevision: Optional[int] = None
    quality: Literal["live", "delayed", "eod", "stale", "fixture"]
    sourceLicenseStatus: Literal["verified", "developmentOnly", "unknown"]


class ErrorDetail(BaseModel):
    code: Literal[
        "UNKNOWN_SYMBOL",
        "SOURCE_UNAVAILABLE",
        "RATE_LIMITED",
        "ACCESS_DENIED",
        "PARSE_ERROR",
        "MISSING_BASELINE",
        "MISSING_NAV",
        "UNSUPPORTED_INSTRUMENT",
    ]
    message: str
    retryable: bool = False


class QuoteErrorItem(BaseModel):
    instrumentId: str
    error: ErrorDetail


class QuoteBatchRequest(BaseModel):
    # Only public instrument IDs may enter the service. Quantities, costs,
    # salary and other ledger values are rejected rather than ignored.
    model_config = ConfigDict(extra="forbid")

    instrumentIds: list[str] = Field(min_length=1)


class QuoteBatchResponse(BaseModel):
    requestId: str
    serverTime: datetime
    refreshAfterSeconds: int
    items: list[Quote | FundNav | QuoteErrorItem]


class SearchResponse(BaseModel):
    requestId: str
    items: list[Instrument]


class CalendarSession(BaseModel):
    startAt: datetime
    endAt: datetime
    tradingDate: date


class CalendarDay(BaseModel):
    localDate: date
    status: Literal["work", "rest", "open", "closed", "unknown"]
    sessions: list[CalendarSession] = Field(default_factory=list)


class CalendarResponse(BaseModel):
    requestId: str
    version: str
    market: Literal["WORK_CN", "SSE", "SZSE", "BSE", "SGE", "FUND_CN"]
    timezone: str
    coverageFrom: date
    coverageTo: date
    source: str
    days: list[CalendarDay]


# ------------------------------------------------------------------ catalog


CATALOG: list[Instrument] = [
    Instrument(
        instrumentId="CN.SH.600000",
        code="600000",
        name="浦发银行",
        market="SSE",
        unit="share",
    ),
    Instrument(
        instrumentId="CN.SZ.000001",
        code="000001",
        name="平安银行",
        market="SZSE",
        unit="share",
    ),
    Instrument(
        instrumentId="CN.SH.600519",
        code="600519",
        name="贵州茅台",
        market="SSE",
        unit="share",
    ),
    Instrument(
        instrumentId="CN.SZ.300750",
        code="300750",
        name="宁德时代",
        market="SZSE",
        unit="share",
    ),
    Instrument(
        instrumentId="CN.BJ.430047",
        code="430047",
        name="诺思兰德",
        market="BSE",
        unit="share",
    ),
    Instrument(
        instrumentId="GOLD.CNY_GRAM.AU9999",
        code="Au99.99",
        name="上金所 Au99.99 参考价",
        market="SGE",
        unit="gram",
    ),
]

FUND_CATALOG: list[Instrument] = [
    Instrument(
        instrumentId="FUND.CN.000001",
        code="000001",
        name="华夏成长混合",
        market="CN_FUND",
        unit="fundShare",
        eligibility="supported",
    ),
    Instrument(
        instrumentId="FUND.CN.110022",
        code="110022",
        name="易方达消费行业股票",
        market="CN_FUND",
        unit="fundShare",
        eligibility="supported",
    ),
    Instrument(
        instrumentId="FUND.CN.000051",
        code="000051",
        name="华夏沪深300ETF联接A",
        market="CN_FUND",
        unit="fundShare",
        eligibility="supported",
    ),
    Instrument(
        instrumentId="FUND.CN.000198",
        code="000198",
        name="天弘余额宝货币",
        market="CN_FUND",
        unit="fundShare",
        supported=False,
        eligibility="unsupported",
        unsupportedReason="货币基金不使用单位净值",
    ),
    Instrument(
        instrumentId="FUND.CN.510300",
        code="510300",
        name="华泰柏瑞沪深300ETF",
        market="CN_FUND",
        unit="fundShare",
        supported=False,
        eligibility="unknown",
        unsupportedReason="无法确认场外持有口径（可能是场内 ETF）",
    ),
    Instrument(
        instrumentId="FUND.CN.000055",
        code="000055",
        name="华夏优势增长美元份额",
        market="CN_FUND",
        unit="fundShare",
        supported=False,
        eligibility="unsupported",
        unsupportedReason="外币计价份额暂不支持",
    ),
]

CATALOG = [*CATALOG, *FUND_CATALOG]
CATALOG_BY_ID = {item.instrumentId: item for item in CATALOG}

FUND_KNOWN_NAVS: dict[str, tuple[str, str]] = {
    "FUND.CN.000001": ("1.2356", "1.2256"),
    "FUND.CN.110022": ("2.3456", "2.3280"),
    "FUND.CN.000051": ("1.5120", "1.5050"),
}

KNOWN_QUOTES: dict[str, tuple[str, str]] = {
    "CN.SZ.000001": ("12.05", "12.40"),
    "CN.SH.600000": ("9.85", "9.90"),
    "CN.SH.600519": ("1508.00", "1495.00"),
    "CN.SZ.300750": ("182.40", "180.60"),
    "CN.BJ.430047": ("18.60", "18.45"),
    "GOLD.CNY_GRAM.AU9999": ("905.00", "900.00"),
}


# ----------------------------------------------------------------- provider


class ProviderAdapter(Protocol):
    name: str
    license_status: Literal["verified", "developmentOnly", "unknown"]

    async def search(
        self, query: str, limit: int, kind: Optional[str] = None
    ) -> list[Instrument]: ...

    async def fetch_quotes(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, Quote | ErrorDetail]: ...

    async def fetch_fund_navs(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, FundNav | ErrorDetail]: ...

    async def calendar(
        self, market: str, start: date, end: date
    ) -> tuple[str, list[CalendarDay]]: ...

    def health(self) -> dict: ...


def _hash(value: str) -> int:
    return int(hashlib.sha256(value.encode("utf-8")).hexdigest()[:8], 16)


def _previous_weekday(day: date) -> date:
    cursor = day - timedelta(days=1)
    while cursor.weekday() > 4:
        cursor -= timedelta(days=1)
    return cursor


def _trading_day(now: datetime) -> tuple[date, bool]:
    local = now.astimezone(SHANGHAI)
    today = local.date()
    if today.weekday() <= 4:
        return today, True
    return _previous_weekday(today), False


class FixtureProvider:
    """Deterministic development data. Never presented as a live feed."""

    name = "fixture"
    license_status = "developmentOnly"

    async def search(
        self, query: str, limit: int, kind: Optional[str] = None
    ) -> list[Instrument]:
        needle = query.strip().lower()
        matches = [
            item
            for item in CATALOG
            if (kind is None
                or (kind == "fund" and item.market == "CN_FUND")
                or (kind == "stock" and item.market != "CN_FUND"))
            and (needle in item.code.lower() or needle in item.name.lower())
        ]
        return matches[:limit]

    async def fetch_quotes(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, Quote | ErrorDetail]:
        trading_date, is_open = _trading_day(now)
        quote_at = now.replace(second=0, microsecond=0)
        fetched_at = now
        result: dict[str, Quote | ErrorDetail] = {}
        for instrument_id in instrument_ids:
            instrument = CATALOG_BY_ID.get(instrument_id)
            if instrument is None:
                result[instrument_id] = ErrorDetail(
                    code="UNKNOWN_SYMBOL",
                    message="暂不支持该标的",
                )
                continue
            price_text, baseline_text = KNOWN_QUOTES[instrument_id]
            result[instrument_id] = Quote(
                instrumentId=instrument_id,
                priceCny=Decimal(price_text),
                baselineCny=Decimal(baseline_text),
                quoteAt=quote_at,
                fetchedAt=fetched_at,
                tradingDate=trading_date,
                dayBasis=(
                    "referenceTradingDay"
                    if instrument.market == "SGE"
                    else "exchangeTradingDay"
                ),
                marketState="OPEN" if is_open else "CLOSED",
                quality="fixture",
                source="fixture",
                sourceRevision=1,
                sourceLicenseStatus="developmentOnly",
                delaySeconds=0,
            )
        return result

    async def fetch_fund_navs(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, FundNav | ErrorDetail]:
        trading_date, _ = _trading_day(now)
        previous_date = _previous_weekday(trading_date)
        result: dict[str, FundNav | ErrorDetail] = {}
        for instrument_id in instrument_ids:
            instrument = CATALOG_BY_ID.get(instrument_id)
            if instrument is None or instrument.market != "CN_FUND":
                result[instrument_id] = ErrorDetail(
                    code="UNKNOWN_SYMBOL",
                    message="暂不支持该基金",
                )
                continue
            eligibility = instrument.eligibility or "unknown"
            known = FUND_KNOWN_NAVS.get(instrument_id)
            supported = eligibility == "supported" and known is not None
            result[instrument_id] = FundNav(
                instrumentId=instrument_id,
                navCny=Decimal(known[0]) if supported else None,
                navDate=trading_date if supported else None,
                previousNavCny=Decimal(known[1]) if supported else None,
                previousNavDate=previous_date if supported else None,
                # The fixture namespace explicitly models complete interval
                # coverage and no event; real sources must not copy this.
                actionStatus="none" if supported else "unknown",
                fundCalendar="mainland" if supported else "unknown",
                eligibility=eligibility,
                fetchedAt=now,
                publishedAt=None,
                source="fixture",
                sourceRevision=None,
                quality="fixture",
                sourceLicenseStatus="developmentOnly",
            )
        return result

    async def calendar(
        self, market: str, start: date, end: date
    ) -> tuple[str, list[CalendarDay]]:
        days: list[CalendarDay] = []
        cursor = start
        while cursor <= end:
            weekday = cursor.weekday() <= 4
            if market == "WORK_CN":
                days.append(
                    CalendarDay(
                        localDate=cursor,
                        status="work" if weekday else "rest",
                    )
                )
            else:
                sessions: list[CalendarSession] = []
                if weekday:
                    if market == "SGE":
                        windows = [("09:00", "11:30"), ("13:30", "15:30")]
                    else:
                        windows = [("09:30", "11:30"), ("13:00", "15:00")]
                    for start_text, end_text in windows:
                        start_at = datetime.combine(
                            cursor, dtime.fromisoformat(start_text), SHANGHAI
                        ).astimezone(UTC)
                        end_at = datetime.combine(
                            cursor, dtime.fromisoformat(end_text), SHANGHAI
                        ).astimezone(UTC)
                        sessions.append(
                            CalendarSession(
                                startAt=start_at,
                                endAt=end_at,
                                tradingDate=cursor,
                            )
                        )
                days.append(
                    CalendarDay(
                        localDate=cursor,
                        status="open" if weekday else "closed",
                        sessions=sessions,
                    )
                )
            cursor += timedelta(days=1)
        return "FIXTURE@v1", days

    def health(self) -> dict:
        return {"status": "ok", "detail": "fixture provider always available"}


class AksharePublicProvider:
    """Candidate public-source adapter, disabled unless explicitly enabled.

    Access and public-display permissions are not verified; the adapter
    normalises whatever the upstream returns into the gateway contract and
    labels the quality as delayed or eod instead of pretending to be live.
    """

    name = "akshare_public"
    license_status = "unknown"

    def __init__(self) -> None:
        self._enabled = False
        self._reason = "disabled by configuration"

    def enable(self) -> None:
        self._enabled = True
        self._reason = ""

    async def search(
        self, query: str, limit: int, kind: Optional[str] = None
    ) -> list[Instrument]:
        return await FixtureProvider().search(query, limit, kind)

    async def fetch_quotes(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, Quote | ErrorDetail]:
        if not self._enabled:
            return {
                instrument_id: ErrorDetail(
                    code="ACCESS_DENIED",
                    message=f"公开源未启用：{self._reason}",
                    retryable=False,
                )
                for instrument_id in instrument_ids
            }
        try:
            return await asyncio.to_thread(self._fetch_blocking, instrument_ids, now)
        except Exception as error:  # pragma: no cover - depends on upstream
            return {
                instrument_id: ErrorDetail(
                    code="SOURCE_UNAVAILABLE",
                    message=f"公开源不可用：{type(error).__name__}",
                    retryable=True,
                )
                for instrument_id in instrument_ids
            }

    def _fetch_blocking(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, Quote | ErrorDetail]:
        import akshare as ak  # imported lazily; optional dependency

        trading_date, is_open = _trading_day(now)
        frames = {}
        stock_ids = [
            instrument_id
            for instrument_id in instrument_ids
            if not instrument_id.startswith("GOLD.")
        ]
        if stock_ids:
            spot = ak.stock_zh_a_spot_em()
            frames["stocks"] = {
                str(row["代码"]): row for _, row in spot.iterrows()
            }
        gold_frame = None
        if any(instrument_id.startswith("GOLD.") for instrument_id in instrument_ids):
            gold_frame = ak.spot_quotations_sge(symbol="Au99.99")

        result: dict[str, Quote | ErrorDetail] = {}
        for instrument_id in instrument_ids:
            instrument = CATALOG_BY_ID.get(instrument_id)
            if instrument is None:
                result[instrument_id] = ErrorDetail(
                    code="UNKNOWN_SYMBOL", message="暂不支持该标的"
                )
                continue
            try:
                if instrument.market == "SGE":
                    frame = gold_frame
                    price = Decimal(str(frame.iloc[0]["价格"]))
                    baseline = None
                    version = _hash(f"sge:{trading_date.isoformat()}") % 100000
                else:
                    row = frames["stocks"][instrument.code]
                    price = Decimal(str(row["最新价"]))
                    baseline = Decimal(str(row["昨收"]))
                    version = _hash(
                        f"{instrument_id}:{trading_date.isoformat()}"
                    ) % 100000
                result[instrument_id] = Quote(
                    instrumentId=instrument_id,
                    priceCny=price,
                    baselineCny=baseline,
                    quoteAt=now.replace(microsecond=0),
                    fetchedAt=now,
                    tradingDate=trading_date,
                    dayBasis=(
                        "referenceTradingDay"
                        if instrument.market == "SGE"
                        else "exchangeTradingDay"
                    ),
                    marketState="OPEN" if is_open else "CLOSED",
                    quality="delayed",
                    source="akshare_public",
                    sourceRevision=version,
                    sourceLicenseStatus="unknown",
                    delaySeconds=None,
                )
            except Exception:
                result[instrument_id] = ErrorDetail(
                    code="PARSE_ERROR",
                    message="上游字段无法解析",
                    retryable=True,
                )
        return result

    async def fetch_fund_navs(
        self, instrument_ids: list[str], now: datetime
    ) -> dict[str, FundNav | ErrorDetail]:
        # No verified fund adapter exists for this candidate source yet. Report
        # that explicitly instead of reusing stock data as a NAV.
        code = "ACCESS_DENIED" if not self._enabled else "SOURCE_UNAVAILABLE"
        message = (
            f"公开源未启用：{self._reason}"
            if not self._enabled
            else "公开源尚未提供已验证的基金净值适配"
        )
        return {
            instrument_id: ErrorDetail(
                code=code, message=message, retryable=self._enabled
            )
            for instrument_id in instrument_ids
        }

    async def calendar(
        self, market: str, start: date, end: date
    ) -> tuple[str, list[CalendarDay]]:
        return await FixtureProvider().calendar(market, start, end)

    def health(self) -> dict:
        return {
            "status": "ok" if self._enabled else "disabled",
            "detail": self._reason or "candidate public source",
        }


# -------------------------------------------------------------------- cache


@dataclass
class _CacheEntry:
    quote: Quote
    stored_at: float


class QuoteCache:
    def __init__(self, ttl_seconds: float = 15.0, max_entries: int = 512) -> None:
        self.ttl_seconds = ttl_seconds
        self.max_entries = max_entries
        self._entries: dict[str, _CacheEntry] = {}
        self._lock = asyncio.Lock()

    def get(self, instrument_id: str, now: float) -> Optional[Quote]:
        entry = self._entries.get(instrument_id)
        if entry is None:
            return None
        if now - entry.stored_at > self.ttl_seconds:
            return None
        return entry.quote

    def put(self, quote: Quote, now: float) -> None:
        if len(self._entries) >= self.max_entries:
            oldest = min(self._entries.items(), key=lambda item: item[1].stored_at)
            self._entries.pop(oldest[0], None)
        self._entries[quote.instrumentId] = _CacheEntry(quote=quote, stored_at=now)

    async def fetch(
        self,
        provider: ProviderAdapter,
        instrument_ids: list[str],
        now: datetime,
    ) -> dict[str, Quote | ErrorDetail]:
        clock = time.monotonic()
        result: dict[str, Quote | ErrorDetail] = {}
        missing: list[str] = []
        for instrument_id in instrument_ids:
            cached = self.get(instrument_id, clock)
            if cached is not None:
                result[instrument_id] = cached
            else:
                missing.append(instrument_id)
        if not missing:
            return result
        async with self._lock:  # single-flight for the whole batch
            fresh: dict[str, Quote | ErrorDetail] = {}
            try:
                fresh = await asyncio.wait_for(
                    provider.fetch_quotes(missing, now), timeout=5.0
                )
            except asyncio.TimeoutError:
                fresh = {
                    instrument_id: ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message="上游超时",
                        retryable=True,
                    )
                    for instrument_id in missing
                }
            except Exception as error:
                fresh = {
                    instrument_id: ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message=f"上游失败：{type(error).__name__}",
                        retryable=True,
                    )
                    for instrument_id in missing
                }
            for instrument_id in missing:
                value = fresh.get(instrument_id)
                if value is None:
                    result[instrument_id] = ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message="上游没有返回该标的",
                        retryable=True,
                    )
                elif isinstance(value, Quote):
                    self.put(value, time.monotonic())
                    result[instrument_id] = value
                else:
                    result[instrument_id] = value
        return result


@dataclass
class _FundCacheEntry:
    nav: FundNav
    stored_at: float


class FundNavCache:
    """End-of-day NAV cache, kept separate from intraday quote caching.

    The default TTL matches the app's 30-minute low-frequency refresh so a
    burst of foreground launches does not hammer the upstream source.
    """

    def __init__(self, ttl_seconds: float = 1800.0, max_entries: int = 512) -> None:
        self.ttl_seconds = ttl_seconds
        self.max_entries = max_entries
        self._entries: dict[str, _FundCacheEntry] = {}
        self._lock = asyncio.Lock()

    def get(self, instrument_id: str, now: float) -> Optional[FundNav]:
        entry = self._entries.get(instrument_id)
        if entry is None or now - entry.stored_at > self.ttl_seconds:
            return None
        return entry.nav

    def put(self, nav: FundNav, now: float) -> None:
        if len(self._entries) >= self.max_entries:
            oldest = min(self._entries.items(), key=lambda item: item[1].stored_at)
            self._entries.pop(oldest[0], None)
        self._entries[nav.instrumentId] = _FundCacheEntry(nav=nav, stored_at=now)

    async def fetch(
        self,
        provider: ProviderAdapter,
        instrument_ids: list[str],
        now: datetime,
    ) -> dict[str, FundNav | ErrorDetail]:
        clock = time.monotonic()
        result: dict[str, FundNav | ErrorDetail] = {}
        missing: list[str] = []
        for instrument_id in instrument_ids:
            cached = self.get(instrument_id, clock)
            if cached is not None:
                result[instrument_id] = cached
            else:
                missing.append(instrument_id)
        if not missing:
            return result
        async with self._lock:
            fresh: dict[str, FundNav | ErrorDetail] = {}
            try:
                fresh = await asyncio.wait_for(
                    provider.fetch_fund_navs(missing, now), timeout=8.0
                )
            except asyncio.TimeoutError:
                fresh = {
                    instrument_id: ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message="基金净值上游超时",
                        retryable=True,
                    )
                    for instrument_id in missing
                }
            except Exception as error:
                fresh = {
                    instrument_id: ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message=f"基金净值上游失败：{type(error).__name__}",
                        retryable=True,
                    )
                    for instrument_id in missing
                }
            for instrument_id in missing:
                value = fresh.get(instrument_id)
                if value is None:
                    result[instrument_id] = ErrorDetail(
                        code="SOURCE_UNAVAILABLE",
                        message="上游没有返回该基金",
                        retryable=True,
                    )
                elif isinstance(value, FundNav):
                    self.put(value, time.monotonic())
                    result[instrument_id] = value
                else:
                    result[instrument_id] = value
        return result


class RateLimiter:
    def __init__(self, limit: int = 60, window_seconds: float = 60.0) -> None:
        self.limit = limit
        self.window = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str) -> Optional[int]:
        now = time.monotonic()
        hits = self._hits[key]
        while hits and now - hits[0] > self.window:
            hits.popleft()
        if len(hits) >= self.limit:
            retry_after = max(1, int(self.window - (now - hits[0])))
            return retry_after
        hits.append(now)
        return None


# ---------------------------------------------------------------------- app


class Settings:
    def __init__(self) -> None:
        import os

        self.provider_name = os.getenv("FJOB_PROVIDER", "fixture")
        self.enable_public = os.getenv("FJOB_ENABLE_PUBLIC_SOURCE", "false").lower() == "true"
        self.rate_limit = int(os.getenv("FJOB_RATE_LIMIT", "60"))
        self.cache_ttl = float(os.getenv("FJOB_CACHE_TTL_SECONDS", "15"))


def _build_provider(settings: Settings) -> ProviderAdapter:
    if settings.provider_name == "akshare":
        provider = AksharePublicProvider()
        if settings.enable_public:
            provider.enable()
        return provider
    return FixtureProvider()


settings = Settings()
provider = _build_provider(settings)
cache = QuoteCache(ttl_seconds=settings.cache_ttl)
fund_cache = FundNavCache(ttl_seconds=1800.0)
limiter = RateLimiter(limit=settings.rate_limit)

app = FastAPI(title="FJOB Market Gateway", version="1.0.0")


def _request_id() -> str:
    return str(uuid.uuid4())


def _client_key(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _check_rate(request: Request) -> None:
    retry_after = limiter.check(_client_key(request))
    if retry_after is not None:
        raise HTTPException(
            status_code=429,
            detail={
                "requestId": _request_id(),
                "code": "RATE_LIMITED",
                "message": "请求太频繁",
            },
            headers={"Retry-After": str(retry_after)},
        )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    if exc.status_code == 429:
        detail = exc.detail if isinstance(exc.detail, dict) else {
            "requestId": _request_id(),
            "code": "RATE_LIMITED",
            "message": str(exc.detail),
        }
        return JSONResponse(
            status_code=429,
            content=detail,
            headers=exc.headers or {},
        )
    detail = exc.detail if isinstance(exc.detail, dict) else {
        "requestId": _request_id(),
        "code": "BAD_REQUEST",
        "message": str(exc.detail),
    }
    return JSONResponse(status_code=exc.status_code, content=detail)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "provider": provider.name,
        "upstream": provider.health(),
    }


@app.get("/v1/instruments/search", response_model=SearchResponse)
async def search_instruments(
    request: Request,
    q: str = Query(min_length=1, max_length=32),
    limit: int = Query(default=10, ge=1, le=20),
    kind: Optional[Literal["stock", "fund"]] = Query(default=None),
) -> SearchResponse:
    _check_rate(request)
    items = await provider.search(q, limit, kind)
    return SearchResponse(requestId=_request_id(), items=items)


@app.post("/v1/quotes/batch", response_model=QuoteBatchResponse)
async def batch_quotes(request: Request, body: QuoteBatchRequest) -> QuoteBatchResponse:
    _check_rate(request)
    instrument_ids = body.instrumentIds
    if len(instrument_ids) > 30 or len(set(instrument_ids)) != len(instrument_ids):
        raise HTTPException(
            status_code=400,
            detail={
                "requestId": _request_id(),
                "code": "BAD_REQUEST",
                "message": "最多 30 个唯一标的",
            },
        )
    if any(len(instrument_id) > 64 or not instrument_id for instrument_id in instrument_ids):
        raise HTTPException(
            status_code=400,
            detail={
                "requestId": _request_id(),
                "code": "BAD_REQUEST",
                "message": "标的长 ID 不合法",
            },
        )
    now = datetime.now(tz=UTC)
    fund_ids = [
        instrument_id
        for instrument_id in instrument_ids
        if instrument_id.startswith("FUND.CN.")
    ]
    security_ids = [
        instrument_id
        for instrument_id in instrument_ids
        if not instrument_id.startswith("FUND.CN.")
    ]
    resolved: dict[str, Quote | FundNav | ErrorDetail] = {}
    if security_ids:
        resolved.update(await cache.fetch(provider, security_ids, now))
    if fund_ids:
        resolved.update(await fund_cache.fetch(provider, fund_ids, now))
    items: list[Quote | FundNav | QuoteErrorItem] = []
    for instrument_id in instrument_ids:
        value = resolved.get(instrument_id)
        if isinstance(value, (Quote, FundNav)):
            items.append(value)
        else:
            detail = value or ErrorDetail(
                code="SOURCE_UNAVAILABLE", message="无可用报价", retryable=True
            )
            items.append(QuoteErrorItem(instrumentId=instrument_id, error=detail))
    return QuoteBatchResponse(
        requestId=_request_id(),
        serverTime=now,
        refreshAfterSeconds=max(
            15, int(settings.cache_ttl), 1800 if fund_ids else 0
        ),
        items=items,
    )


@app.get("/v1/calendars", response_model=CalendarResponse)
async def get_calendar(
    request: Request,
    market: Literal["WORK_CN", "SSE", "SZSE", "BSE", "SGE", "FUND_CN"] = Query(),
    start: date = Query(alias="from"),
    end: date = Query(alias="to"),
) -> CalendarResponse:
    _check_rate(request)
    if end < start:
        raise HTTPException(
            status_code=400,
            detail={
                "requestId": _request_id(),
                "code": "BAD_REQUEST",
                "message": "结束日期早于开始日期",
            },
        )
    if (end - start).days > 366:
        raise HTTPException(
            status_code=400,
            detail={
                "requestId": _request_id(),
                "code": "BAD_REQUEST",
                "message": "日期范围最多 366 天",
            },
        )
    version, days = await provider.calendar(market, start, end)
    return CalendarResponse(
        requestId=_request_id(),
        version=version,
        market=market,
        timezone="Asia/Shanghai",
        coverageFrom=start,
        coverageTo=end,
        source=provider.name,
        days=days,
    )


@app.get("/v1/provider/status")
async def provider_status() -> dict:
    return {
        "provider": provider.name,
        "licenseStatus": provider.license_status,
        "publicSourceEnabled": settings.enable_public,
        "upstream": provider.health(),
        "cacheTtlSeconds": cache.ttl_seconds,
    }
