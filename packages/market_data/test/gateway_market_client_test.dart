import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:finance_core/finance_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_parser/http_parser.dart' show formatHttpDate;
import 'package:ledger_model/ledger_model.dart';
import 'package:market_data/market_data.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 11, 10, 6, 36);
const _stock = 'CN.SZ.000001';
const _fund = 'FUND.CN.000001';

Map<String, Object?> _quote(String id) => {
      'instrumentId': id,
      'priceCny': '12.051',
      'baselineCny': '12.400',
      'quoteAt': '2026-11-10T06:35:00Z',
      'fetchedAt': _now.toIso8601String(),
      'tradingDate': '2026-11-10',
      'dayBasis': 'exchangeTradingDay',
      'marketState': 'OPEN',
      'quality': 'delayed',
      'source': 'licensed_gateway',
      'sourceRevision': 7,
      'sourceLicenseStatus': 'verified',
      'delaySeconds': 60,
    };

Map<String, Object?> _nav(String id) => {
      'kind': 'fundNav',
      'instrumentId': id,
      'navCny': '1.2356',
      'navDate': '2026-11-10',
      'previousNavCny': '1.2256',
      'previousNavDate': '2026-11-09',
      'actionStatus': 'unknown',
      'fundCalendar': 'mainland',
      'eligibility': 'supported',
      'fetchedAt': _now.toIso8601String(),
      'publishedAt': null,
      'source': 'licensed_gateway',
      'sourceRevision': null,
      'quality': 'eod',
      'sourceLicenseStatus': 'verified',
    };

