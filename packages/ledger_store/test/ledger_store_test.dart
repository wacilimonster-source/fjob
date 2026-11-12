import 'dart:async';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

const sourceId = '29a28961-3eb3-46ed-b4a3-f3a45c6e7fe7';
final now = DateTime.utc(2026, 11, 4, 6, 36);
final calendar = BusinessCalendar.shanghai;

LedgerBundle external({int revision = 5, String ledgerId = sourceId, LedgerState? ledger}) {
  final state = ledger ?? buildDemoLedger(calendar, now);
  return LedgerBundle.fromLedger(state.copyWith(settings: state.settings.copyWith(ledgerRevision: revision)),
    ledgerId: ledgerId, exportedAt: now, appVersion: '0.2.0', platform: 'android');
}

void main() {
  sqfliteFfiInit();
  late AppDatabase db;
  late LedgerRepository repository;

  setUp(() async {
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, calendar: calendar);
    repository = LedgerRepository(db, calendar);
  });
  tearDown(() async => db.close());

  Future<LedgerBundle> export() => repository.exportBundle(exportedAt: now, appVersion: '0.2.0', platform: 'windows');

  test('replace is atomic, bumps above both ends, preserves UI, exports no caches', () async {
    final originalId = await db.ledgerId;
    await db.raw.update('app_settings', {'widget_privacy': 1, 'tone': 'harsh'}, where: 'id = 1');
    final preferences = SqliteHomeMetricsPreferenceStore(db);
    await preferences.write(HomeMetricsMode.time);
    await repository.saveQuotes(buildDemoLedger(calendar, now).quotes.values.toList());
    final result = await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    expect(result.settings.ledgerRevision, 6);
    expect(await db.ledgerId, sourceId);
    expect(result.settings.widgetPrivacy, isTrue);
    expect(result.settings.tone, AppTone.harsh);
    expect(await preferences.read(), HomeMetricsMode.time);
    expect(result.quotes, isNotEmpty); // local cache was not imported or erased
    final first = await export();
    final second = await export();
    expect(second.encode(), first.encode());
    expect((await repository.read()).settings.ledgerRevision, 6);
    expect(first.ledger.quotes, isEmpty);
    final backups = await repository.listBackups();
    expect(backups, hasLength(1));
    expect(backups.single.ledgerId, originalId);
    final saved = LedgerBundle.decode((await db.raw.query('ledger_backups')).single['bundle_json']! as String);
    expect(saved.ledger.quotes, isEmpty);
    expect(saved.toJson()['settings'], {'onboardingCompletedAt': null});
  });

  test('same-ledger old revisions explicitly rejected for replace and merge', () async {
    await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    final before = (await export()).encode();
    for (final mode in LedgerImportMode.values) {
      await expectLater(repository.importBundle(external(), expectedRevision: 6, nowUtc: now, mode: mode),
        throwsA(isA<OlderLedgerRevisionException>()));
    }
    expect((await export()).encode(), before);
    expect(await repository.listBackups(), hasLength(1));
  });

  test('expectedRevision checked inside transaction before writes', () async {
    final before = await export();
    await expectLater(repository.importBundle(external(), expectedRevision: 1, nowUtc: now), throwsA(isA<RevisionConflictException>()));
    expect((await export()).encode(), before.encode());
    expect(await repository.listBackups(), isEmpty);
    final results = await Future.wait([
      repository.importBundle(external(), expectedRevision: 0, nowUtc: now).then<Object>((v) => v).catchError((Object e) => e),
      repository.importBundle(external(), expectedRevision: 0, nowUtc: now).then<Object>((v) => v).catchError((Object e) => e),
    ]);
    expect(results.whereType<LedgerState>(), hasLength(1));
    expect(results.whereType<RevisionConflictException>(), hasLength(1));
  });

  test('late SQL failure rolls back rows, revision, ID and backup/pruning', () async {
    for (var i = 0; i < 5; i++) {
      final revision = (await repository.read()).settings.ledgerRevision;
      await repository.importBundle(external(revision: revision + 1), expectedRevision: revision, nowUtc: now);
    }
    final before = (await export()).encode();
    final backupIds = (await repository.listBackups()).map((v) => v.id).toList();
    await db.raw.execute('''CREATE TRIGGER fail_bill BEFORE INSERT ON monthly_bills
      BEGIN SELECT RAISE(ABORT, 'injected write failure'); END''');
    await expectLater(repository.importBundle(external(revision: 100,
      ledgerId: '6ed6049e-d4c5-421d-b97e-062f610d5852'), expectedRevision: 10, nowUtc: now), throwsA(isA<DatabaseException>()));
    expect((await export()).encode(), before);
    expect((await repository.listBackups()).map((v) => v.id).toList(), backupIds);
    expect(await db.ledgerId, sourceId);
    await db.raw.execute('DROP TRIGGER fail_bill');
  });

  test('only newest five backups retained; explicit restore is monotonic and reversible', () async {
    for (var i = 0; i < 7; i++) {
      final revision = (await repository.read()).settings.ledgerRevision;
      await repository.importBundle(external(revision: revision + 1), expectedRevision: revision,
        nowUtc: now.subtract(Duration(days: i))); // recency must not sort by clock
    }
    final backups = await repository.listBackups();
    expect(backups, hasLength(5));
    expect(backups.first.id, 7);
    expect(backups.last.id, 3);
    await expectLater(repository.restoreBackup(backups.last.id, expectedRevision: 0, nowUtc: now), throwsA(isA<RevisionConflictException>()));
    final restored = await repository.restoreBackup(backups.last.id, expectedRevision: 14, nowUtc: now);
    expect(restored.settings.ledgerRevision, 15);
    expect(await repository.listBackups(), hasLength(5));
    expect((await repository.listBackups()).first.ledgerRevision, 14);
    await expectLater(repository.restoreBackup(-1, expectedRevision: 15, nowUtc: now), throwsStateError);
  });

  test('restore corrupted backup fails without changing any content', () async {
    await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    final before = (await export()).encode();
    final backup = (await repository.listBackups()).single;
    await db.raw.update('ledger_backups', {'bundle_json': '{}'}, where: 'id = ?', whereArgs: [backup.id]);
    await expectLater(repository.restoreBackup(backup.id, expectedRevision: 6, nowUtc: now), throwsFormatException);
    expect((await export()).encode(), before);
  });

  test('merge rejects same-ID edits and validates non-ID temporal collisions', () async {
    await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    final before = (await export()).encode();
    Holding stock(String id) => Holding(id: id, instrumentId: 'CN.SZ.000001',
      quantity: Rational.one, costPerUnit: Rational.one, effectiveFromUtc: now);
    final conflicting = LedgerState.empty().copyWith(holdings: [stock('demo-stock')]);
    await expectLater(repository.importBundle(external(revision: 8, ledger: conflicting),
      expectedRevision: 6, nowUtc: now, mode: LedgerImportMode.merge), throwsA(isA<LedgerMergeConflictException>()));
    final overlapping = LedgerState.empty().copyWith(holdings: [stock('different-id')]);
    await expectLater(repository.importBundle(external(revision: 8, ledger: overlapping),
      expectedRevision: 6, nowUtc: now, mode: LedgerImportMode.merge), throwsFormatException);
    expect((await export()).encode(), before);
    expect(await repository.listBackups(), hasLength(1));
  });

  test('nonconflicting merge retains local identity, union and unknown fund valuation', () async {
    await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    final extra = LedgerState.empty().copyWith(holdings: [Holding(id: 'fund', instrumentId: 'FUND.CN.000001',
      quantity: Rational.parse('1.2345'), costPerUnit: Rational.parse('0.3456'), effectiveFromUtc: now)]);
    final result = await repository.importBundle(external(revision: 10, ledger: extra,
      ledgerId: '6ed6049e-d4c5-421d-b97e-062f610d5852'), expectedRevision: 6, nowUtc: now, mode: LedgerImportMode.merge);
    expect(result.settings.ledgerRevision, 11);
    expect(await db.ledgerId, sourceId);
    expect(result.holdings, hasLength(3));
    expect(result.fundNavs, isEmpty);
    final snapshot = DashboardCalculator(calendar).calculate(result.toCalculationInput(calendar: calendar, nowUtc: now));
    expect(snapshot.fundDaily, isNull);
  });

  test('configuration save preserves closed history, all bill months and overrides', () async {
    await repository.importBundle(external(), expectedRevision: 0, nowUtc: now);
    await repository.replaceCompensation(expectedRevision: 6, monthlySalary: Rational.parse('13000'),
      week: WeekTemplate.standardOffice(), effectiveFrom: const LocalDate(2026, 11, 10), nowUtc: now);
    final edited = LedgerState.empty().copyWith(overrides: [const ScheduleOverride(
      localDate: LocalDate(2026, 11, 11), paidIntervals: [], reason: 'rest')]);
    await repository.saveConfiguration(configuration: edited, expectedRevision: 7, nowUtc: now);
    final more = LedgerState.empty().copyWith(bills: [MonthlyBill(expenseId: 'demo-car', kind: ExpenseKind.car,
      month: const LocalDate(2026, 12, 1), monthlyAmountCny: null, status: BillStatus.missing)]);
    final result = await repository.saveConfiguration(configuration: more, expectedRevision: 8, nowUtc: now);
    expect(result.settings.ledgerRevision, 9);
    expect(result.salaryVersions, hasLength(2));
    expect(result.schedules, hasLength(2));
    expect(result.salaryVersions.where((v) => v.effectiveToUtc != null), hasLength(1));
    expect(result.bills, hasLength(3));
    expect(result.overrides.single.localDate, const LocalDate(2026, 11, 11));
    expect(result.settings.hasCompletedOnboarding, isTrue);
    final before = (await export()).encode();
    await expectLater(repository.saveConfiguration(configuration: more, expectedRevision: 8, nowUtc: now), throwsA(isA<RevisionConflictException>()));
    final invalid = LedgerState.empty().copyWith(holdings: [Holding(id: 'bad', instrumentId: 'UNKNOWN',
      quantity: Rational.one, costPerUnit: Rational.one, effectiveFromUtc: now)]);
    await expectLater(repository.saveConfiguration(configuration: invalid, expectedRevision: 9, nowUtc: now), throwsFormatException);
    expect((await export()).encode(), before);
  });

  test('manual compensation save makes a standalone ledger usable', () async {
    final result = await repository.replaceCompensation(
      expectedRevision: 0,
      monthlySalary: Rational.parse('12000'),
      week: WeekTemplate.standardOffice(),
      effectiveFrom: const LocalDate(2026, 11, 2),
      nowUtc: now,
    );
    expect(result.salaryVersions, hasLength(1));
    expect(result.schedules, hasLength(1));
    expect(result.settings.hasCompletedOnboarding, isTrue,
        reason: '保存工资+排班后应记录为已完成配置');
    expect(result.isConfigured, isTrue,
        reason: 'PC 不导入手机账本、手动保存后必须直接可用');
  });

  test('commitSetup optional expectedRevision and retry compatibility', () async {
    final draft = SetupDraft.fresh('session', today: const LocalDate(2026, 11, 4))..salaryText = '12000';
    final commit = draft.validate().commit!;
    await expectLater(repository.commitSetup(commit: commit, setupSessionId: 'session', nowUtc: now,
      expectedRevision: 1), throwsA(isA<RevisionConflictException>()));
    expect((await repository.read()).salaryVersions, isEmpty);
    final result = await repository.commitSetup(commit: commit, setupSessionId: 'session', nowUtc: now, expectedRevision: 0);
    expect(result.settings.ledgerRevision, 1);
    final retry = await repository.commitSetup(commit: commit, setupSessionId: 'session', nowUtc: now);
    expect(retry.settings.ledgerRevision, 1);
    expect(retry.salaryVersions, hasLength(1));
    expect((await export()).ledger.salaryVersions, hasLength(1));
  });

  test('schema v5 migration preserves every row, preferences and stable UUID across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('fjob-v5-');
    final path = '${directory.path}/ledger.sqlite';
    AppDatabase? fileDb;
    try {
      fileDb = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      final fileRepo = LedgerRepository(fileDb, calendar);
      await fileRepo.importBundle(external(), expectedRevision: 0, nowUtc: now);
      await SqliteHomeMetricsPreferenceStore(fileDb).write(HomeMetricsMode.balance);
      await fileDb.raw.execute('DROP TABLE ledger_backups');
      await fileDb.raw.execute('DROP TABLE ledger_metadata');
      await fileDb.raw.setVersion(5);
      await fileDb.close();
      fileDb = null;
      fileDb = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      expect(await fileDb.raw.getVersion(), 6);
      final id = await fileDb.ledgerId;
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      final ledger = await LedgerRepository(fileDb, calendar).read();
      expect(ledger.settings.ledgerRevision, 6);
      expect(ledger.holdings, hasLength(2));
      expect(ledger.bills, hasLength(2));
      expect(await SqliteHomeMetricsPreferenceStore(fileDb).read(), HomeMetricsMode.balance);
      await fileDb.close();
      fileDb = null;
      fileDb = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      expect(await fileDb.ledgerId, id);
      expect(await LedgerRepository(fileDb, calendar).listBackups(), isEmpty);
    } finally {
      await fileDb?.close();
      await directory.delete(recursive: true);
    }
  });

  test('pre-versioned mortgage config migrates through v6 without loss', () async {
    final directory = await Directory.systemTemp.createTemp('fjob-v0-');
    final path = '${directory.path}/ledger.sqlite';
    AppDatabase? migrated;
    try {
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute('CREATE TABLE legacy_config (salary_cny TEXT, mortgage_cny TEXT, mortgage_principal_cny TEXT)');
      await legacy.insert('legacy_config', {'salary_cny': '12000', 'mortgage_cny': '4800', 'mortgage_principal_cny': null});
      await legacy.close();
      migrated = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      final ledger = await LedgerRepository(migrated, calendar).read();
      expect(ledger.salaryVersions.single.monthlyNetCny, Rational.parse('12000'));
      expect(ledger.housingVersions.single.mode, HousingMode.mortgage);
      expect(ledger.bills.single.principalCny, isNull);
      expect(await migrated.raw.getVersion(), 6);
      expect(await migrated.ledgerId, isNotEmpty);
    } finally {
      await migrated?.close();
      await directory.delete(recursive: true);
    }
  });

  test('a second connection reading concurrently never blocks an import', () async {
    final directory = await Directory.systemTemp.createTemp('fjob-concurrent-');
    final path = '${directory.path}/ledger.sqlite';
    AppDatabase? writer;
    AppDatabase? reader;
    try {
      writer = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      reader = await AppDatabase.open(factory: databaseFactoryFfi, path: path, calendar: calendar);
      final readerRepo = LedgerRepository(reader, calendar);
      // The PC card engine reads the shared file on its own connection while
      // the main engine writes; separate connections + WAL must not misuse.
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) async {
        try {
          await readerRepo.read(nowUtc: now);
        } on Object {
          // A transient busy is acceptable; the import must still commit.
        }
      });
      final writerRepo = LedgerRepository(writer, calendar);
      final result = await writerRepo.importBundle(external(), expectedRevision: 0, nowUtc: now);
      timer.cancel();
      expect(result.settings.ledgerRevision, 6);
      expect(result.isConfigured, isTrue);
      expect(await writerRepo.listBackups(), hasLength(1));
    } finally {
      await reader?.close();
      await writer?.close();
      await directory.delete(recursive: true);
    }
  });
}
