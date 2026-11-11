import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_model/ledger_model.dart';

/// PC consumes the same fixtures/calculation-cases.json as mobile and the pure
/// finance_core engine; the demo ledger reproduces CALC-01/CALC-09 to the cent.
void main() {
  final fixture = jsonDecode(
          File('../../fixtures/calculation-cases.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = {
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>())
      c['id'] as String: c,
  };

  test('fixture file is the shared contract version 1', () {
    expect(fixture['contractVersion'], 1);
    expect(fixture['rounding'], 'HALF_UP');
    expect(cases.containsKey('CALC-09'), isTrue);
  });

  test('PC dashboard matches CALC-01 wage and CALC-09 total to the cent', () {
    final calendar = BusinessCalendar.shanghai;
    final now = DateTime.utc(2026, 11, 4, 6, 36);
    final ledger = buildDemoLedger(calendar, now);
    final snapshot = DashboardCalculator(calendar).calculate(
      ledger.toCalculationInput(calendar: calendar, nowUtc: now),
    );
    final wageExpected =
        (cases['CALC-01']!['expected'] as Map)['displayCny'] as String;
    final totalExpected =
        (cases['CALC-09']!['expected'] as Map)['displayCny'] as String;
    expect(snapshot.wage!.toFixed(2), wageExpected);
    expect(snapshot.total!.toFixed(2), totalExpected);
    expect(snapshot.completeness.name,
        (cases['CALC-09']!['expected'] as Map)['completeness']);
  });

  test('shared display model formats the demo balance like the fixture', () {
    final calendar = BusinessCalendar.shanghai;
    final now = DateTime.utc(2026, 11, 4, 6, 36);
    final ledger = buildDemoLedger(calendar, now);
    final snapshot = DashboardCalculator(calendar).calculate(
      ledger.toCalculationInput(calendar: calendar, nowUtc: now),
    );
    final balance = buildHomeBalanceDisplay(
        snapshot: snapshot, calendar: calendar, tone: AppTone.gentle);
    expect(balance.amountText, '−¥55.26');
    expect(balance.negative, isTrue);
    final time = buildHomeTimeDisplay(snapshot: snapshot, calendar: calendar);
    expect(time.mainValue, '03:24:00');
  });
}
