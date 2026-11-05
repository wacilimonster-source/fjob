import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todayagain/data/eastmoney_client.dart';
import 'package:todayagain/domain/setup_draft.dart';

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
}
