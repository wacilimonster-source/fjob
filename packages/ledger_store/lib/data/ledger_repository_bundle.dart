part of 'ledger_repository.dart';

enum LedgerImportMode { replace, merge }

final class OlderLedgerRevisionException implements Exception {
  const OlderLedgerRevisionException(this.incoming, this.current);
  final int incoming;
  final int current;
  @override
  String toString() => 'Older ledger revision rejected ($incoming < $current)';
}

/// Metadata only: listing backups never exposes financial values in a label.
final class LedgerBackup {
  const LedgerBackup({required this.id, required this.createdAt,
    required this.ledgerId, required this.ledgerRevision});
  final int id;
  final DateTime createdAt;
  final String ledgerId;
  final int ledgerRevision;
}

/// Portable bundle and full configuration operations on the shared repository.
/// All checks, backups and mutations run on the same SQLite transaction.
extension LedgerBundleRepository on LedgerRepository {
  Future<int> _checkRevision(Transaction txn, int expected) async {
    final row = (await txn.query('app_settings', where: 'id = 1')).single;
    final actual = row['ledger_revision']! as int;
    if (expected != actual) throw RevisionConflictException(expected, actual);
    return actual;
  }

  Future<String> _ledgerId(DatabaseExecutor txn) async =>
      (await txn.query('ledger_metadata', where: 'id = 1')).single['ledger_id']! as String;

  Future<LedgerBundle> _bundleInTransaction(Transaction txn, {
    required DateTime exportedAt, required String appVersion, required String platform,
  }) async => LedgerBundle.fromLedger(
    await _read(txn, nowUtc: exportedAt, includeMarketData: false),
    ledgerId: await _ledgerId(txn), exportedAt: exportedAt,
    appVersion: appVersion, platform: platform,
  );

  /// Consistent, read-only export. Does not bump revision or create a backup.
  Future<LedgerBundle> exportBundle({required DateTime exportedAt,
    required String appVersion, required String platform}) =>
      database.transaction((txn) => _bundleInTransaction(txn,
        exportedAt: exportedAt, appVersion: appVersion, platform: platform));

  /// Replace adopts the source ledgerId; merge keeps this ledger's identity.
  /// Same-ledger old revisions are rejected even in merge mode. UI preferences
  /// and local market caches are never imported or included in the backup.
  Future<LedgerState> importBundle(LedgerBundle bundle, {
    required int expectedRevision, required DateTime nowUtc,
    LedgerImportMode mode = LedgerImportMode.replace,
  }) => database.transaction((txn) async {
    await _checkRevision(txn, expectedRevision);
    return _importInTransaction(txn, bundle, nowUtc: nowUtc, mode: mode);
  });

  Future<LedgerState> _importInTransaction(Transaction txn, LedgerBundle incoming, {
    required DateTime nowUtc, required LedgerImportMode mode, bool restoring = false,
  }) async {
    final current = await _bundleInTransaction(txn,
      exportedAt: nowUtc, appVersion: 'backup-v1', platform: 'windows');
    if (!restoring && incoming.ledgerId == current.ledgerId &&
        incoming.ledgerRevision < current.ledgerRevision) {
      throw OlderLedgerRevisionException(incoming.ledgerRevision, current.ledgerRevision);
    }
    final selected = mode == LedgerImportMode.merge
        ? current.mergedWith(incoming) : incoming;
    final revision = _nextRevision(current.ledgerRevision, incoming.ledgerRevision);
    // Validation happens before the backup. Any subsequent SQL error rolls
    // back both the backup/pruning and every row/revision/identity mutation.
    await _backup(txn, current, nowUtc);
    await _writeConfiguration(txn, selected.ledger,
      ledgerId: selected.ledgerId, revision: revision, nowUtc: nowUtc);
    return _read(txn, nowUtc: nowUtc);
  }

