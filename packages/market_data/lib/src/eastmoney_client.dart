/// Direct adapter for Eastmoney's public quote and instrument search endpoints.
///
/// These endpoints are publicly reachable without a key, but they are not an
/// official licensed feed: quotes are labelled `delayed` and the source licence
/// as `developmentOnly`. Production distribution still needs a licensed source.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;

import 'package:ledger_model/ledger_model.dart';
import 'cn_market_calendar_2026.dart';
import 'market_client.dart';

final class EastmoneyMarketClient implements MarketClient {
  EastmoneyMarketClient({
    required this.calendar,
    http.Client? client,
    bool? fundEnabled,
  })  : _client = client ?? http.Client(),
        fundEnabled = fundEnabled ?? AppConfig.fundPublicSourceEnabled;

  final BusinessCalendar calendar;
  final http.Client _client;

  /// Public fund endpoints are a development candidate only; release builds
  /// stay disabled until access and display licences are recorded.
  final bool fundEnabled;

  static const String _batchFields = 'f12,f13,f14,f2,f18,f124';
  static const String _searchToken = 'D43BF722C8E33BDC906FB84D85E326E8';
  static const String _fundDirectoryUrl =
      'https://fund.eastmoney.com/js/fundcode_search.js';
  static const String _fundHistoryUrl =
      'https://api.fund.eastmoney.com/f10/lsjz';

  Map<String, FundInfo>? _fundDirectory;
  DateTime? _fundDirectoryAt;
  static const Duration _fundDirectoryTtl = Duration(hours: 12);

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
  Future<FundInfo?> fetchFundInfo(String code) async {
    if (!fundEnabled) {
      throw const MarketUnavailableException(
        '基金公开源未启用（开发验证源尚未取得展示许可）。',
      );
    }
    final directory = await _loadFundDirectory();
    return directory[code] ??
        FundInfo(
          code: code,
          name: '',
          eligibility: FundEligibility.unknown,
          reason: '基金目录未收录，待联网确认',
        );
  }

  @override
  Future<FundNavBatch> fetchFundNavs(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final navs = <String, FundNavSnapshot>{};
    final errors = <String, String>{};
    if (instrumentIds.isEmpty) {
      return FundNavBatch(
        navs: navs,
        errors: errors,
        serverTime: now,
        refreshAfterSeconds: 1800,
      );
    }
    if (!fundEnabled) {
      for (final instrumentId in instrumentIds) {
        errors[instrumentId] = '基金公开源未启用（开发验证源尚未取得展示许可）。';
      }
      return FundNavBatch(
        navs: navs,
        errors: errors,
        serverTime: now,
        refreshAfterSeconds: 1800,
      );
    }

    Map<String, FundInfo> directory = const {};
    try {
      directory = await _loadFundDirectory();
    } on Object {
      // The NAV endpoint can still be useful; eligibility stays unknown.
    }

    for (final instrumentId in instrumentIds) {
      final code = fundCodeOf(instrumentId);
      if (code == null) {
        errors[instrumentId] = '基金代码格式不正确';
        continue;
      }
      final info = directory[code] ??
          FundInfo(
            code: code,
            name: '',
            eligibility: FundEligibility.unknown,
            reason: '基金目录未收录，待联网确认',
          );
      if (info.eligibility == FundEligibility.unsupported) {
        // Persist the confirmed rejection so an earlier offline record stops
        // being valued without deleting the user's shares and cost.
        navs[instrumentId] = _eligibilityOnly(instrumentId, info, now);
        continue;
      }
      try {
        final rows = await _fetchFundHistory(code);
        if (rows.isEmpty) {
          navs[instrumentId] = _eligibilityOnly(instrumentId, info, now);
          errors[instrumentId] = '来源没有返回有效单位净值';
          continue;
        }
        final latest = rows.first;
        final previous = rows.length > 1 && rows[1].$1.compareTo(latest.$1) < 0
            ? rows[1]
            : null;
        final eventDetected = rows.any((row) => row.$3);
        navs[instrumentId] = FundNavSnapshot(
          instrumentId: instrumentId,
          navCny: latest.$2,
          navDate: latest.$1,
          previousNavCny: previous?.$2,
          previousNavDate: previous?.$1,
          // FHSP per day is not proof of complete interval coverage; only a
          // visible event is certain. Otherwise the daily move stays unknown.
          actionStatus: eventDetected
              ? FundActionStatus.detected
              : FundActionStatus.unknown,
          fundCalendar: info.eligibility == FundEligibility.supported
              ? FundCalendarKind.mainland
              : FundCalendarKind.unknown,
          eligibility: info.eligibility,
          fetchedAtUtc: now,
          publishedAtUtc: null,
          source: 'eastmoney_fund_public',
          sourceRevision: null,
          quality: QuoteQuality.eod,
          sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
        );
      } on Object {
        errors[instrumentId] = '基金净值暂时没赶上';
      }
    }
    return FundNavBatch(
      navs: navs,
      errors: errors,
      serverTime: now,
      refreshAfterSeconds: 1800,
    );
  }

