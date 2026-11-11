/// Market data clients: deterministic fixture quotes and the gateway adapter.
library;

import 'dart:async';
import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;
import 'package:ledger_model/ledger_model.dart';

abstract final class AppConfig {
  static const String appName = '今日又白干';
  static const String channelName = 'cn.fjob.todayagain/widgets';

  /// Empty until the verified gateway host is configured for a release build.
  static const String gatewayBaseUrl =
      String.fromEnvironment('FJOB_MARKET_GATEWAY', defaultValue: '');

  static const Duration refreshInterval = Duration(seconds: 15);
  static const Duration quoteStaleAfter = Duration(minutes: 5);
  static const Duration fundRefreshInterval = Duration(minutes: 30);
  static const String goldInstrumentName = '上金所 Au99.99 参考价';

  /// The direct public fund source is a development-verification candidate.
  /// Release builds keep it disabled until source access and public-display
  /// licensing are recorded; pass the define explicitly for a dev APK.
  static const bool fundPublicSourceEnabled = bool.fromEnvironment(
    'FJOB_ENABLE_FUND_PUBLIC_SOURCE',
  );
}

final class FundNavBatch {
  const FundNavBatch({
    required this.navs,
    required this.errors,
    required this.serverTime,
    required this.refreshAfterSeconds,
  });

  final Map<String, FundNavSnapshot> navs;
  final Map<String, String> errors;
  final DateTime serverTime;
  final int refreshAfterSeconds;
}

final class QuoteBatch {
  const QuoteBatch({
    required this.quotes,
    required this.errors,
    required this.serverTime,
    required this.refreshAfterSeconds,
  });

  final Map<String, Quote> quotes;
  final Map<String, String> errors;
  final DateTime serverTime;
  final int refreshAfterSeconds;
}

abstract interface class MarketClient {
  String get sourceLabel;

  bool get isFixture;

  /// Looks up instruments by code fragment or name for the holding editor.
  Future<List<InstrumentInfo>> searchInstruments(String query);

  /// Fund directory lookup by six-digit code. `null` means the code is not in
  /// the directory at all; a non-null result may still be unsupported/unknown.
  Future<FundInfo?> fetchFundInfo(String code);

  Future<QuoteBatch> fetchQuotes(List<String> instrumentIds,
      {DateTime? nowUtc});

  /// Date-only fund NAVs. Requests carry only instrument IDs.
  Future<FundNavBatch> fetchFundNavs(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  });

  Future<MarketCalendar> fetchCalendar({
    required String market,
    required LocalDate from,
    required LocalDate to,
  });
}

/// Deterministic simulated quotes, clearly labelled everywhere in the UI.
///
/// It never invents a fresh random walk per frame: prices depend only on the
/// instrument and the trading date, so ticking the dashboard cannot change the
/// quote. The production build must replace this with the gateway client.
final class FixtureMarketClient implements MarketClient {
  FixtureMarketClient(this.calendar);

  final BusinessCalendar calendar;

  static const Map<String, (double, double)> _knownQuotes = {
    'CN.SZ.000001': (12.05, 12.40),
    'CN.SH.600000': (9.85, 9.90),
    'CN.SH.600519': (1508.00, 1495.00),
    'CN.SZ.300750': (182.40, 180.60),
    'CN.SZ.000858': (121.30, 122.10),
    'CN.BJ.430047': (18.60, 18.45),
  };

  static const Map<String, (String, String, FundEligibility, String)>
      _fundCatalog = {
    '000001': ('华夏成长混合', '混合型', FundEligibility.supported, ''),
    '110022': ('易方达消费行业股票', '股票型', FundEligibility.supported, ''),
    '000051': ('华夏沪深300ETF联接A', '指数型-股票', FundEligibility.supported, ''),
    '000198': (
      '天弘余额宝货币',
      '货币型',
      FundEligibility.unsupported,
      '货币基金不使用单位净值',
    ),
    '510300': (
      '华泰柏瑞沪深300ETF',
      '指数型-股票',
      FundEligibility.unknown,
      '无法确认场外持有口径（可能是场内 ETF）',
    ),
    '000055': (
      '华夏优势增长美元份额',
      '混合型',
      FundEligibility.unsupported,
      '外币计价份额暂不支持',
    ),
  };

