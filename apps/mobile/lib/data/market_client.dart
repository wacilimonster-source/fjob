/// Market data clients: deterministic fixture quotes and the gateway adapter.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;

abstract final class AppConfig {
  static const String appName = '今日又白干';
  static const String channelName = 'cn.fjob.todayagain/widgets';

  /// Empty until the verified gateway host is configured for a release build.
  static const String gatewayBaseUrl =
      String.fromEnvironment('FJOB_MARKET_GATEWAY', defaultValue: '');

  static const Duration refreshInterval = Duration(seconds: 15);
  static const Duration quoteStaleAfter = Duration(minutes: 5);
  static const String goldInstrumentName = '上金所 Au99.99 参考价';
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

  Future<QuoteBatch> fetchQuotes(List<String> instrumentIds, {DateTime? nowUtc});

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

  @override
  String get sourceLabel => '模拟行情';

  @override
  bool get isFixture => true;

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
      days[date] = date.weekday <= 5
          ? MarketDayStatus.open
          : MarketDayStatus.closed;
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
  });

  final String baseUrl;
  final http.Client? client;
  final BusinessCalendar? calendar;

  @override
  String get sourceLabel => '行情网关';

  @override
  bool get isFixture => false;

  @override
  Future<QuoteBatch> fetchQuotes(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    if (instrumentIds.isEmpty) {
      return QuoteBatch(
        quotes: const {},
        errors: const {},
        serverTime: nowUtc ?? DateTime.now().toUtc(),
        refreshAfterSeconds: 15,
      );
    }
    final httpClient = client ?? http.Client();
    final response = await httpClient
        .post(
          Uri.parse('$baseUrl/v1/quotes/batch'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'instrumentIds': instrumentIds}),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 429) {
      throw MarketUnavailableException('请求太频繁，行情先歇一下。', retryable: true);
    }
    if (response.statusCode >= 400) {
      throw MarketUnavailableException(
        '行情网关返回 ${response.statusCode}。',
        retryable: response.statusCode >= 500,
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map) throw const FormatException('gateway body is not an object');
    final quotes = <String, Quote>{};
    final errors = <String, String>{};
    final items = body['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final instrumentId = item['instrumentId'];
        if (instrumentId is! String) continue;
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
    return QuoteBatch(
      quotes: quotes,
      errors: errors,
      serverTime: DateTime.tryParse('${body['serverTime']}')?.toUtc() ??
          DateTime.now().toUtc(),
      refreshAfterSeconds: (body['refreshAfterSeconds'] as num?)?.toInt() ?? 15,
    );
  }

  static Quote _parseQuote(Map<Object?, Object?> item) {
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
    final httpClient = client ?? http.Client();
    final uri = Uri.parse('$baseUrl/v1/calendars').replace(queryParameters: {
      'market': market,
      'from': from.toIsoString(),
      'to': to.toIsoString(),
    });
    final response = await httpClient
        .get(uri)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode >= 400) {
      throw MarketUnavailableException(
        '交易日历暂时不可用（${response.statusCode}）。',
        retryable: response.statusCode >= 500,
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map) throw const FormatException('calendar body is not an object');
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

  static Rational? _rational(Object? value) =>
      value is String ? Rational.tryParse(value) : null;
}

final class MarketUnavailableException implements Exception {
  const MarketUnavailableException(this.message, {this.retryable = false});

  final String message;
  final bool retryable;

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