  static FundNavSnapshot _eligibilityOnly(
    String instrumentId,
    FundInfo info,
    DateTime now,
  ) =>
      FundNavSnapshot(
        instrumentId: instrumentId,
        navCny: null,
        navDate: null,
        previousNavCny: null,
        previousNavDate: null,
        actionStatus: FundActionStatus.unknown,
        fundCalendar: FundCalendarKind.unknown,
        eligibility: info.eligibility,
        fetchedAtUtc: now,
        publishedAtUtc: null,
        source: 'eastmoney_fund_public',
        sourceRevision: null,
        quality: QuoteQuality.eod,
        sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
      );

  /// Reads the fund directory as data. The upstream `.js` file is never
  /// executed; only its JSON array literal is decoded.
  Future<Map<String, FundInfo>> _loadFundDirectory() async {
    final cached = _fundDirectory;
    if (cached != null &&
        _fundDirectoryAt != null &&
        DateTime.now().toUtc().difference(_fundDirectoryAt!) <
            _fundDirectoryTtl) {
      return cached;
    }
    final http.Response response;
    try {
      response = await _client.get(
        Uri.parse(_fundDirectoryUrl),
        headers: {
          'User-Agent': 'FJOB/1.0',
          'Referer': 'https://fund.eastmoney.com/fund.html',
        },
      ).timeout(const Duration(seconds: 8));
    } on Object {
      throw const MarketUnavailableException(
        '基金目录暂时不可用。',
        retryable: true,
      );
    }
    if (response.statusCode != 200) {
      throw MarketUnavailableException(
        '基金目录返回 ${response.statusCode}。',
        retryable: response.statusCode >= 500,
      );
    }
    final text = utf8.decode(response.bodyBytes);
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const FormatException('fund directory is not an array');
    }
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is! List) {
      throw const FormatException('fund directory is not a list');
    }
    final directory = <String, FundInfo>{};
    for (final row in decoded) {
      if (row is! List || row.length < 4) continue;
      final code = row[0];
      final name = row[2];
      final type = row[3];
      if (code is! String ||
          name is! String ||
          type is! String ||
          !RegExp(r'^\d{6}$').hasMatch(code)) {
        continue;
      }
      directory[code] = classifyFund(code: code, name: name, type: type);
    }
    _fundDirectory = directory;
    _fundDirectoryAt = DateTime.now().toUtc();
    return directory;
  }

  /// Latest and previous unit NAV rows, newest first. `FHSP` marks a visible
  /// dividend/split; its absence is not treated as proof of "no event".
  Future<List<(LocalDate, Rational, bool)>> _fetchFundHistory(
    String code,
  ) async {
    final uri = Uri.parse(_fundHistoryUrl).replace(queryParameters: {
      'fundCode': code,
      'pageIndex': '1',
      'pageSize': '2',
    });
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': 'FJOB/1.0',
        'Referer': 'https://fundf10.eastmoney.com/jjjz_$code.html',
      }).timeout(const Duration(seconds: 8));
    } on Object {
      throw const MarketUnavailableException('基金净值暂时不可用。', retryable: true);
    }
    if (response.statusCode != 200) {
      throw MarketUnavailableException(
        '基金净值返回 ${response.statusCode}。',
        retryable: response.statusCode >= 500,
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final data = body is Map ? body['Data'] : null;
    final list = data is Map ? data['LSJZList'] : null;
    if (list is! List) return const [];
    final rows = <(LocalDate, Rational, bool)>[];
    for (final item in list) {
      if (item is! Map) continue;
      final date = LocalDate.tryParse(item['FSRQ'] as String?);
      final nav = Rational.tryParse(item['DWJZ'] as String?);
      if (date == null || nav == null || nav.isNegative) continue;
      final rawEvent = item['FHSP'];
      final event = rawEvent is String &&
          rawEvent.trim().isNotEmpty &&
          rawEvent.trim() != '--' &&
          rawEvent.trim() != '0';
      rows.add((date, nav, event));
    }
    rows.sort((a, b) => b.$1.compareTo(a.$1));
    return rows;
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
    if (body is! Map)
      throw const FormatException('quote body is not an object');
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
          ? DateTime.fromMillisecondsSinceEpoch(stamp.toInt() * 1000,
              isUtc: true)
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
    final sessions =
        gold ? const [(540, 690), (810, 930)] : const [(570, 690), (780, 900)];
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