  static const Map<String, (String, StockMarket)> _instrumentCatalog = {
    '000001': ('平安银行', StockMarket.szse),
    '000333': ('美的集团', StockMarket.szse),
    '000651': ('格力电器', StockMarket.szse),
    '000858': ('五粮液', StockMarket.szse),
    '002415': ('海康威视', StockMarket.szse),
    '002594': ('比亚迪', StockMarket.szse),
    '300059': ('东方财富', StockMarket.szse),
    '300750': ('宁德时代', StockMarket.szse),
    '600000': ('浦发银行', StockMarket.sse),
    '600036': ('招商银行', StockMarket.sse),
    '600276': ('恒瑞医药', StockMarket.sse),
    '600519': ('贵州茅台', StockMarket.sse),
    '601012': ('隆基绿能', StockMarket.sse),
    '601318': ('中国平安', StockMarket.sse),
    '601888': ('中国中免', StockMarket.sse),
    '601899': ('紫金矿业', StockMarket.sse),
    '688981': ('中芯国际', StockMarket.sse),
    '430047': ('诺思兰德', StockMarket.bse),
    '920002': ('万达轴承', StockMarket.bse),
  };

  @override
  String get sourceLabel => '模拟行情';

  @override
  bool get isFixture => true;

  @override
  Future<List<InstrumentInfo>> searchInstruments(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const <InstrumentInfo>[];
    final inferred = marketForCode(text);
    final known = _instrumentCatalog[text];
    if (known != null && inferred != null) {
      return <InstrumentInfo>[
        InstrumentInfo(
          instrumentId: instrumentIdFor(text, inferred),
          code: text,
          name: known.$1,
          market: inferred,
        ),
      ];
    }
    if (text.length == 6 && inferred != null) {
      return <InstrumentInfo>[
        InstrumentInfo(
          instrumentId: instrumentIdFor(text, inferred),
          code: text,
          name: '',
          market: inferred,
          supported: false,
        ),
      ];
    }
    return <InstrumentInfo>[
      for (final entry in _instrumentCatalog.entries)
        if (entry.value.$1.contains(text))
          InstrumentInfo(
            instrumentId: instrumentIdFor(entry.key, entry.value.$2),
            code: entry.key,
            name: entry.value.$1,
            market: entry.value.$2,
          ),
    ];
  }

  @override
  Future<FundInfo?> fetchFundInfo(String code) async {
    final known = _fundCatalog[code];
    if (known == null) {
      if (!RegExp(r'^\d{6}$').hasMatch(code)) return null;
      return FundInfo(
        code: code,
        name: '',
        eligibility: FundEligibility.unknown,
        reason: '模拟目录未收录，待联网确认',
      );
    }
    return FundInfo(
      code: code,
      name: known.$1,
      eligibility: known.$3,
      reason: known.$4,
    );
  }

  @override
  Future<FundNavBatch> fetchFundNavs(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final today = calendar.dateOf(now);
    final navDate = today.weekday <= 5 ? today : _previousWeekday(today);
    final previousDate = _previousWeekday(navDate);
    final navs = <String, FundNavSnapshot>{};
    final errors = <String, String>{};
    for (final instrumentId in instrumentIds) {
      final code = fundCodeOf(instrumentId);
      if (code == null) {
        errors[instrumentId] = '基金代码格式不正确';
        continue;
      }
      final info = await fetchFundInfo(code);
      if (info == null) {
        errors[instrumentId] = '模拟目录没有这个基金';
        continue;
      }
      final supported = info.eligibility == FundEligibility.supported;
      navs[instrumentId] = FundNavSnapshot(
        instrumentId: instrumentId,
        navCny: supported ? Rational.parse('1.2356') : null,
        navDate: supported ? navDate : null,
        previousNavCny: supported ? Rational.parse('1.2256') : null,
        previousNavDate: supported ? previousDate : null,
        actionStatus: FundActionStatus.none,
        fundCalendar:
            supported ? FundCalendarKind.mainland : FundCalendarKind.unknown,
        eligibility: info.eligibility,
        fetchedAtUtc: now,
        publishedAtUtc: null,
        source: 'fixture',
        sourceRevision: null,
        quality: QuoteQuality.fixture,
        sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
      );
    }
    return FundNavBatch(
      navs: navs,
      errors: errors,
      serverTime: now,
      refreshAfterSeconds: 1800,
    );
  }

