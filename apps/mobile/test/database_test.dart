import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todayagain/data/app_database.dart';
import 'package:todayagain/data/home_metrics_preference_store.dart';
import 'package:todayagain/data/ledger_repository.dart';
import 'package:todayagain/domain/home_metrics.dart';
import 'package:todayagain/domain/ledger.dart';
import 'package:todayagain/domain/setup_draft.dart';

import 'support/test_env.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;

  Future<LedgerRepository> openMemory() async {
    initSqliteFfi();
    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: newDatabasePath(),
      calendar: calendar,
    );
    addTearDown(database.close);
    return LedgerRepository(database, calendar);
  }

  test('setup commit is atomic, versioned and idempotent', () async {
    final repository = await openMemory();
    final validation = housingDraft('session-1').validate();
    expect(validation.isValid, isTrue);

    final first = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-1',
      nowUtc: fixedNow,
    );
    expect(first.settings.ledgerRevision, 1);
    expect(first.settings.hasCompletedOnboarding, isTrue);
    expect(first.salaryVersions, hasLength(1));
    expect(first.housingVersions.single.mode, HousingMode.mortgage);
    expect(first.carVersions.single.enabled, isTrue);
    expect(first.bills, hasLength(2));

    final duplicate = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-1',
      nowUtc: fixedNow,
    );
    expect(duplicate.settings.ledgerRevision, 1);
    expect(duplicate.salaryVersions, hasLength(1));
    expect(duplicate.bills, hasLength(2));

    final second = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-2',
      nowUtc: fixedNow,
    );
    expect(second.settings.ledgerRevision, 2);
    expect(second.salaryVersions, hasLength(2));
  });

  test('an expected revision mismatch is rejected', () async {
    final repository = await openMemory();
    final validation = housingDraft('session-1').validate();
    await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-1',
      nowUtc: fixedNow,
    );
    expect(
      () => repository.updateSettings(
        expectedRevision: 0,
        theme: ThemeSetting.dark,
        nowUtc: fixedNow,
      ),
      throwsA(isA<RevisionConflictException>()),
    );
  });

  test('settings changes bump the ledger revision', () async {
    final repository = await openMemory();
    final validation = housingDraft('session-1').validate();
    await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-1',
      nowUtc: fixedNow,
    );
    final updated = await repository.updateSettings(
      expectedRevision: 1,
      widgetPrivacy: true,
      nowUtc: fixedNow,
    );
    expect(updated.settings.ledgerRevision, 2);
    expect(updated.settings.widgetPrivacy, isTrue);
  });

  test('clearing removes configuration, quotes and drafts', () async {
    final repository = await openMemory();
    final validation = housingDraft('session-1').validate();
    await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'session-1',
      nowUtc: fixedNow,
    );
    await repository.saveQuotes([
      Quote(
        instrumentId: 'CN.SZ.000001',
        priceCny: Rational.parse('12.05'),
        baselineCny: Rational.parse('12.4'),
        quoteAtUtc: fixedNow,
        fetchedAtUtc: fixedNow,
        tradingDate: LocalDate(2026, 11, 4),
        dayBasis: QuoteDayBasis.exchangeTradingDay,
        marketState: MarketState.open,
        quality: QuoteQuality.fixture,
        source: 'fixture',
        sourceRevision: 1,
      ),
    ]);
    final cleared = await repository.clearAll(nowUtc: fixedNow);
    expect(cleared.isConfigured, isFalse);
    expect(cleared.settings.ledgerRevision, 2);
    expect(cleared.quotes, isEmpty);
    expect(cleared.bills, isEmpty);
  });

  test('older quotes never overwrite newer ones', () async {
    final repository = await openMemory();
    Quote quote(DateTime at, String price, int revision) => Quote(
          instrumentId: 'CN.SZ.000001',
          priceCny: Rational.parse(price),
          baselineCny: Rational.parse('12.4'),
          quoteAtUtc: at,
          fetchedAtUtc: at,
          tradingDate: LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.exchangeTradingDay,
          marketState: MarketState.open,
          quality: QuoteQuality.live,
          source: 'test',
          sourceRevision: revision,
        );
    await repository.saveQuotes([quote(fixedNow, '12.05', 1)]);
    await repository.saveQuotes([
      quote(fixedNow.subtract(const Duration(seconds: 10)), '11.00', 2),
    ]);
    var state = await repository.read(nowUtc: fixedNow);
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.05'));

    await repository.saveQuotes([quote(fixedNow, '12.10', 0)]);
    state = await repository.read(nowUtc: fixedNow);
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.05'));

    await repository.saveQuotes([quote(fixedNow, '12.10', 3)]);
    state = await repository.read(nowUtc: fixedNow);
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.10'));
  });

  test('drafts keep raw invalid text and the current step', () async {
    final repository = await openMemory();
    await repository.saveDraft(
      setupSessionId: 'session-9',
      step: 2,
      payload: {'salary': '12a'},
      nowUtc: fixedNow,
    );
    final loaded = await repository.loadDraft();
    expect(loaded, isNotNull);
    expect(loaded!.step, 2);
    expect(loaded.payload['salary'], '12a');
  });

  test('instrument names are persisted and updated', () async {
    final repository = await openMemory();
    final draft = validDraft('names')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          name: '平安银行',
          quantityText: '100',
          costText: '12',
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    final state = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'names',
      nowUtc: fixedNow,
    );
    expect(state.instrumentNames['CN.SZ.000001'], '平安银行');

    final updated = await repository.upsertHolding(
      expectedRevision: state.settings.ledgerRevision,
      instrumentId: 'CN.SZ.000001',
      quantity: Rational.parse('200'),
      costPerUnit: Rational.parse('12.5'),
      name: '平安银行A',
      nowUtc: fixedNow,
    );
    expect(updated.instrumentNames['CN.SZ.000001'], '平安银行A');
  });

  test('v1 databases gain the directory and alternation column', () async {
    initSqliteFfi();
    final path = newDatabasePath();
    final raw = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE schedule_versions ('
            'id TEXT NOT NULL PRIMARY KEY,'
            'timezone TEXT NOT NULL,'
            'weekly_json TEXT NOT NULL,'
            'effective_from TEXT NOT NULL,'
            'effective_to TEXT,'
            'calendar_source_version TEXT NOT NULL,'
            'created_at TEXT NOT NULL)',
          );
        },
      ),
    );
    await raw.close();

    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    addTearDown(database.close);
    final directory = await database.raw.query('instrument_directory');
    expect(directory, isEmpty);
    final columns = await database.raw.rawQuery(
      'PRAGMA table_info(schedule_versions)',
    );
    expect(
      columns.any((column) => column['name'] == 'alternation_json'),
      isTrue,
    );
  });

  test('legacy flat configuration migrates to versioned rows', () async {
    initSqliteFfi();
    final directory = await Directory.systemTemp.createTemp('fjob_legacy');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/legacy.db';

    final raw = await databaseFactoryFfiNoIsolate.openDatabase(path);
    await raw.execute('''
      CREATE TABLE legacy_config (
        salary_cny TEXT,
        workdays INTEGER,
        shift_start TEXT,
        shift_end TEXT,
        break_start TEXT,
        break_end TEXT,
        housing_mode TEXT,
        mortgage_cny TEXT,
        mortgage_principal_cny TEXT,
        rent_cny TEXT,
        car_cny TEXT,
        car_principal_cny TEXT
      )
    ''');
    await raw.insert('legacy_config', {
      'salary_cny': '15000',
      'workdays': 31,
      'shift_start': '09:00',
      'shift_end': '18:00',
      'break_start': '12:00',
      'break_end': '13:00',
      'housing_mode': 'mortgage',
      'mortgage_cny': '5000',
      'mortgage_principal_cny': null,
      'rent_cny': '0',
      'car_cny': '2000',
      'car_principal_cny': '1200',
    });
    await raw.close();

    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    addTearDown(database.close);
    final repository = LedgerRepository(database, calendar);
    final state = await repository.read(nowUtc: fixedNow);
    expect(state.settings.hasCompletedOnboarding, isTrue);
    expect(state.salaryVersions.single.monthlyNetCny, Rational.parse('15000'));
    expect(state.housingVersions.single.mode, HousingMode.mortgage);
    expect(state.carVersions.single.enabled, isTrue);
    final housingBill =
        state.bills.firstWhere((bill) => bill.kind == ExpenseKind.housing);
    expect(housingBill.monthlyAmountCny, Rational.parse('5000'));
    expect(housingBill.principalCny, isNull);
  });

  test('v3 databases upgrade to the current schema without data loss', () async {
    initSqliteFfi();
    final path = newDatabasePath();
    // Build a real v4 ledger first, then remove the fund table and report
    // user_version 3 so the production onUpgrade(3 -> current) path runs.
    final first = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    final firstRepository = LedgerRepository(first, calendar);
    final draft = validDraft('v3')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '1000',
          costText: '13',
        ),
      ];
    final committed = await firstRepository.commitSetup(
      commit: draft.validate().commit!,
      setupSessionId: 'v3',
      nowUtc: fixedNow,
    );
    await firstRepository.saveQuotes([
      Quote(
        instrumentId: 'CN.SZ.000001',
        priceCny: Rational.parse('12.05'),
        baselineCny: Rational.parse('12.4'),
        quoteAtUtc: fixedNow,
        fetchedAtUtc: fixedNow,
        tradingDate: LocalDate(2026, 11, 4),
        dayBasis: QuoteDayBasis.exchangeTradingDay,
        marketState: MarketState.open,
        quality: QuoteQuality.live,
        source: 'legacy',
        sourceRevision: 2,
      ),
    ]);
    await first.raw.execute('DROP TABLE fund_nav_cache');
    // v5 (parallel work) created ui_preferences; remove it too so the simulated
    // v3 database has exactly the v3 table set.
    await first.raw.execute('DROP TABLE ui_preferences');
    await first.raw.execute('PRAGMA user_version = 3');
    await first.close();

    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    addTearDown(database.close);
    final repository = LedgerRepository(database, calendar);
    final state = await repository.read(nowUtc: fixedNow);
    expect(state.settings.ledgerRevision, committed.settings.ledgerRevision);
    expect(state.holdings.single.instrumentId, 'CN.SZ.000001');
    expect(state.salaryVersions, hasLength(1));
    expect(state.housingVersions, hasLength(1));
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.05'));
    final fundTable = await database.raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'fund_nav_cache'",
    );
    expect(fundTable, isNotEmpty);
    expect(state.fundNavs, isEmpty);
  });

  test('v2 databases upgrade through v3/v4/v5 without data loss', () async {
    initSqliteFfi();
    final path = newDatabasePath();
    final first = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    final firstRepository = LedgerRepository(first, calendar);
    final draft = validDraft('v2')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '100',
          costText: '12',
        ),
      ];
    await firstRepository.commitSetup(
      commit: draft.validate().commit!,
      setupSessionId: 'v2',
      nowUtc: fixedNow,
    );
    await first.raw.execute('DROP TABLE fund_nav_cache');
    await first.raw.execute('DROP TABLE ui_preferences');
    await first.raw.execute(
      'ALTER TABLE schedule_versions DROP COLUMN alternation_json',
    );
    await first.raw.execute('PRAGMA user_version = 2');
    await first.close();

    final database = await AppDatabase.open(
      factory: databaseFactoryFfiNoIsolate,
      path: path,
      calendar: calendar,
    );
    addTearDown(database.close);
    final state =
        await LedgerRepository(database, calendar).read(nowUtc: fixedNow);
    expect(state.holdings.single.instrumentId, 'CN.SZ.000001');
    expect(state.salaryVersions, hasLength(1));
    expect(state.schedules, hasLength(1));
    final tables = await database.raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, containsAll(['fund_nav_cache', 'ui_preferences']));
    final columns = await database.raw.rawQuery(
      'PRAGMA table_info(schedule_versions)',
    );
    expect(
      columns.any((column) => column['name'] == 'alternation_json'),
      isTrue,
    );
  });

  FundNavSnapshot nav({
    String code = '000001',
    String? navCny = '1.2356',
    String? navDate = '2026-11-09',
    String? previousNav = '1.2256',
    String? previousDate = '2026-11-06',
    DateTime? fetchedAt,
    int? revision,
    FundEligibility eligibility = FundEligibility.supported,
  }) =>
      FundNavSnapshot(
        instrumentId: 'FUND.CN.$code',
        navCny: navCny == null ? null : Rational.parse(navCny),
        navDate: navDate == null ? null : LocalDate.parse(navDate),
        previousNavCny:
            previousNav == null ? null : Rational.parse(previousNav),
        previousNavDate:
            previousDate == null ? null : LocalDate.parse(previousDate),
        actionStatus: FundActionStatus.none,
        fundCalendar: FundCalendarKind.mainland,
        eligibility: eligibility,
        fetchedAtUtc: fetchedAt ?? fixedNow,
        publishedAtUtc: null,
        source: 'test',
        sourceRevision: revision,
        quality: QuoteQuality.eod,
        sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
      );

  test('fund NAVs round-trip with dates, baseline and event state', () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav()]);
    final state = await repository.read(nowUtc: fixedNow);
    final stored = state.fundNavs['FUND.CN.000001']!;
    expect(stored.navCny, Rational.parse('1.2356'));
    expect(stored.navDate, LocalDate(2026, 11, 9));
    expect(stored.previousNavCny, Rational.parse('1.2256'));
    expect(stored.previousNavDate, LocalDate(2026, 11, 6));
    expect(stored.actionStatus, FundActionStatus.none);
    expect(stored.fundCalendar, FundCalendarKind.mainland);
    expect(stored.eligibility, FundEligibility.supported);
    expect(stored.publishedAtUtc, isNull);
    expect(stored.sourceRevision, isNull);
  });

  test('older NAV dates never overwrite newer ones', () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav(navDate: '2026-11-09')]);
    await repository.saveFundNavs([
      nav(navCny: '1.1000', navDate: '2026-11-06', previousDate: '2026-11-05'),
    ]);
    var state = await repository.read(nowUtc: fixedNow);
    expect(state.fundNavs['FUND.CN.000001']!.navCny, Rational.parse('1.2356'));
    expect(state.fundNavs['FUND.CN.000001']!.navDate, LocalDate(2026, 11, 9));
  });

  test('same-date revisions and fetch generations order the cache', () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav(navCny: '1.2356', revision: 2)]);
    await repository.saveFundNavs([nav(navCny: '1.1000', revision: 1)]);
    var stored = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    expect(stored.navCny, Rational.parse('1.2356'));

    await repository.saveFundNavs([nav(navCny: '1.3000', revision: 3)]);
    stored = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    expect(stored.navCny, Rational.parse('1.3'));

    // No upstream revision: a late response with an earlier fetch time cannot
    // overwrite the newer result.
    final newer = fixedNow.add(const Duration(minutes: 5));
    final older = fixedNow.add(const Duration(minutes: 1));
    await repository.saveFundNavs([
      nav(navCny: '1.4000', fetchedAt: newer),
    ]);
    await repository.saveFundNavs([
      nav(navCny: '1.0000', fetchedAt: older),
    ]);
    stored = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    expect(stored.navCny, Rational.parse('1.4'));

    await repository.saveFundNavs([
      nav(navCny: '1.4100', fetchedAt: newer.add(const Duration(minutes: 1))),
    ]);
    stored = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    expect(stored.navCny, Rational.parse('1.41'));
  });

  test('an eligibility-only refresh keeps the cached NAV and fetch time',
      () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav()]);
    final before = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    await repository.saveFundNavs([
      nav(
        navCny: null,
        navDate: null,
        previousNav: null,
        previousDate: null,
        fetchedAt: fixedNow.add(const Duration(hours: 2)),
        eligibility: FundEligibility.unsupported,
      ),
    ]);
    final after = (await repository.read(nowUtc: fixedNow))
        .fundNavs['FUND.CN.000001']!;
    expect(after.eligibility, FundEligibility.unsupported);
    expect(after.navCny, Rational.parse('1.2356'));
    expect(after.navDate, before.navDate);
    expect(after.fetchedAtUtc, before.fetchedAtUtc);
  });

  test('the pending flag is persisted for offline fund saves', () async {
    final repository = await openMemory();
    final validation = validDraft('fund-pending').validate();
    final committed = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'fund-pending',
      nowUtc: fixedNow,
    );
    final updated = await repository.upsertHolding(
      expectedRevision: committed.settings.ledgerRevision,
      instrumentId: 'FUND.CN.000001',
      quantity: Rational.parse('1000.25'),
      costPerUnit: Rational.parse('1.2'),
      name: '',
      pendingQuote: true,
      nowUtc: fixedNow,
    );
    expect(updated.holdings.single.pendingQuote, isTrue);
  });

  test('FND-01 a stock and a fund with the same code coexist', () async {
    final repository = await openMemory();
    final draft = validDraft('same-code')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          name: '平安银行',
          quantityText: '100',
          costText: '12',
        ),
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          name: '华夏成长混合',
          quantityText: '1000.2500',
          costText: '1.2000',
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    final committed = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'same-code',
      nowUtc: fixedNow,
    );
    expect(committed.holdings, hasLength(2));
    expect(
      committed.holdings.map((holding) => holding.instrumentId).toSet(),
      {'CN.SZ.000001', 'FUND.CN.000001'},
    );
    expect(committed.instrumentNames['CN.SZ.000001'], '平安银行');
    expect(committed.instrumentNames['FUND.CN.000001'], '华夏成长混合');

    await repository.saveQuotes([
      Quote(
        instrumentId: 'CN.SZ.000001',
        priceCny: Rational.parse('12.05'),
        baselineCny: Rational.parse('12.4'),
        quoteAtUtc: fixedNow,
        fetchedAtUtc: fixedNow,
        tradingDate: LocalDate(2026, 11, 4),
        dayBasis: QuoteDayBasis.exchangeTradingDay,
        marketState: MarketState.open,
        quality: QuoteQuality.live,
        source: 'test',
        sourceRevision: 1,
      ),
    ]);
    await repository.saveFundNavs([
      nav(),
    ]);
    final state = await repository.read(nowUtc: fixedNow);
    final stock = state.holdings.firstWhere(
      (holding) => holding.instrumentId == 'CN.SZ.000001',
    );
    final fund = state.holdings.firstWhere(
      (holding) => holding.instrumentId == 'FUND.CN.000001',
    );
    expect(stock.quantity, Rational.parse('100'));
    expect(fund.quantity, Rational.parse('1000.25'));
    expect(state.quotes['CN.SZ.000001']!.priceCny, Rational.parse('12.05'));
    expect(state.fundNavs['FUND.CN.000001']!.navCny, Rational.parse('1.2356'));
    expect(state.quotes.containsKey('FUND.CN.000001'), isFalse);
    expect(state.fundNavs.containsKey('CN.SZ.000001'), isFalse);
  });

  test('changing a code closes the old row and inserts the new one atomically',
      () async {
    final repository = await openMemory();
    final draft = validDraft('rename')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '100',
          costText: '12',
        ),
      ];
    final validation = draft.validate();
    final committed = await repository.commitSetup(
      commit: validation.commit!,
      setupSessionId: 'rename',
      nowUtc: fixedNow,
    );
    final renamed = await repository.upsertHolding(
      expectedRevision: committed.settings.ledgerRevision,
      instrumentId: 'FUND.CN.000001',
      quantity: Rational.parse('1000.25'),
      costPerUnit: Rational.parse('1.2'),
      name: '华夏成长混合',
      previousInstrumentId: 'CN.SZ.000001',
      nowUtc: fixedNow.add(const Duration(minutes: 1)),
    );
    final active = renamed.holdings.where(
      (holding) => holding.effectiveToUtc == null,
    );
    expect(active.map((holding) => holding.instrumentId), ['FUND.CN.000001']);
    expect(renamed.holdings, hasLength(2));
    expect(renamed.instrumentNames['FUND.CN.000001'], '华夏成长混合');
  });

  test('a rename into an existing active code aborts the whole transaction',
      () async {
    final repository = await openMemory();
    final draft = validDraft('dup')
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '100',
          costText: '12',
        ),
        const HoldingDraft(
          market: StockMarket.sse,
          code: '600000',
          quantityText: '200',
          costText: '9',
        ),
      ];
    final committed = await repository.commitSetup(
      commit: draft.validate().commit!,
      setupSessionId: 'dup',
      nowUtc: fixedNow,
    );
    await expectLater(
      repository.upsertHolding(
        expectedRevision: committed.settings.ledgerRevision,
        instrumentId: 'CN.SH.600000',
        quantity: Rational.parse('100'),
        costPerUnit: Rational.parse('12'),
        previousInstrumentId: 'CN.SZ.000001',
        nowUtc: fixedNow,
      ),
      throwsA(isA<DuplicateHoldingException>()),
    );
    final state = await repository.read(nowUtc: fixedNow);
    final activeIds = state.holdings
        .where((holding) => holding.effectiveToUtc == null)
        .map((holding) => holding.instrumentId)
        .toSet();
    expect(activeIds, {'CN.SZ.000001', 'CN.SH.600000'});
    expect(state.settings.ledgerRevision, committed.settings.ledgerRevision);
  });

  test('clearing removes fund NAV cache rows too', () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav()]);
    final cleared = await repository.clearAll(nowUtc: fixedNow);
    expect(cleared.fundNavs, isEmpty);
    expect(await repository.oldestFundFetchedAt(['FUND.CN.000001']), isNull);
  });

  test('oldestFundFetchedAt reports the gating input', () async {
    final repository = await openMemory();
    await repository.saveFundNavs([nav()]);
    final oldest = await repository.oldestFundFetchedAt(['FUND.CN.000001']);
    expect(oldest, fixedNow);
    expect(
      await repository.oldestFundFetchedAt(
        ['FUND.CN.000001', 'FUND.CN.110022'],
      ),
      isNull,
    );
  });

  group('HOME-DUAL-10 local display preference', () {
    test('defaults to both and writing it never bumps the ledger revision',
        () async {
      final repository = await openMemory();
      final validation = housingDraft('home-metrics').validate();
      final committed = await repository.commitSetup(
        commit: validation.commit!,
        setupSessionId: 'home-metrics',
        nowUtc: fixedNow,
      );
      final store = SqliteHomeMetricsPreferenceStore(repository.database);

      expect(await store.read(), HomeMetricsMode.both);
      await store.write(HomeMetricsMode.time);
      expect(await store.read(), HomeMetricsMode.time);
      await store.write(HomeMetricsMode.balance);
      expect(await store.read(), HomeMetricsMode.balance);

      final after = await repository.read(nowUtc: fixedNow);
      expect(after.settings.ledgerRevision, committed.settings.ledgerRevision);
      expect(after.settings.hasCompletedOnboarding, isTrue);
    });

    test('an unknown stored value falls back to both', () async {
      final repository = await openMemory();
      await repository.database.raw.insert('ui_preferences', {
        'key': SqliteHomeMetricsPreferenceStore.key,
        'value': 'sideways',
        'updated_at': fixedNow.toIso8601String(),
      });
      final store = SqliteHomeMetricsPreferenceStore(repository.database);
      expect(await store.read(), HomeMetricsMode.both);
    });

    test('clearing the ledger also resets the layout preference', () async {
      final repository = await openMemory();
      final store = SqliteHomeMetricsPreferenceStore(repository.database);
      await store.write(HomeMetricsMode.balance);
      expect(await store.read(), HomeMetricsMode.balance);

      await repository.clearAll(nowUtc: fixedNow);
      expect(await store.read(), HomeMetricsMode.both);
    });

    test('v4 databases upgrade to v5 with an empty preference table', () async {
      initSqliteFfi();
      final path = newDatabasePath();
      final first = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
        calendar: calendar,
      );
      final firstRepository = LedgerRepository(first, calendar);
      final draft = validDraft('v4')
        ..holdings = [
          const HoldingDraft(
            market: StockMarket.szse,
            code: '000001',
            quantityText: '100',
            costText: '12',
          ),
        ];
      await firstRepository.commitSetup(
        commit: draft.validate().commit!,
        setupSessionId: 'v4',
        nowUtc: fixedNow,
      );
      await first.raw.execute('DROP TABLE ui_preferences');
      await first.raw.execute('PRAGMA user_version = 4');
      await first.close();

      final database = await AppDatabase.open(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
        calendar: calendar,
      );
      addTearDown(database.close);
      final store = SqliteHomeMetricsPreferenceStore(database);
      expect(await store.read(), HomeMetricsMode.both);
      final table = await database.raw.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ui_preferences'",
      );
      expect(table, isNotEmpty);
      final state = await LedgerRepository(database, calendar)
          .read(nowUtc: fixedNow);
      expect(state.holdings.single.instrumentId, 'CN.SZ.000001');
      expect(state.settings.ledgerRevision, 1);
    });
  });
}