  Future<void> _backup(Transaction txn, LedgerBundle bundle, DateTime nowUtc) async {
    await txn.insert('ledger_backups', {
      'created_at': nowUtc.toUtc().toIso8601String(),
      'ledger_id': bundle.ledgerId,
      'ledger_revision': bundle.ledgerRevision,
      'bundle_json': bundle.encode(),
    });
    // Row sequence rather than device clock defines recency (clock may rewind).
    await txn.execute('''DELETE FROM ledger_backups WHERE id NOT IN
      (SELECT id FROM ledger_backups ORDER BY id DESC LIMIT 5)''');
  }

  Future<List<LedgerBackup>> listBackups() async {
    final rows = await database.raw.query('ledger_backups',
      columns: ['id', 'created_at', 'ledger_id', 'ledger_revision'], orderBy: 'id DESC');
    return [for (final row in rows) LedgerBackup(
      id: row['id']! as int, createdAt: DateTime.parse(row['created_at']! as String),
      ledgerId: row['ledger_id']! as String, ledgerRevision: row['ledger_revision']! as int,
    )];
  }

  /// Explicit recovery may restore old content, but never rolls revision back.
  /// Creates a backup of the current content first and retains local UI state.
  Future<LedgerState> restoreBackup(int backupId, {
    required int expectedRevision, required DateTime nowUtc,
  }) => database.transaction((txn) async {
    await _checkRevision(txn, expectedRevision);
    final rows = await txn.query('ledger_backups', where: 'id = ?', whereArgs: [backupId]);
    if (rows.isEmpty) throw StateError('Ledger backup not found');
    final bundle = LedgerBundle.decode(rows.single['bundle_json']! as String);
    return _importInTransaction(txn, bundle, nowUtc: nowUtc,
      mode: LedgerImportMode.replace, restoring: true);
  });

  /// Atomically saves an edited configuration. Rows omitted by the caller are
  /// retained (including history and date overrides); supplied identities are
  /// explicit edits. To replace an active version, supply its closed period and
  /// the new version. To mark a date off, supply an empty confirmed override.
  /// Unlike cross-ledger merge, this is a local edit protected by expectedRevision.
  Future<LedgerState> saveConfiguration({required LedgerState configuration,
    required int expectedRevision, required DateTime nowUtc}) =>
      database.transaction((txn) async {
        final actual = await _checkRevision(txn, expectedRevision);
        final current = await _read(txn, nowUtc: nowUtc, includeMarketData: false);
        List<T> overlay<T>(Iterable<T> old, Iterable<T> edits, String Function(T) key) =>
            {for (final v in old) key(v): v, for (final v in edits) key(v): v}.values.toList();
        final merged = configuration.copyWith(
          settings: configuration.settings.copyWith(
            ledgerRevision: actual,
            onboardingCompletedAt: configuration.settings.onboardingCompletedAt ??
                current.settings.onboardingCompletedAt,
          ),
          salaryVersions: overlay(current.salaryVersions, configuration.salaryVersions, (v) => v.id),
          schedules: {...current.schedules, ...configuration.schedules},
          overrides: overlay(current.overrides, configuration.overrides, (v) => v.localDate.toIsoString()),
          holdings: overlay(current.holdings, configuration.holdings, (v) => v.id),
          housingVersions: overlay(current.housingVersions, configuration.housingVersions, (v) => v.id),
          carVersions: overlay(current.carVersions, configuration.carVersions, (v) => v.id),
          bills: overlay(current.bills, configuration.bills, (v) => '${v.expenseId}@${v.month.toIsoString()}'),
        );
        final id = await _ledgerId(txn);
        final checked = LedgerBundle.fromLedger(merged, ledgerId: id,
          exportedAt: nowUtc, appVersion: 'configuration-v1', platform: 'windows');
        await _writeConfiguration(txn, checked.ledger,
          ledgerId: id, revision: _nextRevision(actual, actual), nowUtc: nowUtc);
        return _read(txn, nowUtc: nowUtc);
      });

  int _nextRevision(int a, int b) {
    final top = max(a, b);
    if (top >= LedgerBundle.maxRevision) throw StateError('Ledger revision exhausted');
    return top + 1;
  }