  @override
  Future<QuoteBatch> fetchQuotes(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final today = calendar.dateOf(now);
    final open = today.weekday <= 5;
    final tradingDate = open ? today : _previousWeekday(today);
    final quoteAt = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute - now.minute % 5,
    );
    final quotes = <String, Quote>{};
    for (final instrumentId in instrumentIds) {
      if (instrumentId == 'GOLD.CNY_GRAM.AU9999') {
        quotes[instrumentId] = Quote(
          instrumentId: instrumentId,
          priceCny: Rational.parse('905'),
          baselineCny: Rational.parse('900'),
          quoteAtUtc: quoteAt,
          fetchedAtUtc: now,
          tradingDate: tradingDate,
          dayBasis: QuoteDayBasis.referenceTradingDay,
          marketState: open ? MarketState.open : MarketState.closed,
          quality: QuoteQuality.fixture,
          source: 'fixture',
          sourceRevision: 1,
        );
        continue;
      }
      final known = _knownQuotes[instrumentId];
      final seed = _hash('$instrumentId|${tradingDate.toIsoString()}');
      final price = known?.$1 ?? 5 + (seed % 45000) / 1000;
      final baseline = known?.$2 ?? price * (1 + ((seed % 400) - 200) / 10000);
      quotes[instrumentId] = Quote(
        instrumentId: instrumentId,
        priceCny: Rational.parse(price.toStringAsFixed(3)),
        baselineCny: Rational.parse(baseline.toStringAsFixed(3)),
        quoteAtUtc: quoteAt,
        fetchedAtUtc: now,
        tradingDate: tradingDate,
        dayBasis: QuoteDayBasis.exchangeTradingDay,
        marketState: open ? MarketState.open : MarketState.closed,
        quality: QuoteQuality.fixture,
        source: 'fixture',
        sourceRevision: 1,
      );
    }
    return QuoteBatch(
      quotes: quotes,
      errors: const {},
      serverTime: now,
      refreshAfterSeconds: 60,
    );
  }

  @override
  Future<MarketCalendar> fetchCalendar({
    required String market,
    required LocalDate from,
    required LocalDate to,
  }) async {
    final days = <LocalDate, MarketDayStatus>{};
    var date = from;
    while (date <= to) {
      days[date] =
          date.weekday <= 5 ? MarketDayStatus.open : MarketDayStatus.closed;
      date = date.addDays(1);
    }
    return MarketCalendar(
      days,
      version: 'FIXTURE@v1',
      source: 'fixture (周末规则，未含法定节假日)',
    );
  }

  static LocalDate _previousWeekday(LocalDate date) {
    var cursor = date.addDays(-1);
    while (cursor.weekday > 5) {
      cursor = cursor.addDays(-1);
    }
    return cursor;
  }

  static int _hash(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }
}

