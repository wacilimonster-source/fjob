/// Direct adapter for Eastmoney's public quote and instrument search endpoints.
///
/// These endpoints are publicly reachable without a key, but they are not an
/// official licensed feed: quotes are labelled `delayed` and the source licence
/// as `developmentOnly`. Production distribution still needs a licensed source.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;

import '../domain/instrument.dart';
import '../domain/setup_draft.dart';
import 'cn_market_calendar_2026.dart';
import 'market_client.dart';

final class EastmoneyMarketClient implements MarketClient {
  EastmoneyMarketClient({
    required this.calendar,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final BusinessCalendar calendar;
  final http.Client _client;

  static const String _batchFields = 'f12,f13,f14,f2,f18,f124';
  static const String _searchToken = 'D43BF722C8E33BDC906FB84D85E326E8';

  @override
  String get sourceLabel => '东方财富公开接口';

  @override
  bool get isFixture => false;

  String? _secid(String instrumentId) {
    if (instrumentId.startsWith('GOLD.')) return '118.AU9999';
    final parts = instrumentId.split('.');
    if (parts.length < 3) return null;
    final code = parts[2];
    return switch (parts[1]) {
      'SH' => '1.$code',
      'SZ' => '0.$code',
      'BJ' => '0.$code',
      _ => null,
    };
  }

  @override
  Future<QuoteBatch> fetchQuotes(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final secids = <String, String>{};
    for (final id in instrumentIds) {
      final secid = _secid(id);
      if (secid != null) secids[secid] = id;
    }
    if (secids.isEmpty) {
      return QuoteBatch(
        quotes: const {},
        errors: {for (final id in instrumentIds) id: '暂不支持该标的'},
        serverTime: now,
        refreshAfterSeconds: 15,
      );
    }
    final uri = Uri.parse('https://push2.eastmoney.com/api/qt/ulist.np/get')
        .replace(queryParameters: {
      'secids': secids.keys.join(','),
      'fields': _batchFields,
    });
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': 'FJOB/1.0',
        'Referer': 'https://quote.eastmoney.com/',
      }).timeout(const Duration(seconds: 8));
    } on Object {
      throw const MarketUnavailableException('公开行情暂时不可用。', retryable: true);
    }
    if (response.statusCode != 200) {
      throw MarketUnavailableException(
        '公开行情返回 ${response.statusCode}。',
        retryable: response.statusCode >= 500,
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) throw const FormatException('quote body is not an object');
    final data = body['data'];
    final diff = data is Map ? data['diff'] : null;
    final byCode = <String, Map<Object?, Object?>>{};
    if (diff is List) {
      for (final item in diff) {
        if (item is Map && item['f12'] is String) {
          byCode[item['f12']! as String] = item;
        }
      }
    }

    final quotes = <String, Quote>{};
    final errors = <String, String>{};
    for (final entry in secids.entries) {
      final instrumentId = entry.value;
      final code = instrumentId.split('.').last;
      final row = byCode[code];
      if (row == null) {
        errors[instrumentId] = '东财未返回该标的';
        continue;
      }
      final priceRaw = row['f2'];
      final baselineRaw = row['f18'];
      final stamp = row['f124'];
      final price = priceRaw is num && priceRaw > 0
          ? Rational.parse((priceRaw / 100).toStringAsFixed(2))
          : null;
      final baseline = baselineRaw is num && baselineRaw > 0
          ? Rational.parse((baselineRaw / 100).toStringAsFixed(2))
          : null;
      final quoteAt = stamp is num && stamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(stamp.toInt() * 1000, isUtc: true)
          : now;
      final tradingDate = calendar.dateOf(quoteAt);
      final gold = instrumentId.startsWith('GOLD.');
      quotes[instrumentId] = Quote(
        instrumentId: instrumentId,
        priceCny: price,
        baselineCny: baseline,
        quoteAtUtc: quoteAt,
        fetchedAtUtc: now,
        tradingDate: tradingDate,
        dayBasis: gold
            ? QuoteDayBasis.referenceTradingDay
            : QuoteDayBasis.exchangeTradingDay,
        marketState: _marketState(quoteAt, gold: gold),
        quality: QuoteQuality.delayed,
        source: 'eastmoney_public',
        sourceRevision: stamp is num ? stamp.toInt() : 0,
        delaySeconds: null,
      );
    }
    return QuoteBatch(
      quotes: quotes,
      errors: errors,
      serverTime: now,
      refreshAfterSeconds: 15,
    );
  }

  MarketState _marketState(DateTime quoteAtUtc, {required bool gold}) {
    final local = calendar.localTimeOf(quoteAtUtc);
    if (local.weekday > 5) return MarketState.closed;
    final minute = local.hour * 60 + local.minute;
    final sessions = gold
        ? const [(540, 690), (810, 930)]
        : const [(570, 690), (780, 900)];
    if (minute < sessions.first.$1) return MarketState.preopen;
    for (final session in sessions) {
      if (minute >= session.$1 && minute < session.$2) return MarketState.open;
    }
    if (minute < sessions.last.$1) return MarketState.breakTime;
    return MarketState.closed;
  }

  @override
  Future<List<InstrumentInfo>> searchInstruments(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const <InstrumentInfo>[];
    final uri = Uri.https('searchapi.eastmoney.com', '/api/suggest/get', {
      'input': text,
      'type': '14',
      'token': _searchToken,
    });
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': 'FJOB/1.0',
        'Referer': 'https://quote.eastmoney.com/',
      }).timeout(const Duration(seconds: 8));
    } on Object {
      throw const MarketUnavailableException('证券名称查询暂时不可用。', retryable: true);
    }
    if (response.statusCode != 200) {
      throw MarketUnavailableException('证券名称查询返回 ${response.statusCode}。');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final table = body is Map ? body['QuotationCodeTable'] : null;
    final data = table is Map ? table['Data'] : null;
    if (data is! List) return const <InstrumentInfo>[];
    final result = <InstrumentInfo>[];
    for (final item in data) {
      if (item is! Map) continue;
      final code = item['Code'];
      final name = item['Name'];
      final security = item['SecurityTypeName'];
      if (code is! String || name is! String || security is! String) continue;
      if (!const {'沪A', '深A', '京A'}.contains(security)) continue;
      final market = security == '沪A'
          ? StockMarket.sse
          : security == '深A'
              ? StockMarket.szse
              : StockMarket.bse;
      result.add(
        InstrumentInfo(
          instrumentId: instrumentIdFor(code, market),
          code: code,
          name: name,
          market: market,
        ),
      );
      if (result.length >= 10) break;
    }
    return result;
  }

  @override
  Future<MarketCalendar> fetchCalendar({
    required String market,
    required LocalDate from,
    required LocalDate to,
  }) async =>
      buildCnMarketCalendar(from: from, to: to);
}
