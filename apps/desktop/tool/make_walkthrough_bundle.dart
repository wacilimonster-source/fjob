// Generates a mobile-style .fjob for the PC walkthrough and prints the
// expected dashboard values at the current instant for parity comparison.
import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';

void main(List<String> args) {
  final out = args.isNotEmpty ? args[0] : 'walkthrough.fjob';
  final calendar = BusinessCalendar.shanghai;
  final now = args.length > 1 ? DateTime.parse(args[1]).toUtc() : DateTime.now().toUtc();
  final ledger = buildDemoLedger(calendar, now);
  final bundle = LedgerBundle.fromLedger(
    ledger,
    ledgerId: '7f3a9c2e-1111-4b2a-9c3d-a1b2c3d4e5f6',
    exportedAt: now,
    appVersion: '0.1.0',
    platform: 'android',
  );
  File(out).writeAsStringSync(bundle.encode());
  final snapshot = DashboardCalculator(calendar).calculate(
    ledger.toCalculationInput(calendar: calendar, nowUtc: now),
  );
  stdout.writeln(jsonEncode({
    'file': out,
    'ledgerRevision': bundle.ledgerRevision,
    'checksum': bundle.checksum,
    'computedAtUtc': now.toIso8601String(),
    'wage': snapshot.wage?.toFixed(2),
    'housing': snapshot.housing?.toFixed(2),
    'car': snapshot.car?.toFixed(2),
    'total': snapshot.total?.toFixed(2),
    'completeness': snapshot.completeness.name,
    'phase': snapshot.phase.name,
  }));
}