/// HTTP adapter for `contracts/market-gateway.openapi.yaml`.
final class GatewayMarketClient implements MarketClient {
  GatewayMarketClient({
    required this.baseUrl,
    this.client,
    this.calendar,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String baseUrl;
  final http.Client? client;
  final BusinessCalendar? calendar;

  /// Transport time is independent of the ledger's optional `nowUtc` input.
  final DateTime Function() _clock;
  DateTime? _retryAtUtc;
  MarketUnavailableException? _blockedError;
  int _transientFailures = 0;

  /// The gateway contract limits each batch to 30 distinct identifiers.
  static const int maxBatchSize = 30;

  static void _validateBatch(List<String> ids) {
    if (ids.length > maxBatchSize || ids.toSet().length != ids.length) {
      throw ArgumentError('行情批次最多包含 30 个不重复标的。');
    }
    if (ids.any((id) => id.isEmpty || id.length > 64)) {
      throw ArgumentError('行情标的 ID 长度必须为 1 至 64。');
    }
  }

  /// All endpoints share a source-level circuit breaker. No in-call retries:
  /// polling/manual refresh may try again after the deadline, but cannot bypass
  /// it. 401/403 disables this client for its lifetime; recreate only after
  /// correcting the source configuration, not as an automatic fallback.
  Future<http.Response> _request(
    Future<http.Response> Function(http.Client) send,
    String failureLabel,
  ) async {
    final blocked = _blockedError;
    if (blocked != null &&
        (_retryAtUtc == null || _clock().toUtc().isBefore(_retryAtUtc!))) {
      throw blocked;
    }
    final httpClient = client ?? http.Client();
    try {
      final response =
          await send(httpClient).timeout(const Duration(seconds: 8));
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        final error = MarketUnavailableException(
          '行情来源不可用（$status），请检查来源访问权限与配置。',
          statusCode: status,
        );
        _blockedError = error;
        _retryAtUtc = null;
        throw error;
      }
      if (status == 429) {
        final now = _clock().toUtc();
        final retryAfter = response.headers.entries
            .where((entry) => entry.key.toLowerCase() == 'retry-after')
            .map((entry) => entry.value)
            .firstOrNull;
        final deadline = _retryAfter(retryAfter, now);
        throw _defer(
          '请求太频繁，行情先歇一下。',
          deadline,
          statusCode: status,
        );
      }
      if (status >= 500) {
        throw _transientFailure('$failureLabel（$status）。', statusCode: status);
      }
      if (status >= 400) {
        throw MarketUnavailableException(
          '$failureLabel（$status）。',
          statusCode: status,
        );
      }
      // An older in-flight success must not erase another request's denial or
      // Retry-After. Expired retryable failures can be cleared safely.
      if (_retryAtUtc == null && _blockedError == null ||
          _retryAtUtc != null && !_clock().toUtc().isBefore(_retryAtUtc!)) {
        _blockedError = null;
        _retryAtUtc = null;
        _transientFailures = 0;
      }
      return response;
    } on TimeoutException {
      throw _transientFailure('$failureLabel（请求超时）。');
    } on http.ClientException {
      throw _transientFailure('$failureLabel（网络连接失败）。');
    } finally {
      // An injected client belongs to the caller; locally-created clients must
      // not leak sockets on success, denial or timeout.
      if (client == null) httpClient.close();
    }
  }

  MarketUnavailableException _transientFailure(
    String message, {
    int? statusCode,
  }) {
    final seconds = (15 * (1 << _transientFailures)).clamp(15, 300);
    if (_transientFailures < 5) _transientFailures++;
    return _defer(
      message,
      _clock().toUtc().add(Duration(seconds: seconds)),
      statusCode: statusCode,
    );
  }

  MarketUnavailableException _defer(
    String message,
    DateTime deadline, {
    int? statusCode,
  }) {
    // Parallel failures may extend a cooldown, never shorten it or undo a
    // permanent access denial.
    if (_blockedError != null && _retryAtUtc == null) return _blockedError!;
    if (_retryAtUtc != null && _retryAtUtc!.isAfter(deadline)) {
      return _blockedError!;
    }
    _retryAtUtc = deadline;
    return _blockedError = MarketUnavailableException(
      message,
      retryable: true,
      statusCode: statusCode,
      retryAtUtc: deadline,
    );
  }

  static DateTime _retryAfter(String? value, DateTime now) {
    final text = value?.trim();
    final seconds = int.tryParse(text ?? '');
    if (seconds != null && seconds >= 0) {
      // Guard untrusted integer overflow without shortening a valid long wait.
      final maxSeconds =
          (8640000000000000 - now.millisecondsSinceEpoch) ~/ 1000;
      if (seconds <= maxSeconds) {
        return now.add(Duration(seconds: seconds == 0 ? 1 : seconds));
      }
      return DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true);
    }
    if (text != null) {
      try {
        final date = parseHttpDate(text).toUtc();
        if (date.isAfter(now)) return date;
      } on FormatException {
        // Missing, invalid or past headers use the conservative fallback.
      }
    }
    return now.add(const Duration(minutes: 1));
  }

  @override
  String get sourceLabel => '行情网关';

  @override
  bool get isFixture => false;

