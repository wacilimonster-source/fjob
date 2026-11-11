import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';
import 'package:ledger_model/ledger_model.dart';

import 'support/test_env.dart';

final class _FakeMarketClient implements MarketClient {
  _FakeMarketClient(this.calendar);

  final BusinessCalendar calendar;
  int quoteCalls = 0;
  int fundCalls = 0;
  final List<List<String>> quoteRequests = [];
  final List<List<String>> fundRequests = [];

  @override
  String get sourceLabel => 'fake';

  @override
  bool get isFixture => true;

  @override
  Future<FundInfo?> fetchFundInfo(String code) async =>
      FundInfo(code: code, name: '', eligibility: FundEligibility.unknown);

  @override
  Future<List<InstrumentInfo>> searchInstruments(String query) async =>
      const <InstrumentInfo>[];

  @override
  Future<QuoteBatch> fetchQuotes(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    quoteCalls++;
    quoteRequests.add(List<String>.from(instrumentIds));
    final now = nowUtc ?? fixedNow;
    return QuoteBatch(
      quotes: {
        'CN.SZ.000001': Quote(
          instrumentId: 'CN.SZ.000001',
          priceCny: Rational.parse('12.05'),
          baselineCny: Rational.parse('12.4'),
          quoteAtUtc: now,
          fetchedAtUtc: now,
          tradingDate: LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.exchangeTradingDay,
          marketState: MarketState.open,
          quality: QuoteQuality.live,
          source: 'fake',
          sourceRevision: 1,
        ),
      },
      errors: const {},
      serverTime: now,
      refreshAfterSeconds: 15,
    );
  }

  @override
  Future<FundNavBatch> fetchFundNavs(
    List<String> instrumentIds, {
    DateTime? nowUtc,
  }) async {
    fundCalls++;
    fundRequests.add(List<String>.from(instrumentIds));
    final now = nowUtc ?? fixedNow;
    final navs = <String, FundNavSnapshot>{};
    final errors = <String, String>{};
    for (final id in instrumentIds) {
      if (id == 'FUND.CN.110022') {
        errors[id] = '来源暂时没有这只基金';
        continue;
      }
      navs[id] = FundNavSnapshot(
        instrumentId: id,
        navCny: Rational.parse('1.2356'),
        navDate: LocalDate(2026, 11, 4),
        previousNavCny: Rational.parse('1.2256'),
        previousNavDate: LocalDate(2026, 11, 3),
        actionStatus: FundActionStatus.none,
        fundCalendar: FundCalendarKind.mainland,
        eligibility: FundEligibility.supported,
        fetchedAtUtc: now,
        publishedAtUtc: null,
        source: 'fake',
        sourceRevision: null,
        quality: QuoteQuality.eod,
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
    return MarketCalendar(days, version: 'FAKE@v1', source: 'fake');
  }
}

void main() {
  final calendar = BusinessCalendar.shanghai;

  Future<(QuoteRepository, LedgerRepository, _FakeMarketClient)> setup() async {
    initSqliteFfi();
    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: newDatabasePath(),
      calendar: calendar,
    );
    addTearDown(database.close);
    final ledger = LedgerRepository(database, calendar);
    final client = _FakeMarketClient(calendar);
    return (
      QuoteRepository(client: client, ledger: ledger, calendar: calendar),
      ledger,
      client,
    );
  }

  test('FND-17 one failed fund never blocks another fund or a stock', () async {
    final (repository, ledger, client) = await setup();
    final outcome = await repository.refresh(
      ['CN.SZ.000001', 'FUND.CN.000001', 'FUND.CN.110022'],
      nowUtc: fixedNow,
      manual: true,
    );
    expect(outcome.success, isTrue);
    expect(outcome.quoteCount, 1);
    expect(outcome.fundCount, 1);
    expect(outcome.errors['FUND.CN.110022'], isNotNull);
    expect(client.quoteRequests.single, ['CN.SZ.000001']);
    expect(
      client.fundRequests.single,
      ['FUND.CN.000001', 'FUND.CN.110022'],
    );

    final state = await ledger.read(nowUtc: fixedNow);
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.05'));
    expect(
      state.fundNavs['FUND.CN.000001']!.navCny,
      Rational.parse('1.2356'),
    );
    expect(state.fundNavs.containsKey('FUND.CN.110022'), isFalse);
  });

  test('ordinary fund refreshes keep a 30-minute floor', () async {
    final (repository, _, client) = await setup();
    await repository.refresh(
      ['FUND.CN.000001'],
      nowUtc: fixedNow,
      manual: true,
    );
    expect(client.fundCalls, 1);

    await repository.refresh(
      ['FUND.CN.000001'],
      nowUtc: fixedNow.add(const Duration(minutes: 5)),
    );
    expect(client.fundCalls, 1, reason: 'cached NAV is younger than 30 minutes');

    await repository.refresh(
      ['FUND.CN.000001'],
      nowUtc: fixedNow.add(const Duration(minutes: 31)),
    );
    expect(client.fundCalls, 2);

    await repository.refresh(
      ['FUND.CN.000001'],
      nowUtc: fixedNow.add(const Duration(minutes: 32)),
      manual: true,
    );
    expect(client.fundCalls, 3, reason: 'manual refresh bypasses the floor');
  });

  test('a fund-only batch never enters the stock secid route', () async {
    final (repository, _, client) = await setup();
    final outcome = await repository.refresh(
      ['FUND.CN.000001'],
      nowUtc: fixedNow,
      manual: true,
    );
    expect(outcome.success, isTrue);
    expect(client.quoteCalls, 0);
    expect(client.quoteRequests, isEmpty);
    expect(client.fundCalls, 1);
  });
}
