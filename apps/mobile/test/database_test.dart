import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todayagain/data/app_database.dart';
import 'package:todayagain/data/ledger_repository.dart';
import 'package:todayagain/domain/ledger.dart';

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
}
