/// HOME-DUAL-10: local-only storage for the dashboard metric choice.
///
/// Deliberately separate from `LedgerRepository.updateSettings`: changing the
/// layout must not bump `ledgerRevision`, request quotes or publish a widget
/// snapshot. A single-row replace keeps each write atomic.
library;

import 'package:sqflite_common/sqlite_api.dart';

import 'package:ledger_model/domain/home_metrics.dart';
import 'app_database.dart';

abstract interface class HomeMetricsPreferenceStore {
  Future<HomeMetricsMode> read();

  Future<void> write(HomeMetricsMode mode);
}

final class SqliteHomeMetricsPreferenceStore
    implements HomeMetricsPreferenceStore {
  SqliteHomeMetricsPreferenceStore(this._database);

  final AppDatabase _database;

  static const String key = 'home_metrics_mode';

  @override
  Future<HomeMetricsMode> read() async {
    final rows = await _database.raw.query(
      'ui_preferences',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [key],
      limit: 1,
    );
    if (rows.isEmpty) return HomeMetricsMode.both;
    return HomeMetricsMode.fromStorage(rows.first['value']);
  }

  @override
  Future<void> write(HomeMetricsMode mode) async {
    await _database.raw.insert(
      'ui_preferences',
      {
        'key': key,
        'value': mode.storageValue,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
