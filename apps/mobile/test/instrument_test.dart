import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/data/market_client.dart';
import 'package:todayagain/domain/instrument.dart';
import 'package:todayagain/domain/setup_draft.dart';

void main() {
  test('marketForCode follows A-share prefixes and rejects B shares', () {
    expect(marketForCode('600000'), StockMarket.sse);
    expect(marketForCode('688981'), StockMarket.sse);
    expect(marketForCode('000001'), StockMarket.szse);
    expect(marketForCode('300750'), StockMarket.szse);
    expect(marketForCode('430047'), StockMarket.bse);
    expect(marketForCode('830799'), StockMarket.bse);
    expect(marketForCode('920002'), StockMarket.bse);
    expect(marketForCode('900901'), isNull);
    expect(marketForCode('200001'), isNull);
    expect(marketForCode('60000'), isNull);
    expect(marketForCode('ABCDEF'), isNull);
  });

  test('instrumentIdFor keeps the leading zeroes', () {
    expect(instrumentIdFor('000001', StockMarket.szse), 'CN.SZ.000001');
    expect(instrumentIdFor('600000', StockMarket.sse), 'CN.SH.600000');
  });

  test('the fixture directory looks up known names and infers unknown ones',
      () async {
    final client = FixtureMarketClient(BusinessCalendar.shanghai);

    final pingan = await client.searchInstruments('000001');
    expect(pingan, hasLength(1));
    expect(pingan.single.name, '平安银行');
    expect(pingan.single.market, StockMarket.szse);
    expect(pingan.single.supported, isTrue);

    final maotai = await client.searchInstruments('600519');
    expect(maotai.single.name, '贵州茅台');
    expect(maotai.single.instrumentId, 'CN.SH.600519');

    final unknown = await client.searchInstruments('601999');
    expect(unknown.single.name, isEmpty);
    expect(unknown.single.market, StockMarket.sse);
    expect(unknown.single.supported, isFalse);

    final byName = await client.searchInstruments('银行');
    expect(byName.map((item) => item.code), contains('000001'));
  });
}
