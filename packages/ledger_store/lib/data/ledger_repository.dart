/// Reads and writes the versioned local ledger.
library;

import 'dart:convert';
import 'dart:math';

import 'package:finance_core/finance_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'package:ledger_model/ledger_model.dart';
import 'app_database.dart';

part 'ledger_repository_bundle.dart';

final class RevisionConflictException implements Exception {
  const RevisionConflictException(this.expected, this.actual);

  final int expected;
  final int actual;

  @override
  String toString() => 'ledger revision changed ($expected != $actual)';
}

final class DuplicateHoldingException implements Exception {
  const DuplicateHoldingException(this.instrumentId);

  final String instrumentId;

  @override
  String toString() => '持仓已存在：$instrumentId';
}

final class LedgerRepository {
  LedgerRepository(this.database, this.calendar);

  final AppDatabase database;
  final BusinessCalendar calendar;

  static final Random _random = Random.secure();

  String _newId(String prefix) {
    final suffix = List<int>.generate(8, (_) => _random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  Future<LedgerState> read({DateTime? nowUtc}) => database.transaction(
        (txn) => _read(txn, nowUtc: nowUtc),
      );

  Future<LedgerState> _read(DatabaseExecutor db, {
    DateTime? nowUtc,
    bool includeMarketData = true,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final settingsRows = await db.query('app_settings', where: 'id = 1');
    final settingsRow = settingsRows.isEmpty ? null : settingsRows.first;

    final scheduleRows = await db.query('schedule_versions');
    final schedules = <String, ScheduleVersion>{};
    for (final row in scheduleRows) {
      final json = jsonDecode(row['weekly_json']! as String);
      if (json is! Map) continue;
      final from = DateTime.parse(row['effective_from']! as String);
      final to = LedgerJson.dateFromIso(row['effective_to']);
      if (to != null && !to.isAfter(from)) continue;
      final alternationRaw = row['alternation_json'];
      WeekAlternation? alternation;
      if (alternationRaw is String && alternationRaw.isNotEmpty) {
        final decoded = jsonDecode(alternationRaw);
        if (decoded is Map) {
          alternation = ScheduleCodec.decodeAlternation(
            decoded.cast<String, dynamic>(),
          );
        }
      }
      schedules[row['id']! as String] = ScheduleVersion(
        id: row['id']! as String,
        timezone: row['timezone']! as String,
        week: ScheduleCodec.decodeWeek(json.cast<String, dynamic>()),
        alternation: alternation,
        effectiveFromUtc: from,
        effectiveToUtc: to,
        calendarSourceVersion:
            (row['calendar_source_version'] as String?) ?? 'WORK_CN@builtin',
      );
    }

    final salaryRows = await db.query('salary_versions');
    final salaries = <SalaryVersion>[];
    for (final row in salaryRows) {
      final from = DateTime.parse(row['effective_from']! as String);
      final to = LedgerJson.dateFromIso(row['effective_to']);
      if (to != null && !to.isAfter(from)) continue;
      salaries.add(
        SalaryVersion(
          id: row['id']! as String,
          monthlyNetCny: Rational.parse(row['monthly_net_cny']! as String),
          effectiveFromUtc: from,
          effectiveToUtc: to,
          scheduleVersionId: row['schedule_version_id']! as String,
        ),
      );
    }

    final overrideRows = await db.query('schedule_day_overrides');
    final overrides = [
      for (final row in overrideRows)
        if (LocalDate.tryParse(row['local_date'] as String?) != null)
          ScheduleOverride(
            localDate: LocalDate.parse(row['local_date']! as String),
            paidIntervals: ScheduleCodec.decodeOverrides(
              row['paid_intervals_json']! as String,
            ),
            reason: (row['reason'] as String?) ?? 'override',
            confirmed: LedgerJson.asBool(row['confirmed'], fallback: true),
          ),
    ];

    final holdingRows = await db.query('holding_versions');
    final holdings = [
      for (final row in holdingRows)
        Holding(
          id: row['id']! as String,
          instrumentId: row['instrument_id']! as String,
          quantity: Rational.parse(row['quantity']! as String),
          costPerUnit: Rational.parse(row['cost_per_unit']! as String),
          effectiveFromUtc: DateTime.parse(row['effective_from']! as String),
          effectiveToUtc: LedgerJson.dateFromIso(row['effective_to']),
          pendingQuote: LedgerJson.asBool(row['pending_quote']),
        ),
    ];

    final housingRows = await db.query('housing_plan_versions');
    final housingVersions = [
      for (final row in housingRows)
        HousingVersion(
          id: row['id']! as String,
          mode: HousingMode.values.firstWhere(
            (value) => value.name == row['mode'],
            orElse: () => HousingMode.none,
          ),
          effectiveFromUtc: DateTime.parse(row['effective_from']! as String),
          effectiveToUtc: LedgerJson.dateFromIso(row['effective_to']),
        ),
    ];

    final carRows = await db.query('car_plan_versions');
    final carVersions = [
      for (final row in carRows)
        CarVersion(
          id: row['id']! as String,
          enabled: LedgerJson.asBool(row['enabled'], fallback: true),
          effectiveFromUtc: DateTime.parse(row['effective_from']! as String),
          effectiveToUtc: LedgerJson.dateFromIso(row['effective_to']),
        ),
    ];

    final billRows = await db.query('monthly_bills');
    final bills = [
      for (final row in billRows)
        if (LocalDate.tryParse(row['month'] as String?) != null)
          MonthlyBill(
            expenseId: row['expense_id']! as String,
            kind: ExpenseKind.values.firstWhere(
              (value) => value.name == row['kind'],
              orElse: () => ExpenseKind.housing,
            ),
            month: LocalDate.parse(row['month']! as String),
            monthlyAmountCny:
                LedgerJson.moneyFromJson(row['monthly_amount_cny']),
            principalCny: LedgerJson.moneyFromJson(row['principal_cny']),
            status: BillStatus.values.firstWhere(
              (value) => value.name == row['status'],
              orElse: () => BillStatus.confirmed,
            ),
            revision: LedgerJson.asInt(row['revision'], fallback: 1),
            note: row['note'] as String?,
          ),
    ];

    final quoteRows = includeMarketData ? await db.query('quote_cache') : <Map<String, Object?>>[];
    final quotes = <String, Quote>{
      for (final row in quoteRows)
        if (LocalDate.tryParse(row['trading_date'] as String?) != null)
          row['instrument_id']! as String: Quote(
            instrumentId: row['instrument_id']! as String,
            priceCny: LedgerJson.moneyFromJson(row['price_cny']),
            baselineCny: LedgerJson.moneyFromJson(row['baseline_cny']),
            quoteAtUtc: DateTime.parse(row['quote_at']! as String),
            fetchedAtUtc: DateTime.parse(row['fetched_at']! as String),
            tradingDate: LocalDate.parse(row['trading_date']! as String),
            dayBasis: QuoteDayBasis.values.firstWhere(
              (value) => value.name == row['day_basis'],
              orElse: () => QuoteDayBasis.exchangeTradingDay,
            ),
            marketState: MarketState.values.firstWhere(
              (value) => value.name == row['market_state'],
              orElse: () => MarketState.unknown,
            ),
            quality: QuoteQuality.values.firstWhere(
              (value) => value.name == row['quality'],
              orElse: () => QuoteQuality.unavailable,
            ),
            source: (row['source'] as String?) ?? 'unknown',
            sourceRevision:
                LedgerJson.asInt(row['source_revision'], fallback: 0),
            delaySeconds: row['delay_seconds'] as int?,
          ),
    };

    final fundRows = includeMarketData ? await db.query('fund_nav_cache') : <Map<String, Object?>>[];
    final fundNavs = <String, FundNavSnapshot>{};
    for (final row in fundRows) {
      final instrumentId = row['instrument_id'] as String?;
      if (instrumentId == null) continue;
      final navDate = LocalDate.tryParse(row['nav_date'] as String?);
      final nav = LedgerJson.moneyFromJson(row['nav_cny']);
      final previousNavDate =
          LocalDate.tryParse(row['previous_nav_date'] as String?);
      final previousNav =
          LedgerJson.moneyFromJson(row['previous_nav_cny']);
      fundNavs[instrumentId] = FundNavSnapshot(
        instrumentId: instrumentId,
        // A value without its date is not a usable NAV.
        navCny: navDate == null ? null : nav,
        navDate: navDate,
        previousNavCny: previousNavDate == null ? null : previousNav,
        previousNavDate: previousNavDate,
        actionStatus: FundActionStatus.values.firstWhere(
          (value) => value.name == row['action_status'],
          orElse: () => FundActionStatus.unknown,
        ),
        fundCalendar: FundCalendarKind.values.firstWhere(
          (value) => value.name == row['fund_calendar'],
          orElse: () => FundCalendarKind.unknown,
        ),
        eligibility: FundEligibility.values.firstWhere(
          (value) => value.name == row['eligibility'],
          orElse: () => FundEligibility.unknown,
        ),
        fetchedAtUtc: DateTime.parse(row['fetched_at']! as String),
        publishedAtUtc: LedgerJson.dateFromIso(row['published_at']),
        source: (row['source'] as String?) ?? 'unknown',
        sourceRevision: row['source_revision'] as int?,
        quality: QuoteQuality.values.firstWhere(
          (value) => value.name == row['quality'],
          orElse: () => QuoteQuality.unavailable,
        ),
        sourceLicenseStatus: SourceLicenseStatus.values.firstWhere(
          (value) => value.name == row['source_license_status'],
          orElse: () => SourceLicenseStatus.unknown,
        ),
      );
    }

    final calendarRows = includeMarketData ? await db.query(
      'market_calendar_days',
      where: 'market = ?',
      whereArgs: ['SSE'],
    ) : <Map<String, Object?>>[];
    final days = <LocalDate, MarketDayStatus>{};
    for (final row in calendarRows) {
      final date = LocalDate.tryParse(row['local_date'] as String?);
      if (date == null) continue;
      days[date] = MarketDayStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => MarketDayStatus.unknown,
      );
    }
    final fundCalendarRows = includeMarketData ? await db.query(
      'market_calendar_days',
      where: 'market = ?',
      whereArgs: ['FUND_CN'],
    ) : <Map<String, Object?>>[];
    final fundDays = <LocalDate, MarketDayStatus>{};
    for (final row in fundCalendarRows) {
      final date = LocalDate.tryParse(row['local_date'] as String?);
      if (date == null) continue;
      fundDays[date] = MarketDayStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => MarketDayStatus.unknown,
      );
    }
    final sgeRows = includeMarketData ? await db.query(
      'market_calendar_days',
      where: 'market = ? AND local_date = ?',
      whereArgs: ['SGE', calendar.dateOf(now).toIsoString()],
    ) : <Map<String, Object?>>[];
    final goldSessionActive = sgeRows.isNotEmpty &&
        sgeRows.first['status'] == MarketDayStatus.open.name;

    final directoryRows = includeMarketData ? await db.query('instrument_directory') : <Map<String, Object?>>[];
    final instrumentNames = <String, String>{
      for (final row in directoryRows)
        if ((row['instrument_id'] as String?) != null &&
            (row['name'] as String?)?.isNotEmpty == true)
          row['instrument_id']! as String: row['name']! as String,
    };

    final settings = settingsRow == null
        ? const AppSettings()
        : AppSettings(
            ledgerRevision:
                LedgerJson.asInt(settingsRow['ledger_revision']),
            salaryTimezone:
                (settingsRow['salary_timezone'] as String?) ?? 'Asia/Shanghai',
            theme: ThemeSetting.values.firstWhere(
              (value) => value.name == settingsRow['theme'],
              orElse: () => ThemeSetting.system,
            ),
            motion: MotionSetting.values.firstWhere(
              (value) => value.name == settingsRow['motion'],
              orElse: () => MotionSetting.full,
            ),
            tone: AppTone.values.firstWhere(
              (value) => value.name == settingsRow['tone'],
              orElse: () => AppTone.gentle,
            ),
            widgetPrivacy: LedgerJson.asBool(settingsRow['widget_privacy']),
            onboardingCompletedAt:
                LedgerJson.dateFromIso(settingsRow['onboarding_completed_at']),
            sampleMode: LedgerJson.asBool(settingsRow['sample_mode']),
          );

    return LedgerState(
      settings: settings,
      salaryVersions: salaries,
      schedules: schedules,
      overrides: overrides,
      holdings: holdings,
      housingVersions: housingVersions,
      carVersions: carVersions,
      bills: bills,
      quotes: quotes,
      marketCalendar: MarketCalendar(
        days,
        version: 'SSE@local',
        source: 'market_gateway',
      ),
      fundNavs: fundNavs,
      fundCalendar: MarketCalendar(
        fundDays,
        version: 'FUND_CN@local',
        source: 'market_gateway',
      ),
      instrumentNames: instrumentNames,
      goldReferenceSessionActive: goldSessionActive,
    );
  }

  Future<void> _saveInstrumentNames(
    Transaction txn,
    Map<String, String> names,
    String timestamp,
  ) async {
    for (final entry in names.entries) {
      final name = entry.value.trim();
      if (name.isEmpty) continue;
      await txn.insert(
        'instrument_directory',
        {
          'instrument_id': entry.key,
          'name': name,
          'market': _marketName(entry.key),
          'updated_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static String _marketName(String instrumentId) {
    if (instrumentId.startsWith('CN.SH')) return 'SSE';
    if (instrumentId.startsWith('CN.SZ')) return 'SZSE';
    if (instrumentId.startsWith('CN.BJ')) return 'BSE';
    if (instrumentId.startsWith('GOLD.')) return 'SGE';
    if (instrumentId.startsWith('FUND.CN.')) return 'CN_FUND';
    return 'UNKNOWN';
  }

  /// Closes every version older than [instant] and removes versions that start
  /// at or after it, so a zero-length effective period is never written.
  Future<void> _closeVersions(
    Transaction txn,
    String table,
    DateTime instant, {
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) async {
    final iso = instant.toIso8601String();
    final suffix = extraWhere == null ? '' : ' AND $extraWhere';
    await txn.delete(
      table,
      where: 'effective_from >= ?$suffix',
      whereArgs: [iso, ...extraArgs],
    );
    await txn.update(
      table,
      {'effective_to': iso},
      where: '(effective_to IS NULL OR effective_to > ?) AND effective_from < ?$suffix',
      whereArgs: [iso, iso, ...extraArgs],
    );
  }

  Future<LedgerState> commitSetup({
    required SetupCommit commit,
    required String setupSessionId,
    required DateTime nowUtc,
    bool sampleMode = false,
    bool replaceExisting = false,
    int? expectedRevision,
  }) async {
    final now = nowUtc.toUtc();
    final effectiveFrom = calendar.startOfDayUtc(commit.effectiveDate);
    final billMonth = calendar.dateOf(now).firstOfMonth;
    await database.transaction((txn) async {
      if (expectedRevision != null) {
        await _checkRevision(txn, expectedRevision);
      }
      final existing = await txn.query(
        'setup_commits',
        where: 'setup_session_id = ?',
        whereArgs: [setupSessionId],
      );
      if (existing.isNotEmpty) return;

      final settingsRows = await txn.query('app_settings', where: 'id = 1');
      final revision =
          LedgerJson.asInt(settingsRows.first['ledger_revision']) + 1;
      final timestamp = now.toIso8601String();

      if (replaceExisting) {
        // Re-running onboarding replaces the configuration from the chosen
        // effective date; history stays readable through the closed periods.
        await _closeVersions(txn, 'salary_versions', effectiveFrom);
        await _closeVersions(txn, 'schedule_versions', effectiveFrom);
        await _closeVersions(txn, 'housing_plan_versions', effectiveFrom);
        await _closeVersions(txn, 'car_plan_versions', effectiveFrom);
        await _closeVersions(txn, 'holding_versions', now);
      }

      final scheduleId = _newId('schedule');
      await txn.insert('schedule_versions', {
        'id': scheduleId,
        'timezone': calendar.timezoneName,
        'weekly_json': jsonEncode(ScheduleCodec.encodeWeek(commit.week)),
        'effective_from': effectiveFrom.toIso8601String(),
        'effective_to': null,
        'calendar_source_version': 'WORK_CN@builtin',
        'alternation_json': commit.alternation == null
            ? null
            : jsonEncode(
                ScheduleCodec.encodeAlternation(commit.alternation!),
              ),
        'created_at': timestamp,
      });
      await txn.insert('salary_versions', {
        'id': _newId('salary'),
        'monthly_net_cny': commit.monthlySalary.toCanonicalString(),
        'effective_from': effectiveFrom.toIso8601String(),
        'effective_to': null,
        'schedule_version_id': scheduleId,
        'created_at': timestamp,
      });

      for (final holding in commit.holdings) {
        await txn.insert('holding_versions', {
          'id': _newId('holding'),
          'instrument_id': holding.instrumentId,
          'quantity': holding.quantity.toCanonicalString(),
          'cost_per_unit': holding.costPerUnit.toCanonicalString(),
          'effective_from': timestamp,
          'effective_to': null,
          'pending_quote': holding.pendingQuote ? 1 : 0,
          'created_at': timestamp,
        });
      }
      if (commit.hasGold) {
        await txn.insert('holding_versions', {
          'id': _newId('holding'),
          'instrument_id': goldInstrumentId,
          'quantity': commit.goldQuantity!.toCanonicalString(),
          'cost_per_unit': commit.goldCost!.toCanonicalString(),
          'effective_from': timestamp,
          'effective_to': null,
          'pending_quote': 0,
          'created_at': timestamp,
        });
      }

      await _saveInstrumentNames(
        txn,
        {
          for (final holding in commit.holdings)
            holding.instrumentId: holding.name,
          if (commit.hasGold) goldInstrumentId: goldInstrumentName,
        },
        timestamp,
      );

      final housingId = _newId('housing');
      await txn.insert('housing_plan_versions', {
        'id': housingId,
        'mode': commit.housingMode.name,
        'effective_from': effectiveFrom.toIso8601String(),
        'effective_to': null,
        'created_at': timestamp,
      });
      if (commit.housingMode != HousingMode.none &&
          commit.housingMonthly != null) {
        await txn.insert('monthly_bills', {
          'id': _newId('bill'),
          'expense_id': housingId,
          'kind': ExpenseKind.housing.name,
          'month': billMonth.toIsoString(),
          'monthly_amount_cny': commit.housingMonthly!.toCanonicalString(),
          'principal_cny':
              commit.housingPrincipal?.toCanonicalString(),
          'status': BillStatus.confirmed.name,
          'revision': 1,
          'note': commit.housingMode == HousingMode.rent ? 'rent' : null,
          'updated_at': timestamp,
        });
      }

      final carId = _newId('car');
      await txn.insert('car_plan_versions', {
        'id': carId,
        'enabled': commit.carEnabled ? 1 : 0,
        'effective_from': effectiveFrom.toIso8601String(),
        'effective_to': null,
        'created_at': timestamp,
      });
      if (commit.carEnabled && commit.carMonthly != null) {
        await txn.insert('monthly_bills', {
          'id': _newId('bill'),
          'expense_id': carId,
          'kind': ExpenseKind.car.name,
          'month': billMonth.toIsoString(),
          'monthly_amount_cny': commit.carMonthly!.toCanonicalString(),
          'principal_cny': commit.carPrincipal?.toCanonicalString(),
          'status': BillStatus.confirmed.name,
          'revision': 1,
          'note': null,
          'updated_at': timestamp,
        });
      }

      await txn.insert('setup_commits', {
        'setup_session_id': setupSessionId,
        'committed_at': timestamp,
      });
      await txn.update(
        'app_settings',
        {
          'ledger_revision': revision,
          'widget_privacy': commit.widgetPrivacy ? 1 : 0,
          'onboarding_completed_at': timestamp,
          'sample_mode': sampleMode ? 1 : 0,
        },
        where: 'id = 1',
      );
      await txn.delete(
        'onboarding_drafts',
        where: 'setup_session_id = ?',
        whereArgs: [setupSessionId],
      );
    });
    return read(nowUtc: now);
  }

  Future<int> _bumpRevision(Transaction txn, int expectedRevision) async {
    final rows = await txn.query('app_settings', where: 'id = 1');
    final actual = LedgerJson.asInt(rows.first['ledger_revision']);
    if (actual != expectedRevision) {
      throw RevisionConflictException(expectedRevision, actual);
    }
    final next = actual + 1;
    await txn.update('app_settings', {'ledger_revision': next}, where: 'id = 1');
    return next;
  }

  Future<LedgerState> updateSettings({
    required int expectedRevision,
    ThemeSetting? theme,
    MotionSetting? motion,
    AppTone? tone,
    bool? widgetPrivacy,
    required DateTime nowUtc,
  }) async {
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await txn.update(
        'app_settings',
        {
          if (theme != null) 'theme': theme.name,
          if (motion != null) 'motion': motion.name,
          if (tone != null) 'tone': tone.name,
          if (widgetPrivacy != null) 'widget_privacy': widgetPrivacy ? 1 : 0,
        },
        where: 'id = 1',
      );
    });
    return read(nowUtc: nowUtc);
  }

  Future<LedgerState> replaceCompensation({
    required int expectedRevision,
    required Rational monthlySalary,
    required WeekTemplate week,
    WeekAlternation? alternation,
    required LocalDate effectiveFrom,
    required DateTime nowUtc,
  }) async {
    final instant = calendar.startOfDayUtc(effectiveFrom);
    final timestamp = nowUtc.toUtc().toIso8601String();
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await _closeVersions(txn, 'salary_versions', instant);
      await _closeVersions(txn, 'schedule_versions', instant);
      final scheduleId = _newId('schedule');
      await txn.insert('schedule_versions', {
        'id': scheduleId,
        'timezone': calendar.timezoneName,
        'weekly_json': jsonEncode(ScheduleCodec.encodeWeek(week)),
        'effective_from': instant.toIso8601String(),
        'effective_to': null,
        'calendar_source_version': 'WORK_CN@builtin',
        'alternation_json': alternation == null
            ? null
            : jsonEncode(ScheduleCodec.encodeAlternation(alternation)),
        'created_at': timestamp,
      });
      await txn.insert('salary_versions', {
        'id': _newId('salary'),
        'monthly_net_cny': monthlySalary.toCanonicalString(),
        'effective_from': instant.toIso8601String(),
        'effective_to': null,
        'schedule_version_id': scheduleId,
        'created_at': timestamp,
      });
      // Salary + schedule is a complete ledger regardless of how it was
      // created. Record onboarding completion so exports and future onboarding
      // decisions do not treat a manually configured PC ledger as unfinished.
      await txn.rawUpdate(
        'UPDATE app_settings SET onboarding_completed_at = ? '
        'WHERE id = 1 AND onboarding_completed_at IS NULL',
        [timestamp],
      );
    });
    return read(nowUtc: nowUtc);
  }

  Future<LedgerState> replaceHousing({
    required int expectedRevision,
    required HousingMode mode,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
    required DateTime nowUtc,
  }) async {
    final instant = calendar.startOfDayUtc(effectiveFrom);
    final timestamp = nowUtc.toUtc().toIso8601String();
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await _closeVersions(txn, 'housing_plan_versions', instant);
      final planId = _newId('housing');
      await txn.insert('housing_plan_versions', {
        'id': planId,
        'mode': mode.name,
        'effective_from': instant.toIso8601String(),
        'effective_to': null,
        'created_at': timestamp,
      });
      if (mode != HousingMode.none && monthlyAmount != null) {
        await txn.insert('monthly_bills', {
          'id': _newId('bill'),
          'expense_id': planId,
          'kind': ExpenseKind.housing.name,
          'month': billMonth.toIsoString(),
          'monthly_amount_cny': monthlyAmount.toCanonicalString(),
          'principal_cny': principal?.toCanonicalString(),
          'status': BillStatus.confirmed.name,
          'revision': 1,
          'note': mode == HousingMode.rent ? 'rent' : null,
          'updated_at': timestamp,
        });
      }
    });
    return read(nowUtc: nowUtc);
  }

  Future<LedgerState> replaceCar({
    required int expectedRevision,
    required bool enabled,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
    required DateTime nowUtc,
  }) async {
    final instant = calendar.startOfDayUtc(effectiveFrom);
    final timestamp = nowUtc.toUtc().toIso8601String();
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await _closeVersions(txn, 'car_plan_versions', instant);
      final planId = _newId('car');
      await txn.insert('car_plan_versions', {
        'id': planId,
        'enabled': enabled ? 1 : 0,
        'effective_from': instant.toIso8601String(),
        'effective_to': null,
        'created_at': timestamp,
      });
      if (enabled && monthlyAmount != null) {
        await txn.insert('monthly_bills', {
          'id': _newId('bill'),
          'expense_id': planId,
          'kind': ExpenseKind.car.name,
          'month': billMonth.toIsoString(),
          'monthly_amount_cny': monthlyAmount.toCanonicalString(),
          'principal_cny': principal?.toCanonicalString(),
          'status': BillStatus.confirmed.name,
          'revision': 1,
          'note': null,
          'updated_at': timestamp,
        });
      }
    });
    return read(nowUtc: nowUtc);
  }

  /// Closes [previousInstrumentId] and inserts [instrumentId] in one
  /// transaction. Editing a code never leaves two active rows or a half
  /// written ledger; a duplicate target id aborts the whole transaction.
  Future<LedgerState> upsertHolding({
    required int expectedRevision,
    required String instrumentId,
    required Rational quantity,
    required Rational costPerUnit,
    String? name,
    bool pendingQuote = false,
    String? previousInstrumentId,
    required DateTime nowUtc,
  }) async {
    final timestamp = nowUtc.toUtc().toIso8601String();
    final instant = nowUtc.toUtc();
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      if (previousInstrumentId != null &&
          previousInstrumentId != instrumentId) {
        final active = await txn.query(
          'holding_versions',
          where: 'instrument_id = ? AND effective_to IS NULL',
          whereArgs: [instrumentId],
          limit: 1,
        );
        if (active.isNotEmpty) {
          throw DuplicateHoldingException(instrumentId);
        }
        await _closeVersions(
          txn,
          'holding_versions',
          instant,
          extraWhere: 'instrument_id = ?',
          extraArgs: [previousInstrumentId],
        );
      }
      await _closeVersions(
        txn,
        'holding_versions',
        instant,
        extraWhere: 'instrument_id = ?',
        extraArgs: [instrumentId],
      );
      await txn.insert('holding_versions', {
        'id': _newId('holding'),
        'instrument_id': instrumentId,
        'quantity': quantity.toCanonicalString(),
        'cost_per_unit': costPerUnit.toCanonicalString(),
        'effective_from': timestamp,
        'effective_to': null,
        'pending_quote': pendingQuote ? 1 : 0,
        'created_at': timestamp,
      });
      if (name != null && name.trim().isNotEmpty) {
        await _saveInstrumentNames(txn, {instrumentId: name}, timestamp);
      }
    });
    return read(nowUtc: nowUtc);
  }

  /// Persists date-only fund NAVs.
  ///
  /// Ordering rules: a newer NAV date wins; the same date only accepts a
  /// provable higher source revision, otherwise the real fetch time decides so
  /// a late response from an old request cannot overwrite a newer result. An
  /// eligibility-only row never erases a cached NAV.
  Future<void> saveFundNavs(List<FundNavSnapshot> navs) async {
    if (navs.isEmpty) return;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      for (final nav in navs) {
        final existing = await txn.query(
          'fund_nav_cache',
          where: 'instrument_id = ?',
          whereArgs: [nav.instrumentId],
          limit: 1,
        );
        final row = existing.isEmpty ? null : existing.first;

        if (row != null) {
          final oldDate = LocalDate.tryParse(row['nav_date'] as String?);
          final oldFetched = DateTime.parse(row['fetched_at']! as String);
          if (nav.navCny == null || nav.navDate == null) {
            if (oldDate != null) {
              // Directory/eligibility refresh only: keep the real NAV and its
              // original fetch instant, update the public status columns.
              await txn.update(
                'fund_nav_cache',
                {
                  'eligibility': nav.eligibility.name,
                  'fund_calendar': nav.fundCalendar.name,
                  'source_license_status': nav.sourceLicenseStatus.name,
                  'updated_at': timestamp,
                },
                where: 'instrument_id = ?',
                whereArgs: [nav.instrumentId],
              );
              continue;
            }
          } else if (oldDate != null) {
            final order = nav.navDate!.compareTo(oldDate);
            if (order < 0) continue;
            if (order == 0) {
              final oldRevision = row['source_revision'] as int?;
              final newRevision = nav.sourceRevision;
              if (oldRevision != null && newRevision != null) {
                if (newRevision < oldRevision) continue;
                if (newRevision == oldRevision &&
                    nav.fetchedAtUtc.isBefore(oldFetched)) {
                  continue;
                }
              } else if (nav.fetchedAtUtc.isBefore(oldFetched)) {
                continue;
              }
            }
          } else if (nav.fetchedAtUtc.isBefore(oldFetched)) {
            continue;
          }
        }

        await txn.insert(
          'fund_nav_cache',
          {
            'instrument_id': nav.instrumentId,
            'nav_cny': nav.navCny?.toCanonicalString(),
            'nav_date': nav.navDate?.toIsoString(),
            'previous_nav_cny': nav.previousNavCny?.toCanonicalString(),
            'previous_nav_date': nav.previousNavDate?.toIsoString(),
            'action_status': nav.actionStatus.name,
            'fund_calendar': nav.fundCalendar.name,
            'eligibility': nav.eligibility.name,
            'fetched_at': nav.fetchedAtUtc.toIso8601String(),
            'published_at': nav.publishedAtUtc?.toIso8601String(),
            'source': nav.source,
            'source_revision': nav.sourceRevision,
            'quality': nav.quality.name,
            'source_license_status': nav.sourceLicenseStatus.name,
            'updated_at': timestamp,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Oldest cached NAV fetch time for [instrumentIds], or null when at least
  /// one fund has no cache yet. Used for the 30-minute low-frequency refresh.
  Future<DateTime?> oldestFundFetchedAt(List<String> instrumentIds) async {
    if (instrumentIds.isEmpty) return null;
    final rows = await database.raw.query(
      'fund_nav_cache',
      columns: ['instrument_id', 'fetched_at'],
      where: 'instrument_id IN (${List.filled(instrumentIds.length, '?').join(',')})',
      whereArgs: instrumentIds,
    );
    if (rows.length < instrumentIds.length) return null;
    DateTime? oldest;
    for (final row in rows) {
      final fetched = DateTime.parse(row['fetched_at']! as String);
      if (oldest == null || fetched.isBefore(oldest)) oldest = fetched;
    }
    return oldest;
  }

  Future<LedgerState> deleteHolding({
    required int expectedRevision,
    required String instrumentId,
    required DateTime nowUtc,
  }) async {
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await _closeVersions(
        txn,
        'holding_versions',
        nowUtc.toUtc(),
        extraWhere: 'instrument_id = ?',
        extraArgs: [instrumentId],
      );
    });
    return read(nowUtc: nowUtc);
  }

  Future<LedgerState> saveBill({
    required int expectedRevision,
    required MonthlyBill bill,
    required DateTime nowUtc,
  }) async {
    final timestamp = nowUtc.toUtc().toIso8601String();
    await database.transaction((txn) async {
      await _bumpRevision(txn, expectedRevision);
      await txn.insert(
        'monthly_bills',
        {
          'id': _newId('bill'),
          'expense_id': bill.expenseId,
          'kind': bill.kind.name,
          'month': bill.month.toIsoString(),
          'monthly_amount_cny': bill.monthlyAmountCny?.toCanonicalString(),
          'principal_cny': bill.principalCny?.toCanonicalString(),
          'status': bill.status.name,
          'revision': bill.revision + 1,
          'note': bill.note,
          'updated_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return read(nowUtc: nowUtc);
  }

  Future<LedgerState> clearAll({required DateTime nowUtc}) async {
    await database.transaction((txn) async {
      for (final table in const [
        'salary_versions',
        'schedule_versions',
        'schedule_day_overrides',
        'holding_versions',
        'housing_plan_versions',
        'car_plan_versions',
        'monthly_bills',
        'quote_cache',
        'fund_nav_cache',
        'market_calendar_days',
        'onboarding_drafts',
        'setup_commits',
        'widget_publish_jobs',
        // Clearing financial data must also remove recoverable copies.
        'ledger_backups',
        // HOME-DUAL-10: clearing the ledger also resets the local layout
        // preference; the next visit defaults to showing both cards.
        'ui_preferences',
      ]) {
        await txn.delete(table);
      }
      final rows = await txn.query('app_settings', where: 'id = 1');
      final revision = LedgerJson.asInt(rows.first['ledger_revision']) + 1;
      await txn.update(
        'app_settings',
        {
          'ledger_revision': revision,
          'widget_privacy': 0,
          'onboarding_completed_at': null,
          'sample_mode': 0,
        },
        where: 'id = 1',
      );
    });
    return read(nowUtc: nowUtc);
  }

  Future<void> saveDraft({
    required String setupSessionId,
    required int step,
    required Map<String, dynamic> payload,
    required DateTime nowUtc,
    int draftVersion = 1,
  }) async {
    await database.raw.insert(
      'onboarding_drafts',
      {
        'setup_session_id': setupSessionId,
        'draft_version': draftVersion,
        'step': step,
        'payload_json': jsonEncode(payload),
        'updated_at': nowUtc.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OnboardingDraftRow?> loadDraft() async {
    final rows = await database.raw.query(
      'onboarding_drafts',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final payload = jsonDecode(row['payload_json']! as String);
    return OnboardingDraftRow(
      setupSessionId: row['setup_session_id']! as String,
      draftVersion: LedgerJson.asInt(row['draft_version'], fallback: 1),
      step: LedgerJson.asInt(row['step']),
      payload: payload is Map
          ? payload.cast<String, dynamic>()
          : <String, dynamic>{},
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  Future<void> deleteDraft(String setupSessionId) async {
    await database.raw.delete(
      'onboarding_drafts',
      where: 'setup_session_id = ?',
      whereArgs: [setupSessionId],
    );
  }

  Future<void> enqueueWidgetJob({
    required int ledgerRevision,
    required String kind,
    required String payload,
    required DateTime nowUtc,
    int revision = 1,
  }) async {
    await database.raw.delete(
      'widget_publish_jobs',
      where: 'ledger_revision <= ?',
      whereArgs: [ledgerRevision],
    );
    await database.raw.insert('widget_publish_jobs', {
      'ledger_revision': ledgerRevision,
      'kind': kind,
      'payload': payload,
      'created_at': nowUtc.toUtc().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<List<WidgetPublishJob>> pendingWidgetJobs() async {
    final rows = await database.raw.query(
      'widget_publish_jobs',
      orderBy: 'ledger_revision ASC',
    );
    return [
      for (final row in rows)
        WidgetPublishJob(
          id: LedgerJson.asInt(row['id']),
          ledgerRevision: LedgerJson.asInt(row['ledger_revision']),
          kind: row['kind']! as String,
          payload: row['payload']! as String,
          attempts: LedgerJson.asInt(row['attempts']),
        ),
    ];
  }

  Future<void> completeWidgetJob(int id) async {
    await database.raw.delete('widget_publish_jobs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordWidgetJobFailure(int id) async {
    await database.raw.rawUpdate(
      'UPDATE widget_publish_jobs SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  Future<bool> hasCalendarDay({
    required String market,
    required LocalDate date,
  }) async {
    final rows = await database.raw.query(
      'market_calendar_days',
      where: 'market = ? AND local_date = ?',
      whereArgs: [market, date.toIsoString()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> saveQuotes(List<Quote> quotes) async {
    if (quotes.isEmpty) return;
    await database.transaction((txn) async {
      for (final quote in quotes) {
        final existing = await txn.query(
          'quote_cache',
          where: 'instrument_id = ?',
          whereArgs: [quote.instrumentId],
        );
        if (existing.isNotEmpty) {
          final current = existing.first;
          final currentAt = DateTime.parse(current['quote_at']! as String);
          final currentRevision =
              LedgerJson.asInt(current['source_revision']);
          final older = quote.quoteAtUtc.isBefore(currentAt);
          final sameTimeOlderRevision = quote.quoteAtUtc.isAtSameMomentAs(currentAt) &&
              quote.sourceRevision < currentRevision;
          if (older || sameTimeOlderRevision) continue;
        }
        await txn.insert(
          'quote_cache',
          {
            'instrument_id': quote.instrumentId,
            'price_cny': quote.priceCny?.toCanonicalString(),
            'baseline_cny': quote.baselineCny?.toCanonicalString(),
            'quote_at': quote.quoteAtUtc.toIso8601String(),
            'fetched_at': quote.fetchedAtUtc.toIso8601String(),
            'trading_date': quote.tradingDate.toIsoString(),
            'day_basis': quote.dayBasis.name,
            'market_state': quote.marketState.name,
            'quality': quote.quality.name,
            'source': quote.source,
            'source_revision': quote.sourceRevision,
            'delay_seconds': quote.delaySeconds,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> saveCalendarDays({
    required String market,
    required Map<LocalDate, MarketDayStatus> days,
  }) async {
    if (days.isEmpty) return;
    await database.transaction((txn) async {
      for (final entry in days.entries) {
        await txn.insert(
          'market_calendar_days',
          {
            'market': market,
            'local_date': entry.key.toIsoString(),
            'status': entry.value.name,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}

final class WidgetPublishJob {
  const WidgetPublishJob({
    required this.id,
    required this.ledgerRevision,
    required this.kind,
    required this.payload,
    required this.attempts,
  });

  final int id;
  final int ledgerRevision;
  final String kind;
  final String payload;
  final int attempts;
}