  @override
  Future<List<InstrumentInfo>> searchInstruments(String query) async {
    final uri = Uri.parse('$baseUrl/v1/instruments/search').replace(
      queryParameters: {'q': query.trim(), 'limit': '10'},
    );
    final response =
        await _request((httpClient) => httpClient.get(uri), '证券目录暂时不可用');
    final body = jsonDecode(response.body);
    if (body is! Map)
      throw const FormatException('search body is not an object');
    final items = body['items'];
    if (items is! List) return const <InstrumentInfo>[];
    final result = <InstrumentInfo>[];
    for (final item in items) {
      if (item is! Map) continue;
      final code = item['code'];
      final name = item['name'];
      if (code is! String || name is! String) continue;
      final market = switch (item['market']) {
        'SSE' => StockMarket.sse,
        'SZSE' => StockMarket.szse,
        'BSE' => StockMarket.bse,
        _ => null,
      };
      if (market == null) continue;
      result.add(
        InstrumentInfo(
          instrumentId: (item['instrumentId'] as String?) ??
              instrumentIdFor(code, market),
          code: code,
          name: name,
          market: market,
          supported: item['supported'] != false,
        ),
      );
    }
    return result;
  }

  @override
  Future<FundInfo?> fetchFundInfo(String code) async {
    final uri = Uri.parse('$baseUrl/v1/instruments/search').replace(
      queryParameters: {'q': code, 'kind': 'fund', 'limit': '10'},
    );
    final response =
        await _request((httpClient) => httpClient.get(uri), '基金目录暂时不可用');
    final body = jsonDecode(response.body);
    if (body is! Map)
      throw const FormatException('fund search body is not an object');
    final items = body['items'];
    if (items is! List) return null;
    for (final item in items) {
      if (item is! Map) continue;
      final itemCode = item['code'];
      final itemId = item['instrumentId'];
      if (itemCode != code && itemId != fundInstrumentIdFor(code)) continue;
      final name = item['name'];
      return FundInfo(
        code: code,
        name: name is String ? name : '',
        eligibility: _fundEligibility(item['eligibility']),
        reason: (item['unsupportedReason'] as String?) ?? '',
      );
    }
    return null;
  }

