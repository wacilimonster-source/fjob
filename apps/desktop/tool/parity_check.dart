// Reads an exported .fjob and prints the shared-engine dashboard values at a
// given instant, for cent-level comparison against the running PC UI.
import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/parity_check.dart <file.fjob> [isoInstantUtc]');
    exit(64);
  }
  final bundle = LedgerBundle.decode(File(args[0]).readAsStringSync());
  final ledger = bundle.ledger;
  final calendar = BusinessCalendar.forZone(ledger.settings.salaryTimezone);
  final now = args.length > 1 ? DateTime.parse(args[1]).toUtc() : DateTime.now().toUtc();
  final snapshot = DashboardCalculator(calendar).calculate(
    ledger.toCalculationInput(calendar: calendar, nowUtc: now),
  );
  stdout.writeln(jsonEncode({
    'ledgerId': bundle.ledgerId,
    'ledgerRevision': bundle.ledgerRevision,
    'computedAtUtc': now.toIso8601String(),
    'localClock': formatClock(now, calendar),
    'wage': snapshot.wage?.toFixed(2),
    'stockDaily': snapshot.stockDaily?.toFixed(2),
    'fundDaily': snapshot.fundDaily?.toFixed(2),
    'goldDaily': snapshot.goldDaily?.toFixed(2),
    'housing': snapshot.housing?.toFixed(2),
    'car': snapshot.car?.toFixed(2),
    'total': snapshot.total?.toFixed(2),
    'completeness': snapshot.completeness.name,
    'phase': snapshot.phase.name,
  }));
}