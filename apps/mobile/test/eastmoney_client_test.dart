import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_data/market_data.dart';
import 'package:ledger_model/ledger_model.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;

  test('parses a real batch quote response and builds secids', () async {
    late Uri requested;
    final client = EastmoneyMarketClient(
      calendar: calendar,
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'data': {
              'diff': [
                {
                  'f12': '600000',
                  'f13': 1,
                  'f14': '浦发银行',
                  'f2': 987,
                  'f18': 1009,
                  'f124': 1793866310,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final batch = await client.fetchQuotes(['CN.SH.600000']);
    expect(requested.queryParameters['secids'], '1.600000');
    final quote = batch.quotes['CN.SH.600000']!;
    expect(quote.priceCny, Rational.parse('9.87'));
    expect(quote.baselineCny, Rational.parse('10.09'));
    expect(quote.dayBasis, QuoteDayBasis.exchangeTradingDay);
    expect(quote.quality, QuoteQuality.delayed);
    expect(quote.source, 'eastmoney_public');
  });

  test('resolves instrument names and markets from the search endpoint',
      () async {
    final client = EastmoneyMarketClient(
      calendar: calendar,
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'QuotationCodeTable': {
              'Data': [
                {
                  'Code': '600519',
                  'Name': '贵州茅台',
                  'SecurityTypeName': '沪A',
                  'QuoteID': '1.600519',
                },
                {
                  'Code': '920047',
                  'Name': '诺思兰德',
                  'SecurityTypeName': '京A',
                  'QuoteID': '0.920047',
                },
                {
                  'Code': '600000',
                  'Name': '浦发银行',
                  'SecurityTypeName': '沪A',
                  'QuoteID': '1.600000',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final results = await client.searchInstruments('600');
    expect(results, hasLength(3));
    expect(results.first.name, '贵州茅台');
    expect(results.first.market, StockMarket.sse);
    expect(results.first.instrumentId, 'CN.SH.600519');
  });

  test('reports missing instruments instead of inventing a price', () async {
    final client = EastmoneyMarketClient(
      calendar: calendar,
      client: MockClient((request) async => http.Response(
            jsonEncode({'data': {'diff': []}}),
            200,
          )),
    );
    final batch = await client.fetchQuotes(['CN.SZ.000001']);
    expect(batch.quotes, isEmpty);
    expect(batch.errors['CN.SZ.000001'], contains('未返回'));
  });

  const directory =
      'var r = [["000001","HXCZHH","华夏成长混合","混合型-灵活","HUAXIA"],'
      '["110022","YFDXF","易方达消费行业股票","股票型-普通股票","YIFANGDA"],'
      '["000051","HXHS300","华夏沪深300ETF联接A","指数型-股票","LIANJIE"],'
      '["000198","THYEB","天弘余额宝货币","货币型","HUOBI"],'
      '["510300","HTB","华泰柏瑞沪深300ETF","指数型-股票","ETF"],'
      '["000055","HXYS","华夏优势增长美元份额","混合型-灵活","MEIYUAN"]];';

  String history(String code) => jsonEncode({
        'Data': {
          'LSJZList': switch (code) {
            '000001' => [
              {'FSRQ': '2026-11-09', 'DWJZ': '1.2356', 'FHSP': ''},
              {'FSRQ': '2026-11-06', 'DWJZ': '1.2256', 'FHSP': ''},
            ],
            '110022' => const [],
            _ => [
              {'FSRQ': '2026-11-09', 'DWJZ': '1.5000', 'FHSP': '每份派现0.1元'},
            ],
          },
        },
        'ErrCode': 0,
      });

  EastmoneyMarketClient fundClient({
    void Function(Uri uri)? onRequest,
    bool enabled = true,
  }) =>
      EastmoneyMarketClient(
        calendar: calendar,
        fundEnabled: enabled,
        client: MockClient((request) async {
          onRequest?.call(request.url);
          if (request.url.host == 'fund.eastmoney.com') {
            return http.Response.bytes(utf8.encode(directory), 200);
          }
          final code = request.url.queryParameters['fundCode'] ?? '';
          return http.Response.bytes(utf8.encode(history(code)), 200);
        }),
      );

  test('reads the fund directory without executing upstream JavaScript',
      () async {
    final client = fundClient();
    final supported = await client.fetchFundInfo('000001');
    expect(supported!.name, '华夏成长混合');
    expect(supported.eligibility, FundEligibility.supported);

    final money = await client.fetchFundInfo('000198');
    expect(money!.eligibility, FundEligibility.unsupported);
    expect(money.reason, contains('货币'));

    final feeder = await client.fetchFundInfo('000051');
    expect(feeder!.eligibility, FundEligibility.supported);

    final exchange = await client.fetchFundInfo('510300');
    expect(exchange!.eligibility, FundEligibility.unknown);

    final foreign = await client.fetchFundInfo('000055');
    expect(foreign!.eligibility, FundEligibility.unsupported);
  });

  test('parses date-only fund NAVs and keeps unsupported funds unvalued',
      () async {
    final requested = <Uri>[];
    final client = fundClient(onRequest: requested.add);
    final batch = await client.fetchFundNavs([
      'FUND.CN.000001',
      'FUND.CN.000198',
      'FUND.CN.510300',
    ]);
    expect(batch.errors, isEmpty);

    final nav = batch.navs['FUND.CN.000001']!;
    expect(nav.navCny, Rational.parse('1.2356'));
    expect(nav.navDate, LocalDate(2026, 11, 9));
    expect(nav.previousNavCny, Rational.parse('1.2256'));
    expect(nav.previousNavDate, LocalDate(2026, 11, 6));
    // FHSP is empty, but that is not proof of complete interval coverage.
    expect(nav.actionStatus, FundActionStatus.unknown);
    expect(nav.fundCalendar, FundCalendarKind.mainland);
    expect(nav.publishedAtUtc, isNull);
    expect(nav.quality, QuoteQuality.eod);
    expect(nav.sourceLicenseStatus, SourceLicenseStatus.developmentOnly);

    final money = batch.navs['FUND.CN.000198']!;
    expect(money.eligibility, FundEligibility.unsupported);
    expect(money.navCny, isNull);
    expect(money.navDate, isNull);

    final ambiguous = batch.navs['FUND.CN.510300']!;
    expect(ambiguous.eligibility, FundEligibility.unknown);

    // One history request per non-rejected fund; the money fund is rejected
    // from the directory without a NAV request.
    final navRequests = requested
        .where((uri) => uri.host == 'api.fund.eastmoney.com')
        .map((uri) => uri.queryParameters['fundCode'])
        .toList();
    expect(navRequests, containsAll(['000001', '510300']));
    expect(navRequests, isNot(contains('000198')));
    // Only public codes leave the device, never shares or cost.
    for (final uri in requested) {
      expect(uri.queryParameters.keys, isNot(contains('quantity')));
      expect(uri.queryParameters.keys, isNot(contains('cost')));
    }
  });

  test('one fund failure does not block another fund', () async {
    final client = fundClient();
    final batch = await client.fetchFundNavs([
      'FUND.CN.000001',
      'FUND.CN.110022',
    ]);
    expect(batch.navs['FUND.CN.000001']!.navCny, Rational.parse('1.2356'));
    expect(batch.navs['FUND.CN.110022']!.navCny, isNull);
    expect(batch.errors['FUND.CN.110022'], contains('有效单位净值'));
  });

  test('a dividend row is detected and never converted into cash', () async {
    final client = fundClient();
    final batch = await client.fetchFundNavs(['FUND.CN.000002']);
    final nav = batch.navs['FUND.CN.000002'];
    // Not in the directory: eligibility stays unknown and no amount is faked.
    expect(nav!.eligibility, FundEligibility.unknown);
    expect(nav.actionStatus, FundActionStatus.detected);
    expect(nav.navCny, Rational.parse('1.5'));
  });

  test('the public fund source stays disabled unless enabled explicitly',
      () async {
    var calls = 0;
    final client = fundClient(enabled: false, onRequest: (_) => calls++);
    await expectLater(
      client.fetchFundInfo('000001'),
      throwsA(isA<MarketUnavailableException>()),
    );
    final batch = await client.fetchFundNavs(['FUND.CN.000001']);
    expect(batch.navs, isEmpty);
    expect(batch.errors['FUND.CN.000001'], contains('未启用'));
    expect(calls, 0);
  });
}
