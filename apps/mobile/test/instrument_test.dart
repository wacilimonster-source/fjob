import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_data/market_data.dart';
import 'package:ledger_model/ledger_model.dart';

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

  test('fund identity never collides with a same-code A-share', () {
    expect(fundInstrumentIdFor('000001'), 'FUND.CN.000001');
    expect(instrumentIdFor('000001', StockMarket.szse), 'CN.SZ.000001');
    expect(isFundInstrumentId('FUND.CN.000001'), isTrue);
    expect(isFundInstrumentId('CN.SZ.000001'), isFalse);
    expect(fundCodeOf('FUND.CN.000001'), '000001');
    expect(fundCodeOf('CN.SZ.000001'), isNull);
  });

  test('the fixture fund directory separates supported and ambiguous products',
      () async {
    final client = FixtureMarketClient(BusinessCalendar.shanghai);

    final supported = await client.fetchFundInfo('000001');
    expect(supported!.name, '华夏成长混合');
    expect(supported.eligibility, FundEligibility.supported);
    expect(supported.instrumentId, 'FUND.CN.000001');

    final feeder = await client.fetchFundInfo('000051');
    expect(feeder!.eligibility, FundEligibility.supported);

    final moneyFund = await client.fetchFundInfo('000198');
    expect(moneyFund!.eligibility, FundEligibility.unsupported);
    expect(moneyFund.reason, isNotEmpty);

    final exchangeTraded = await client.fetchFundInfo('510300');
    expect(exchangeTraded!.eligibility, FundEligibility.unknown);

    final unknown = await client.fetchFundInfo('999999');
    expect(unknown!.eligibility, FundEligibility.unknown);
    expect(unknown.name, isEmpty);
  });

  test('classification does not guess on-exchange or foreign currency', () {
    expect(
      classifyFund(
        code: '000051',
        name: '华夏沪深300ETF联接A',
        type: '指数型-股票',
      ).eligibility,
      FundEligibility.supported,
    );
    expect(
      classifyFund(
        code: '510300',
        name: '华泰柏瑞沪深300ETF',
        type: '指数型-股票',
      ).eligibility,
      FundEligibility.unknown,
    );
    expect(
      classifyFund(
        code: '000198',
        name: '天弘余额宝货币',
        type: '货币型',
      ).eligibility,
      FundEligibility.unsupported,
    );
    expect(
      classifyFund(
        code: '000055',
        name: '华夏优势增长美元份额',
        type: '混合型',
      ).eligibility,
      FundEligibility.unsupported,
    );
    expect(
      classifyFund(
        code: '000009',
        name: '某QDII基金',
        type: 'QDII',
      ).eligibility,
      FundEligibility.unknown,
    );
    // Live directory labels are compound, not the bare asset class.
    expect(
      classifyFund(
        code: '000001',
        name: '华夏成长混合',
        type: '混合型-灵活',
      ).eligibility,
      FundEligibility.supported,
    );
    expect(
      classifyFund(
        code: '000003',
        name: '中海可转债债券A',
        type: '债券型-混合二级',
      ).eligibility,
      FundEligibility.supported,
    );
  });
}