http.Response _batch(List<Map<String, Object?>> items, {int refresh = 60}) =>
    http.Response(
      jsonEncode({
        'requestId': 'mock-boundary',
        'serverTime': _now.toIso8601String(),
        'refreshAfterSeconds': refresh,
        'items': items,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

GatewayMarketClient _gateway(
  Future<http.Response> Function(http.Request) handler, {
  DateTime Function()? clock,
}) =>
    GatewayMarketClient(
      baseUrl: 'https://market.example.invalid',
      client: MockClient(handler),
      clock: clock ?? () => _now,
    );

final _endpoints = <String, Future<Object?> Function(GatewayMarketClient)>{
  'quotes': (client) => client.fetchQuotes([_stock]),
  'NAVs': (client) => client.fetchFundNavs([_fund]),
  'stock search': (client) => client.searchInstruments('000001'),
  'fund search': (client) => client.fetchFundInfo('000001'),
  'calendar': (client) => client.fetchCalendar(
        market: 'SSE',
        from: LocalDate(2026, 11, 1),
        to: LocalDate(2026, 11, 30),
      ),
};

Matcher _unavailable(
        {required bool retryable, int? status, DateTime? retryAt}) =>
    isA<MarketUnavailableException>()
        .having((e) => e.retryable, 'retryable', retryable)
        .having((e) => e.statusCode, 'statusCode', status)
        .having((e) => e.retryAtUtc, 'retryAtUtc', retryAt);

void main() {
  test('stock/gold POST sends only IDs and preserves source precision',
      () async {
    final client = _gateway((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/quotes/batch');
      expect(request.url.queryParameters, isEmpty);
      expect(request.headers['content-type'], 'application/json');
      expect(jsonDecode(request.body), {
        'instrumentIds': [_stock, 'GOLD.CNY_GRAM.AU9999'],
      });
      return _batch([
        _quote(_stock),
        _quote('GOLD.CNY_GRAM.AU9999')
          ..['dayBasis'] = 'referenceTradingDay'
          ..['baselineCny'] = null,
      ]);
    });
    final batch = await client.fetchQuotes([_stock, 'GOLD.CNY_GRAM.AU9999']);
    expect(batch.errors, isEmpty);
    final quote = batch.quotes[_stock]!;
    expect(quote.priceCny, Rational.parse('12.051'));
    expect(quote.baselineCny, Rational.parse('12.4'));
    expect(quote.sourceRevision, 7);
    expect(quote.delaySeconds, 60);
    expect(quote.quoteAtUtc, DateTime.utc(2026, 11, 10, 6, 35));
    expect(quote.fetchedAtUtc, _now);
    expect(quote.quality, QuoteQuality.delayed);
    expect(batch.quotes['GOLD.CNY_GRAM.AU9999']!.baselineCny, isNull);
    expect(batch.quotes['GOLD.CNY_GRAM.AU9999']!.dayBasis,
        QuoteDayBasis.referenceTradingDay);
    expect(batch.serverTime, _now);
    expect(batch.refreshAfterSeconds, 60);
    expect(client.isFixture, isFalse);
  });

  test('fund POST preserves date-only NAV, precision and licence metadata',
      () async {
    final client = _gateway((request) async {
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'instrumentIds': [_fund]
      });
      return _batch([_nav(_fund)], refresh: 1800);
    });
    final batch = await client.fetchFundNavs([_fund]);
    final nav = batch.navs[_fund]!;
    expect(batch.errors, isEmpty);
    expect(nav.navCny, Rational.parse('1.2356'));
    expect(nav.previousNavCny, Rational.parse('1.2256'));
    expect(nav.navDate, LocalDate(2026, 11, 10));
    expect(nav.previousNavDate, LocalDate(2026, 11, 9));
    expect(nav.publishedAtUtc, isNull);
    expect(nav.sourceRevision, isNull);
    expect(nav.actionStatus, FundActionStatus.unknown);
    expect(nav.eligibility, FundEligibility.supported);
    expect(nav.quality, QuoteQuality.eod);
    expect(nav.sourceLicenseStatus, SourceLicenseStatus.verified);
    expect(batch.refreshAfterSeconds, 1800);
  });

  test('stock and fund search keep distinct market/code namespaces', () async {
    final client = _gateway((request) async {
      expect(request.method, 'GET');
      expect(request.body, isEmpty);
      expect(request.url.path, '/v1/instruments/search');
      final fund = request.url.queryParameters['kind'] == 'fund';
      expect(request.url.queryParameters, {
        'q': '000001',
        if (fund) 'kind': 'fund',
        'limit': '10',
      });
      return _batch([
        {
          'instrumentId': fund ? _fund : _stock,
          'code': '000001',
          'name': fund ? '华夏成长混合' : '平安银行',
          'market': fund ? 'CN_FUND' : 'SZSE',
          'supported': true,
          'eligibility': 'supported',
        },
      ]);
    });
    final stock = (await client.searchInstruments(' 000001 ')).single;
    expect(stock.instrumentId, _stock);
    expect(stock.market, StockMarket.szse);
    expect(stock.name, '平安银行');
    final fund = await client.fetchFundInfo('000001');
    expect(fund!.code, '000001');
    expect(fund.name, '华夏成长混合');
    expect(fund.eligibility, FundEligibility.supported);
  });

  test('calendar request preserves dates, version and unknown coverage',
      () async {
    final client = _gateway((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/calendars');
      expect(request.url.queryParameters, {
        'market': 'FUND_CN',
        'from': '2026-11-07',
        'to': '2026-11-10',
      });
      return http.Response(
          jsonEncode({
            'version': 'CN@2026',
            'source': 'calendar_gateway',
            'days': [
              {'localDate': '2026-11-07', 'status': 'closed'},
              {'localDate': '2026-11-09', 'status': 'open'},
              {'localDate': '2026-11-10', 'status': 'unknown'},
            ],
          }),
          200);
    });
    final calendar = await client.fetchCalendar(
      market: 'FUND_CN',
      from: LocalDate(2026, 11, 7),
      to: LocalDate(2026, 11, 10),
    );
    expect(calendar.version, 'CN@2026');
    expect(calendar.statusOn(LocalDate(2026, 11, 7)), MarketDayStatus.closed);
    expect(calendar.statusOn(LocalDate(2026, 11, 9)), MarketDayStatus.open);
    expect(calendar.statusOn(LocalDate(2026, 11, 10)), MarketDayStatus.unknown);
    expect(calendar.statusOn(LocalDate(2027, 1, 1)), MarketDayStatus.unknown);
  });

  for (final fund in [false, true]) {
    test(
        '${fund ? 'NAV' : 'quote'} batch validates 0/30/31 and unique IDs before HTTP',
        () async {
      var calls = 0;
      final client = _gateway((request) async {
        calls++;
        final ids =
            (jsonDecode(request.body)['instrumentIds'] as List).cast<String>();
        expect(ids, hasLength(30));
        return _batch(ids.map(fund ? _nav : _quote).toList());
      });
      Future<Object> fetch(List<String> ids) => fund
          ? client.fetchFundNavs(ids, nowUtc: _now)
          : client.fetchQuotes(ids, nowUtc: _now);
      await fetch([]);
      expect(calls, 0);
      final ids = List.generate(
          30,
          (i) =>
              '${fund ? 'FUND.CN' : 'CN.SZ'}.${i.toString().padLeft(6, '0')}');
      await fetch(ids);
      expect(calls, 1);
      for (final invalid in [
        [...ids, fund ? 'FUND.CN.999999' : 'CN.SZ.999999'],
        [ids.first, ids.first],
        [''],
        ['x' * 65],
      ]) {
        await expectLater(fetch(invalid), throwsArgumentError);
      }
      expect(calls, 1);
    });
  }

  for (final endpoint in _endpoints.entries) {
    test('429 on ${endpoint.key} blocks all endpoints until exact deadline',
        () async {
      var now = _now;
      var calls = 0;
      final client = _gateway((_) async {
        calls++;
        return http.Response('', 429, headers: {'Retry-After': '120'});
      }, clock: () => now);
      final error = _unavailable(
          retryable: true,
          status: 429,
          retryAt: _now.add(const Duration(seconds: 120)));
      await expectLater(endpoint.value(client), throwsA(error));
      for (final call in _endpoints.values) {
        await expectLater(call(client), throwsA(error));
      }
      now = _now.add(const Duration(seconds: 119));
      await expectLater(
          client.fetchQuotes([_stock], nowUtc: DateTime.utc(2099)),
          throwsA(error));
      expect(calls, 1,
          reason:
              'ledger time/manual retries cannot bypass transport cooldown');
      now = _now.add(const Duration(seconds: 120));
      await expectLater(
          endpoint.value(client), throwsA(isA<MarketUnavailableException>()));
      expect(calls, 2);
    });

    for (final status in [401, 403]) {
      test(
          '$status on ${endpoint.key} disables the source without automatic retry',
          () async {
        var now = _now;
        var calls = 0;
        final client = _gateway((_) async {
          calls++;
          return http.Response('sensitive upstream detail', status);
        }, clock: () => now);
        final error = _unavailable(retryable: false, status: status);
        await expectLater(endpoint.value(client), throwsA(error));
        now = _now.add(const Duration(days: 365));
        for (final call in _endpoints.values) {
          await expectLater(call(client), throwsA(error));
        }
        expect(calls, 1);
      });
    }
  }

  final retryHeaders = <String?, Duration>{
    null: const Duration(minutes: 1),
    '': const Duration(minutes: 1),
    '-2': const Duration(minutes: 1),
    'invalid': const Duration(minutes: 1),
    '0': const Duration(seconds: 1),
    ' 90 ': const Duration(seconds: 90),
    '86401': const Duration(seconds: 86401),
    formatHttpDate(_now.add(const Duration(minutes: 4))):
        const Duration(minutes: 4),
    formatHttpDate(_now.subtract(const Duration(seconds: 1))):
        const Duration(minutes: 1),
  };
  for (final entry in retryHeaders.entries) {
    test('Retry-After ${entry.key} uses a safe, non-shortened deadline',
        () async {
      final client = _gateway((_) async => http.Response('', 429,
          headers: {if (entry.key != null) 'retry-after': entry.key!}));
      await expectLater(
          client.fetchQuotes([_stock]),
          throwsA(_unavailable(
            retryable: true,
            status: 429,
            retryAt: _now.add(entry.value),
          )));
    });
  }

  test('5xx uses capped exponential cooldown and resets after recovery',
      () async {
    var now = _now;
    var fail = true;
    var calls = 0;
    final client = _gateway((_) async {
      calls++;
      return fail ? http.Response('', 503) : _batch([_quote(_stock)]);
    }, clock: () => now);
    for (final seconds in [15, 30, 60, 120, 240, 300, 300]) {
      final expected = _unavailable(
          retryable: true,
          status: 503,
          retryAt: now.add(Duration(seconds: seconds)));
      await expectLater(client.fetchQuotes([_stock]), throwsA(expected));
      final count = calls;
      await expectLater(client.fetchQuotes([_stock]), throwsA(expected));
      expect(calls, count, reason: 'no immediate retry');
      now = now.add(Duration(seconds: seconds));
    }
    fail = false;
    expect((await client.fetchQuotes([_stock])).quotes, hasLength(1));
    fail = true;
    await expectLater(
        client.fetchQuotes([_stock]),
        throwsA(_unavailable(
          retryable: true,
          status: 503,
          retryAt: now.add(const Duration(seconds: 15)),
        )));
  });

  test('network failure is sanitized and deferred, never replaced with a price',
      () async {
    var calls = 0;
    final client = _gateway((_) async {
      calls++;
      throw http.ClientException('private proxy credential');
    });
    final error = _unavailable(
        retryable: true, retryAt: _now.add(const Duration(seconds: 15)));
    await expectLater(client.fetchQuotes([_stock]), throwsA(error));
    await expectLater(client.fetchFundNavs([_fund]), throwsA(error));
    expect(calls, 1);
  });

  test('8-second timeout returns no quote, defers retries and can recover', () {
    fakeAsync((async) {
      var calls = 0;
      Object? error;
      QuoteBatch? batch;
      final client = _gateway((_) {
        calls++;
        if (calls == 1) return Completer<http.Response>().future;
        return Future.value(_batch([_quote(_stock)]));
      }, clock: () => _now.add(async.elapsed));
      client.fetchQuotes([_stock]).then<void>((value) {
        batch = value;
      }, onError: (Object e) {
        error = e;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 7));
      expect(error, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(
          error,
          _unavailable(
              retryable: true, retryAt: _now.add(const Duration(seconds: 23))));
      expect(batch, isNull);
      client.fetchQuotes([_stock]).then<void>((value) {
        batch = value;
      }, onError: (Object e) {
        error = e;
      });
      async.flushMicrotasks();
      expect(calls, 1);
      async.elapse(const Duration(seconds: 15));
      client.fetchQuotes([_stock]).then((value) => batch = value);
      async.flushMicrotasks();
      expect(calls, 2);
      expect(batch!.quotes[_stock]!.priceCny, Rational.parse('12.051'));
    });
  });

  for (final status in [429, 401, 403]) {
    test('late concurrent success cannot erase $status source block', () async {
      var calls = 0;
      final pending = Completer<http.Response>();
      final client = _gateway((_) {
        calls++;
        if (calls == 1) return pending.future;
        return Future.value(
            http.Response('', status, headers: {'retry-after': '120'}));
      });
      final slow = client.fetchQuotes([_stock]);
      await Future<void>.delayed(Duration.zero);
      await expectLater(client.fetchFundNavs([_fund]),
          throwsA(isA<MarketUnavailableException>()));
      pending.complete(_batch([_quote(_stock)]));
      await slow;
      await expectLater(client.searchInstruments('000001'),
          throwsA(isA<MarketUnavailableException>()));
      expect(calls, 2);
    });
  }

  test('a late shorter cooldown or network error never weakens access denial',
      () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final client = _gateway((_) {
      calls++;
      if (calls == 1) return pending.future;
      return Future.value(http.Response('', 403));
    });
    final slow = client.fetchQuotes([_stock]);
    final slowAssertion =
        expectLater(slow, throwsA(_unavailable(retryable: false, status: 403)));
    await Future<void>.delayed(Duration.zero);
    await expectLater(client.fetchFundNavs([_fund]),
        throwsA(isA<MarketUnavailableException>()));
    pending.completeError(http.ClientException('connection lost'));
    await slowAssertion;
    await expectLater(client.fetchQuotes([_stock]),
        throwsA(_unavailable(retryable: false, status: 403)));
    expect(calls, 2);
  });

  test('400 is nonretryable but does not disable subsequent valid requests',
      () async {
    var calls = 0;
    final client = _gateway((_) async {
      calls++;
      return calls == 1 ? http.Response('', 400) : _batch([_quote(_stock)]);
    });
    await expectLater(client.fetchQuotes([_stock]),
        throwsA(_unavailable(retryable: false, status: 400)));
    expect((await client.fetchQuotes([_stock])).quotes, hasLength(1));
    expect(calls, 2);
  });

  test(
      'missing/invalid/failed quotes are per-item errors; foreign IDs are ignored',
      () async {
    final client = _gateway((_) async => _batch([
          _quote(_stock),
          _quote('CN.SH.600000')..['priceCny'] = 'not-a-price',
          {
            'instrumentId': 'CN.SH.600519',
            'error': {'message': '来源拒绝'}
          },
          _quote('CN.SZ.999999'),
        ]));
    final batch = await client
        .fetchQuotes([_stock, 'CN.SH.600000', 'CN.SH.600519', 'CN.SZ.000002']);
    expect(batch.quotes.keys, [_stock]);
    expect(batch.errors.keys,
        unorderedEquals(['CN.SH.600000', 'CN.SH.600519', 'CN.SZ.000002']));
    expect(batch.errors['CN.SH.600519'], '来源拒绝');
    expect(batch.errors['CN.SZ.000002'], contains('未返回'));
  });

  test(
      'missing/invalid/failed NAVs are isolated without zero or stock fallback',
      () async {
    final client = _gateway((_) async => _batch([
          _nav(_fund),
          _nav('FUND.CN.000002')..['navDate'] = null,
          _nav('FUND.CN.000003')..['previousNavDate'] = null,
          _nav('FUND.CN.000004')..['kind'] = 'quote',
          {
            'instrumentId': 'FUND.CN.000005',
            'error': {'message': '来源拒绝'}
          },
          _nav('FUND.CN.999999'),
        ]));
    final ids = List.generate(
        6, (i) => 'FUND.CN.${(i + 1).toString().padLeft(6, '0')}');
    final batch = await client.fetchFundNavs(ids);
    expect(batch.navs.keys, [_fund]);
    expect(batch.errors.keys, unorderedEquals(ids.skip(1)));
    expect(batch.errors['FUND.CN.000006'], contains('未返回'));
  });

  for (final body in ['not JSON', '[]', 'null']) {
    test('malformed response $body fails without invented data', () async {
      final client = _gateway((_) async => http.Response(body, 200));
      await expectLater(client.fetchQuotes([_stock]), throwsFormatException);
      await expectLater(client.fetchFundNavs([_fund]), throwsFormatException);
    });
  }

  for (final field in ['quality', 'source']) {
    test('gateway rejects fixture $field for real quotes and NAVs', () async {
      final client = _gateway((_) async => _batch([
            _quote(_stock)..[field] = 'fixture',
            _nav(_fund)..[field] = 'fixture',
          ]));
      final quotes = await client.fetchQuotes([_stock]);
      final navs = await client.fetchFundNavs([_fund]);
      expect(quotes.quotes, isEmpty);
      expect(navs.navs, isEmpty);
      expect(quotes.errors[_stock], contains('模拟行情不得用于真实账本'));
      expect(navs.errors[_fund], contains('模拟行情不得用于真实账本'));
    });
  }

  test('isolated fixture remains deterministic and explicitly labelled',
      () async {
    final client = FixtureMarketClient(BusinessCalendar.shanghai);
    final first =
        await client.fetchQuotes([_stock, 'CN.SZ.123456'], nowUtc: _now);
    final later = await client.fetchQuotes([_stock, 'CN.SZ.123456'],
        nowUtc: _now.add(const Duration(seconds: 30)));
    expect(client.isFixture, isTrue);
    for (final id in first.quotes.keys) {
      expect(first.quotes[id]!.priceCny, later.quotes[id]!.priceCny);
      expect(first.quotes[id]!.quality, QuoteQuality.fixture);
      expect(first.quotes[id]!.source, 'fixture');
    }
  });

  test('freshness changes quality, not the price or source timestamp',
      () async {
    final batch = await _gateway((_) async => _batch([_quote(_stock)]))
        .fetchQuotes([_stock]);
    final quote = batch.quotes[_stock]!;
    final boundary = quote.quoteAtUtc.add(AppConfig.quoteStaleAfter);
    expect(applyQuoteFreshness(batch.quotes, boundary)[_stock]!.quality,
        QuoteQuality.delayed);
    final stale = applyQuoteFreshness(
        batch.quotes, boundary.add(const Duration(seconds: 1)))[_stock]!;
    expect(stale.quality, QuoteQuality.stale);
    expect(stale.priceCny, quote.priceCny);
    expect(stale.quoteAtUtc, quote.quoteAtUtc);
    expect(stale.fetchedAtUtc, quote.fetchedAtUtc);
  });

  test('injected HTTP client remains caller-owned after success and failure',
      () async {
    var calls = 0;
    final httpClient = _TrackingMockClient((_) async {
      calls++;
      return calls == 1 ? _batch([_quote(_stock)]) : http.Response('', 403);
    });
    final client = GatewayMarketClient(
        baseUrl: 'https://market.example.invalid', client: httpClient);
    await client.fetchQuotes([_stock]);
    expect(httpClient.closed, isFalse);
    await expectLater(client.fetchQuotes([_stock]),
        throwsA(isA<MarketUnavailableException>()));
    expect(httpClient.closed, isFalse);
    httpClient.close();
    expect(httpClient.closed, isTrue);
  });
}

final class _TrackingMockClient extends MockClient {
  _TrackingMockClient(super.handler);
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