  Future<void> _writeConfiguration(Transaction txn, LedgerState ledger, {
    required String ledgerId, required int revision, required DateTime nowUtc,
  }) async {
    final timestamp = nowUtc.toUtc().toIso8601String();
    for (final table in const ['monthly_bills', 'salary_versions', 'schedule_day_overrides',
      'holding_versions', 'housing_plan_versions', 'car_plan_versions', 'schedule_versions']) {
      await txn.delete(table);
    }
    for (final v in ledger.schedules.values) {
      await txn.insert('schedule_versions', {
        'id': v.id, 'timezone': v.timezone,
        'weekly_json': jsonEncode(ScheduleCodec.encodeWeek(v.week)),
        'alternation_json': v.alternation == null ? null : jsonEncode(ScheduleCodec.encodeAlternation(v.alternation!)),
        'effective_from': v.effectiveFromUtc.toIso8601String(),
        'effective_to': v.effectiveToUtc?.toIso8601String(),
        'calendar_source_version': v.calendarSourceVersion, 'created_at': timestamp,
      });
    }
    for (final v in ledger.salaryVersions) {
      await txn.insert('salary_versions', {
        'id': v.id, 'monthly_net_cny': v.monthlyNetCny.toCanonicalString(),
        'schedule_version_id': v.scheduleVersionId,
        'effective_from': v.effectiveFromUtc.toIso8601String(),
        'effective_to': v.effectiveToUtc?.toIso8601String(), 'created_at': timestamp,
      });
    }
    for (final v in ledger.overrides) {
      await txn.insert('schedule_day_overrides', {
        'local_date': v.localDate.toIsoString(),
        'paid_intervals_json': ScheduleCodec.encodeOverrides(v.paidIntervals),
        'reason': v.reason, 'confirmed': v.confirmed ? 1 : 0, 'updated_at': timestamp,
      });
    }
    for (final v in ledger.holdings) {
      await txn.insert('holding_versions', {
        'id': v.id, 'instrument_id': v.instrumentId,
        'quantity': v.quantity.toCanonicalString(), 'cost_per_unit': v.costPerUnit.toCanonicalString(),
        'effective_from': v.effectiveFromUtc.toIso8601String(),
        'effective_to': v.effectiveToUtc?.toIso8601String(),
        'pending_quote': v.pendingQuote ? 1 : 0, 'created_at': timestamp,
      });
    }
    for (final v in ledger.housingVersions) {
      await txn.insert('housing_plan_versions', {
        'id': v.id, 'mode': v.mode.name,
        'effective_from': v.effectiveFromUtc.toIso8601String(),
        'effective_to': v.effectiveToUtc?.toIso8601String(), 'created_at': timestamp,
      });
    }
    for (final v in ledger.carVersions) {
      await txn.insert('car_plan_versions', {
        'id': v.id, 'enabled': v.enabled ? 1 : 0,
        'effective_from': v.effectiveFromUtc.toIso8601String(),
        'effective_to': v.effectiveToUtc?.toIso8601String(), 'created_at': timestamp,
      });
    }
    for (final v in ledger.bills) {
      await txn.insert('monthly_bills', {
        'id': '${v.expenseId}@${v.month.toIsoString()}',
        'expense_id': v.expenseId, 'kind': v.kind.name, 'month': v.month.toIsoString(),
        'monthly_amount_cny': v.monthlyAmountCny?.toCanonicalString(),
        'principal_cny': v.principalCny?.toCanonicalString(),
        'status': v.status.name, 'revision': v.revision, 'note': v.note, 'updated_at': timestamp,
      });
    }
    await txn.update('ledger_metadata', {'ledger_id': ledgerId}, where: 'id = 1');
    // Presentation settings and ui_preferences are deliberately not overwritten.
    await txn.update('app_settings', {
      'ledger_revision': revision,
      'salary_timezone': ledger.settings.salaryTimezone,
      'onboarding_completed_at': ledger.settings.onboardingCompletedAt?.toIso8601String(),
      'sample_mode': 0,
    }, where: 'id = 1');
    await txn.delete('widget_publish_jobs');
  }
}
