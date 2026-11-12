// Seeds a PC ledger through the manual compensation path (no mobile import)
// for a release-build walkthrough. Temporary verification tool.
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/seed_manual_ledger.dart <db path>');
    exit(64);
  }
  sqfliteFfiInit();
  final path = args.first;
  final file = File(path);
  file.parent.createSync(recursive: true);
  if (file.existsSync()) file.deleteSync();
  final calendar = BusinessCalendar.shanghai;
  final now = DateTime.utc(2026, 11, 12, 2);
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
    calendar: calendar,
  );
  final repository = LedgerRepository(database, calendar);
  final state = await repository.replaceCompensation(
    expectedRevision: 0,
    monthlySalary: Rational.parse('12000'),
    week: WeekTemplate.standardOffice(),
    effectiveFrom: const LocalDate(2026, 11, 2),
    nowUtc: now,
  );
  stdout.writeln('configured=${state.isConfigured} '
      'onboarding=${state.settings.hasCompletedOnboarding}');
  await database.close();
}
