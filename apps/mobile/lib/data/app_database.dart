/// SQLite storage: schema, migrations and transaction helpers.
library;

import 'dart:convert';

import 'package:finance_core/finance_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Opens the local ledger database.
///
/// `sqflite` provides the mobile platform implementation; tests inject the FFI
/// factory. The schema follows the data contract: timestamps are UTC ISO-8601,
/// business dates are `YYYY-MM-DD`, amounts are canonical decimal strings and
/// every versioned row uses a closed-open effective period.
final class AppDatabase {
  AppDatabase._(this._db, this.schemaVersion);

  static const int currentSchemaVersion = 3;

  static Future<AppDatabase> open({
    required DatabaseFactory factory,
    required String path,
    required BusinessCalendar calendar,
  }) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentSchemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          for (final statement in _schemaV1) {
            await db.execute(statement);
          }
          await db.insert('app_settings', {
            'id': 1,
            'ledger_revision': 0,
            'salary_timezone': calendar.timezoneName,
            'theme': ThemeSettingValues.system,
            'motion': 'full',
            'tone': 'gentle',
            'widget_privacy': 0,
            'onboarding_completed_at': null,
            'sample_mode': 0,
          });
          // A pre-versioned database also reports user_version 0, so sqflite
          // routes it through onCreate rather than onUpgrade.
          await _migrateLegacyConfig(db, calendar);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 1) {
            await _migrateLegacyConfig(db, calendar);
          }
          if (oldVersion < 2) {
            await db.execute(_instrumentDirectorySql);
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE schedule_versions ADD COLUMN alternation_json TEXT',
            );
          }
        },
      ),
    );
    return AppDatabase._(db, currentSchemaVersion);
  }

  final Database _db;
  final int schemaVersion;

  Database get raw => _db;

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _db.transaction(action);

  Future<void> close() => _db.close();

  static const String _instrumentDirectorySql = '''
    CREATE TABLE instrument_directory (
      instrument_id TEXT NOT NULL PRIMARY KEY,
      name TEXT NOT NULL,
      market TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''';

  static const List<String> _schemaV1 = <String>[
    '''
    CREATE TABLE app_settings (
      id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
      ledger_revision INTEGER NOT NULL DEFAULT 0,
      salary_timezone TEXT NOT NULL,
      theme TEXT NOT NULL,
      motion TEXT NOT NULL,
      tone TEXT NOT NULL,
      widget_privacy INTEGER NOT NULL DEFAULT 0,
      onboarding_completed_at TEXT,
      sample_mode INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE schedule_versions (
      id TEXT NOT NULL PRIMARY KEY,
      timezone TEXT NOT NULL,
      weekly_json TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      calendar_source_version TEXT NOT NULL,
      alternation_json TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE salary_versions (
      id TEXT NOT NULL PRIMARY KEY,
      monthly_net_cny TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      schedule_version_id TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE schedule_day_overrides (
      local_date TEXT NOT NULL PRIMARY KEY,
      paid_intervals_json TEXT NOT NULL,
      reason TEXT NOT NULL,
      confirmed INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE holding_versions (
      id TEXT NOT NULL PRIMARY KEY,
      instrument_id TEXT NOT NULL,
      quantity TEXT NOT NULL,
      cost_per_unit TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      pending_quote INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE housing_plan_versions (
      id TEXT NOT NULL PRIMARY KEY,
      mode TEXT NOT NULL,
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE car_plan_versions (
      id TEXT NOT NULL PRIMARY KEY,
      enabled INTEGER NOT NULL,
      effective_from TEXT NOT NULL,
      effective_to TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE monthly_bills (
      id TEXT NOT NULL PRIMARY KEY,
      expense_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      month TEXT NOT NULL,
      monthly_amount_cny TEXT,
      principal_cny TEXT,
      status TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1,
      note TEXT,
      updated_at TEXT NOT NULL,
      UNIQUE (expense_id, month)
    )
    ''',
    '''
    CREATE TABLE quote_cache (
      instrument_id TEXT NOT NULL PRIMARY KEY,
      price_cny TEXT,
      baseline_cny TEXT,
      quote_at TEXT NOT NULL,
      fetched_at TEXT NOT NULL,
      trading_date TEXT NOT NULL,
      day_basis TEXT NOT NULL,
      market_state TEXT NOT NULL,
      quality TEXT NOT NULL,
      source TEXT NOT NULL,
      source_revision INTEGER NOT NULL DEFAULT 0,
      delay_seconds INTEGER
    )
    ''',
    '''
    CREATE TABLE market_calendar_days (
      market TEXT NOT NULL,
      local_date TEXT NOT NULL,
      status TEXT NOT NULL,
      PRIMARY KEY (market, local_date)
    )
    ''',
    '''
    CREATE TABLE onboarding_drafts (
      setup_session_id TEXT NOT NULL PRIMARY KEY,
      draft_version INTEGER NOT NULL,
      step INTEGER NOT NULL,
      payload_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE setup_commits (
      setup_session_id TEXT NOT NULL PRIMARY KEY,
      committed_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE widget_publish_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ledger_revision INTEGER NOT NULL,
      kind TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0
    )
    ''',
    _instrumentDirectorySql,
    'CREATE INDEX idx_salary_effective ON salary_versions (effective_from)',
    'CREATE INDEX idx_holding_instrument ON holding_versions (instrument_id)',
    'CREATE INDEX idx_bills_month ON monthly_bills (month)',
  ];

  /// Imports a pre-versioned prototype ledger when one is found.
  ///
  /// The delivery has no shipped legacy database, so this migration documents
  /// and tests the "old mortgage configuration" upgrade required by
  /// AC-DATA-01: a single flat config becomes versioned rows, and the housing
  /// mode becomes `mortgage`.
  static Future<void> _migrateLegacyConfig(
    Database db,
    BusinessCalendar calendar,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'legacy_config'",
    );
    if (tables.isEmpty) return;
    final rows = await db.query('legacy_config', limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;

    final now = DateTime.now().toUtc();
    final monthStart = calendar.startOfMonthUtc(calendar.dateOf(now));
    final weekdays = row['workdays'] is int ? row['workdays']! as int : 31;
    final startMinute = _parseTime(row['shift_start'] as String?, 9 * 60);
    var endMinute = _parseTime(row['shift_end'] as String?, 18 * 60);
    if (endMinute <= startMinute) endMinute += 1440;
    final breakStart = _parseTime(row['break_start'] as String?, 12 * 60);
    final breakEnd = _parseTime(row['break_end'] as String?, 13 * 60);
    final shift = ShiftTemplate(
      startMinute: startMinute,
      endMinute: endMinute,
      breaks: breakStart == breakEnd
          ? const <BreakTemplate>[]
          : <BreakTemplate>[
              BreakTemplate(startMinute: breakStart, endMinute: breakEnd),
            ],
    );
    final week = WeekTemplate([
      for (var index = 0; index < 7; index++)
        if ((weekdays >> index) & 1 == 1)
          <ShiftTemplate>[shift]
        else
          const <ShiftTemplate>[],
    ]);

    final scheduleId = 'legacy-schedule';
    await db.insert('schedule_versions', {
      'id': scheduleId,
      'timezone': calendar.timezoneName,
      'weekly_json': jsonEncode({
        'mondayFirst': [
          for (final day in week.byWeekday)
            [
              for (final entry in day)
                {
                  'start': entry.startMinute,
                  'end': entry.endMinute,
                  'breaks': [
                    for (final pause in entry.breaks)
                      {'start': pause.startMinute, 'end': pause.endMinute},
                  ],
                },
            ],
        ],
      }),
      'effective_from': monthStart.toIso8601String(),
      'effective_to': null,
      'calendar_source_version': 'WORK_CN@legacy',
      'created_at': now.toIso8601String(),
    });
    await db.insert('salary_versions', {
      'id': 'legacy-salary',
      'monthly_net_cny': (row['salary_cny'] as String?) ?? '0',
      'effective_from': monthStart.toIso8601String(),
      'effective_to': null,
      'schedule_version_id': scheduleId,
      'created_at': now.toIso8601String(),
    });

    final housingMode = (row['housing_mode'] as String?) ?? 'mortgage';
    final housingId = 'legacy-housing';
    await db.insert('housing_plan_versions', {
      'id': housingId,
      'mode': housingMode,
      'effective_from': monthStart.toIso8601String(),
      'effective_to': null,
      'created_at': now.toIso8601String(),
    });
    final housingAmount = housingMode == 'rent'
        ? (row['rent_cny'] as String?)
        : (row['mortgage_cny'] as String?);
    if (housingAmount != null) {
      await db.insert('monthly_bills', {
        'id': 'legacy-housing-bill',
        'expense_id': housingId,
        'kind': 'housing',
        'month': calendar.dateOf(now).firstOfMonth.toIsoString(),
        'monthly_amount_cny': housingAmount,
        'principal_cny': housingMode == 'mortgage'
            ? (row['mortgage_principal_cny'] as String?)
            : null,
        'status': 'confirmed',
        'revision': 1,
        'note': 'migrated-legacy',
        'updated_at': now.toIso8601String(),
      });
    }

    final carAmount = row['car_cny'] as String?;
    if (carAmount != null) {
      final carId = 'legacy-car';
      await db.insert('car_plan_versions', {
        'id': carId,
        'enabled': 1,
        'effective_from': monthStart.toIso8601String(),
        'effective_to': null,
        'created_at': now.toIso8601String(),
      });
      await db.insert('monthly_bills', {
        'id': 'legacy-car-bill',
        'expense_id': carId,
        'kind': 'car',
        'month': calendar.dateOf(now).firstOfMonth.toIsoString(),
        'monthly_amount_cny': carAmount,
        'principal_cny': (row['car_principal_cny'] as String?),
        'status': 'confirmed',
        'revision': 1,
        'note': 'migrated-legacy',
        'updated_at': now.toIso8601String(),
      });
    }

    await db.update(
      'app_settings',
      {
        'ledger_revision': 1,
        'onboarding_completed_at': now.toIso8601String(),
      },
      where: 'id = 1',
    );
    await db.execute('DROP TABLE legacy_config');
  }

  static int _parseTime(String? value, int fallback) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value ?? '');
    if (match == null) return fallback;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }
}

/// Stored enum text values, kept out of the UI layer.
abstract final class ThemeSettingValues {
  static const String system = 'system';
  static const String light = 'light';
  static const String dark = 'dark';
}
