// Seeds a configured ledger database for reproducing mobile export on an
// emulator. Not part of the product; remove after the investigation.
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  final out = args.isNotEmpty ? args[0] : 'seed_ledger.db';
  if (File(out).existsSync()) File(out).deleteSync();
  final calendar = BusinessCalendar.shanghai;
  final now = DateTime.utc(2026, 11, 12, 2, 0);
  final ledger = buildDemoLedger(calendar, now);
  final bundle = LedgerBundle.fromLedger(
    ledger,
    ledgerId: '7f3a9c2e-1111-4b2a-9c3d-a1b2c3d4e5f6',
    exportedAt: now,
    appVersion: '0.1.11',
    platform: 'android',
  );
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: out,
    calendar: calendar,
  );
  final repository = LedgerRepository(database, calendar);
  final state = await repository.importBundle(
    bundle,
    expectedRevision: 0,
    nowUtc: now,
    mode: LedgerImportMode.replace,
  );
  stdout.writeln('configured=${state.isConfigured} '
      'salary=${state.salaryVersions.length} schedules=${state.schedules.length}');
  await database.close();
}