  @override
  Future<FundNavBatch> fetchFundNavs(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    _validateBatch(instrumentIds);
    final now = nowUtc ?? DateTime.now().toUtc();
    if (instrumentIds.isEmpty) {
      return FundNavBatch(
        navs: const {},
        errors: const {},
        serverTime: now,
        refreshAfterSeconds: 1800,
      );
    }
    final response = await _request(
      (httpClient) => httpClient.post(
        Uri.parse('$baseUrl/v1/quotes/batch'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'instrumentIds': instrumentIds}),
      ),
      '基金净值网关暂时不可用',
    );
    final body = jsonDecode(response.body);
    if (body is! Map)
      throw const FormatException('gateway body is not an object');
    final navs = <String, FundNavSnapshot>{};
    final errors = <String, String>{};
    final items = body['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final instrumentId = item['instrumentId'];
        if (instrumentId is! String || !instrumentIds.contains(instrumentId))
          continue;
        if (item['error'] is Map) {
          final error = item['error'] as Map;
          errors[instrumentId] = (error['message'] as String?) ?? '净值获取失败';
          continue;
        }
        if (item['kind'] != 'fundNav') {
          errors[instrumentId] = '返回的不是基金净值';
          continue;
        }
        try {
          navs[instrumentId] = _parseFundNav(item);
        } on Object catch (error) {
          errors[instrumentId] = '基金净价格式无法解析：$error';
        }
      }
    }
    for (final id in instrumentIds) {
      if (!navs.containsKey(id) && !errors.containsKey(id)) {
        errors[id] = '网关未返回该基金净值';
      }
    }
    return FundNavBatch(
      navs: navs,
      errors: errors,
      serverTime: DateTime.tryParse('${body['serverTime']}')?.toUtc() ?? now,
      refreshAfterSeconds:
          (body['refreshAfterSeconds'] as num?)?.toInt() ?? 1800,
    );
  }

  static FundNavSnapshot _parseFundNav(Map<Object?, Object?> item) {
    _rejectFixture(item);
    final instrumentId = item['instrumentId']! as String;
    final nav = _rational(item['navCny']);
    final navDate = LocalDate.tryParse(item['navDate'] as String?);
    if ((nav == null) != (navDate == null)) {
      throw const FormatException('navCny and navDate must be paired');
    }
    final previousNav = _rational(item['previousNavCny']);
    final previousDate = LocalDate.tryParse(item['previousNavDate'] as String?);
    if ((previousNav == null) != (previousDate == null)) {
      throw const FormatException('previous NAV and date must be paired');
    }
    final actionStatus = switch (item['actionStatus']) {
      'none' => FundActionStatus.none,
      'detected' => FundActionStatus.detected,
      _ => FundActionStatus.unknown,
    };
    final calendarKind = switch (item['fundCalendar']) {
      'mainland' => FundCalendarKind.mainland,
      _ => FundCalendarKind.unknown,
    };
    final quality = switch (item['quality']) {
      'live' => QuoteQuality.live,
      'delayed' => QuoteQuality.delayed,
      'eod' => QuoteQuality.eod,
      'stale' => QuoteQuality.stale,
      'fixture' => QuoteQuality.fixture,
      _ => QuoteQuality.unavailable,
    };
    final license = switch (item['sourceLicenseStatus']) {
      'verified' => SourceLicenseStatus.verified,
      'developmentOnly' => SourceLicenseStatus.developmentOnly,
      _ => SourceLicenseStatus.unknown,
    };
    return FundNavSnapshot(
      instrumentId: instrumentId,
      navCny: nav,
      navDate: navDate,
      previousNavCny: previousNav,
      previousNavDate: previousDate,
      actionStatus: actionStatus,
      fundCalendar: calendarKind,
      eligibility: _fundEligibility(item['eligibility']),
      fetchedAtUtc: DateTime.parse(item['fetchedAt']! as String).toUtc(),
      publishedAtUtc: DateTime.tryParse('${item['publishedAt']}')?.toUtc(),
      source: (item['source'] as String?) ?? 'gateway',
      sourceRevision: (item['sourceRevision'] as num?)?.toInt(),
      quality: quality,
      sourceLicenseStatus: license,
    );
  }

  static FundEligibility _fundEligibility(Object? value) => switch (value) {
        'supported' => FundEligibility.supported,
        'unsupported' => FundEligibility.unsupported,
        _ => FundEligibility.unknown,
      };

  @override
  Future<QuoteBatch> fetchQuotes(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    _validateBatch(instrumentIds);
    if (instrumentIds.isEmpty) {
      return QuoteBatch(
        quotes: const {},
        errors: const {},
        serverTime: nowUtc ?? DateTime.now().toUtc(),
        refreshAfterSeconds: 15,
      );
    }
    final response = await _request(
      (httpClient) => httpClient.post(
        Uri.parse('$baseUrl/v1/quotes/batch'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'instrumentIds': instrumentIds}),
      ),
      '行情网关暂时不可用',
    );
    final body = jsonDecode(response.body);
    if (body is! Map)
      throw const FormatException('gateway body is not an object');
    final quotes = <String, Quote>{};
    final errors = <String, String>{};
    final items = body['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final instrumentId = item['instrumentId'];
        if (instrumentId is! String || !instrumentIds.contains(instrumentId))
          continue;
        if (item['error'] is Map) {
          final error = item['error'] as Map;
          errors[instrumentId] = (error['message'] as String?) ?? '报价失败';
          continue;
        }
        try {
          quotes[instrumentId] = _parseQuote(item);
        } on Object catch (error) {
          errors[instrumentId] = '报价格式无法解析：$error';
        }
      }
    }
    for (final id in instrumentIds) {
      if (!quotes.containsKey(id) && !errors.containsKey(id)) {
        errors[id] = '网关未返回该标的报价';
      }
    }
    return QuoteBatch(
      quotes: quotes,
      errors: errors,
      serverTime: DateTime.tryParse('${body['serverTime']}')?.toUtc() ??
          DateTime.now().toUtc(),
      refreshAfterSeconds: (body['refreshAfterSeconds'] as num?)?.toInt() ?? 15,
    );
  }

  static Quote _parseQuote(Map<Object?, Object?> item) {
    _rejectFixture(item);
    final instrumentId = item['instrumentId']! as String;
    final price = _rational(item['priceCny']);
    if (price == null) throw const FormatException('missing priceCny');
    final dayBasis = switch (item['dayBasis']) {
      'referenceTradingDay' => QuoteDayBasis.referenceTradingDay,
      _ => QuoteDayBasis.exchangeTradingDay,
    };
    final marketState = switch (item['marketState']) {
      'PREOPEN' => MarketState.preopen,
      'OPEN' => MarketState.open,
      'BREAK' => MarketState.breakTime,
      'CLOSED' => MarketState.closed,
      'SUSPENDED' => MarketState.suspended,
      _ => MarketState.unknown,
    };
    final quality = switch (item['quality']) {
      'live' => QuoteQuality.live,
      'delayed' => QuoteQuality.delayed,
      'eod' => QuoteQuality.eod,
      'stale' => QuoteQuality.stale,
      'fixture' => QuoteQuality.fixture,
      _ => QuoteQuality.unavailable,
    };
    final tradingDate = LocalDate.tryParse(item['tradingDate'] as String?);
    if (tradingDate == null) throw const FormatException('missing tradingDate');
    return Quote(
      instrumentId: instrumentId,
      priceCny: price,
      baselineCny: _rational(item['baselineCny']),
      quoteAtUtc: DateTime.parse(item['quoteAt']! as String).toUtc(),
      fetchedAtUtc: DateTime.parse(item['fetchedAt']! as String).toUtc(),
      tradingDate: tradingDate,
      dayBasis: dayBasis,
      marketState: marketState,
      quality: quality,
      source: (item['source'] as String?) ?? 'gateway',
      sourceRevision: (item['sourceRevision'] as num?)?.toInt() ?? 0,
      delaySeconds: (item['delaySeconds'] as num?)?.toInt(),
    );
  }

  @override
  Future<MarketCalendar> fetchCalendar({
    required String market,
    required LocalDate from,
    required LocalDate to,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/calendars').replace(queryParameters: {
      'market': market,
      'from': from.toIsoString(),
      'to': to.toIsoString(),
    });
    final response =
        await _request((httpClient) => httpClient.get(uri), '交易日历暂时不可用');
    final body = jsonDecode(response.body);
    if (body is! Map)
      throw const FormatException('calendar body is not an object');
    final days = <LocalDate, MarketDayStatus>{};
    final rawDays = body['days'];
    if (rawDays is List) {
      for (final item in rawDays) {
        if (item is! Map) continue;
        final date = LocalDate.tryParse(item['localDate'] as String?);
        if (date == null) continue;
        final status = item['status'];
        days[date] = switch (status) {
          'open' || 'work' => MarketDayStatus.open,
          'closed' || 'rest' => MarketDayStatus.closed,
          _ => MarketDayStatus.unknown,
        };
      }
    }
    return MarketCalendar(
      days,
      version: (body['version'] as String?) ?? 'unknown',
      source: (body['source'] as String?) ?? market,
    );
  }

  static void _rejectFixture(Map<Object?, Object?> item) {
    if (item['quality'] == 'fixture' || item['source'] == 'fixture') {
      throw const FormatException('模拟行情不得用于真实账本');
    }
  }

  static Rational? _rational(Object? value) =>
      value is String ? Rational.tryParse(value) : null;
}

final class MarketUnavailableException implements Exception {
  const MarketUnavailableException(
    this.message, {
    this.retryable = false,
    this.statusCode,
    this.retryAtUtc,
  });

  final String message;
  final bool retryable;
  final int? statusCode;

  /// Null for permanent access denial or errors without a scheduled retry.
  final DateTime? retryAtUtc;

  @override
  String toString() => message;
}

/// Applies cache-age staleness without pretending the price is live.
Map<String, Quote> applyQuoteFreshness(
  Map<String, Quote> quotes,
  DateTime nowUtc, {
  Duration staleAfter = AppConfig.quoteStaleAfter,
}) {
  return {
    for (final entry in quotes.entries)
      entry.key: _staleIfOld(entry.value, nowUtc, staleAfter),
  };
}

Quote _staleIfOld(Quote quote, DateTime nowUtc, Duration staleAfter) {
  final age = nowUtc.difference(quote.quoteAtUtc);
  final sessionLive = quote.marketState == MarketState.open ||
      quote.marketState == MarketState.breakTime;
  if (!sessionLive) return quote;
  if (quote.quality != QuoteQuality.live &&
      quote.quality != QuoteQuality.delayed) {
    return quote;
  }
  if (age <= staleAfter) return quote;
  return quote.copyWith(quality: QuoteQuality.stale);
}
