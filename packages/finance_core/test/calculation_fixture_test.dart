/// Runs every reference case in `fixtures/calculation-cases.json` through the
/// production primitives. The fixture is the cross-language acceptance source,
/// so the test reads it from disk instead of duplicating its numbers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final file = File('../../fixtures/calculation-cases.json');
  final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  test('fixture file exposes unique cases and contract version', () {
    expect(fixture['contractVersion'], 1);
    expect(fixture['rounding'], 'HALF_UP');
    expect(fixture['timezone'], 'Asia/Shanghai');
    expect(cases, hasLength(24));
    expect(cases.map((item) => item['id']).toSet(), hasLength(cases.length));
  });

  for (final testCase in cases) {
    final id = testCase['id'] as String;
    final operation = testCase['operation'] as String;
    final input = testCase['input'] as Map<String, dynamic>;
    final expected = testCase['expected'] as Map<String, dynamic>;

    test('$id $operation', () {
      final expectedError = expected['error'] as String?;
      if (expectedError != null) {
        expect(
          () => _run(operation, input),
          throwsA(isA<InvalidScheduleException>()),
        );
        return;
      }
      if (operation == 'fundDailyStale') {
        final position = _runFund(input);
        expect(position.dailyPnl, isNull);
        expect(position.heldPnl!.toFixed(2), expected['heldDisplayCny']);
        return;
      }
      final result = _run(operation, input);
      expect(result.toFixed(2), expected['displayCny']);
      if (expected.containsKey('exact')) {
        expect(result.toCanonicalString(), expected['exact']);
      }
      if (expected.containsKey('completeness')) {
        expect(_completenessOf(input), expected['completeness']);
      }
      if (expected.containsKey('principalCny')) {
        final breakdown = _loanBreakdown(input);
        expect(
          breakdown.principal?.toFixed(2),
          expected['principalCny'],
        );
        expect(
          breakdown.interest?.toFixed(2),
          expected['interestCny'],
        );
      }
    });
  }
}

Rational _run(String operation, Map<String, dynamic> input) {
  switch (operation) {
    case 'wage':
      return wageFor(
        monthlyCny: _money(input['monthlyCny']),
        monthlyPaidSeconds: _int(input['monthlyPaidSeconds']),
        elapsedPaidSeconds: _int(input['elapsedPaidSeconds']),
      );
    case 'allocation':
      return _allocation(
        monthlyCny: _money(input['monthlyCny']),
        monthDays: _int(input['monthDays']),
        elapsedDaySeconds: _int(input['elapsedDaySeconds']),
        daySeconds: _int(input['daySeconds']),
      );
    case 'loanBreakdown':
      return _allocation(
        monthlyCny: _money(input['monthlyCny']),
        monthDays: _int(input['monthDays']),
        elapsedDaySeconds: _int(input['elapsedDaySeconds']),
        daySeconds: _int(input['daySeconds']),
      );
    case 'pnl':
      final quantity = _money(input['quantity']);
      if (quantity.isZero) return Rational.zero;
      final price = input['price'];
      final baseline = input['baseline'];
      if (price == null || baseline == null) {
        throw StateError('pnl requires price and baseline unless quantity is 0');
      }
      return (_money(price) - _money(baseline)) * quantity;
    case 'dashboard':
      final salary = wageFor(
        monthlyCny: _money(input['monthlySalaryCny']),
        monthlyPaidSeconds: _int(input['monthlyPaidSeconds']),
        elapsedPaidSeconds: _int(input['elapsedPaidSeconds']),
      );
      final fixed = _money(input['housingMonthlyCny']) +
          _money(input['carMonthlyCny']);
      final expense = _allocation(
        monthlyCny: fixed,
        monthDays: _int(input['monthDays']),
        elapsedDaySeconds: _int(input['elapsedDaySeconds']),
        daySeconds: _int(input['daySeconds']),
      );
      final stock = input['stockDailyCny'] == null
          ? Rational.zero
          : _money(input['stockDailyCny']);
      final gold = input['goldDailyCny'] == null
          ? Rational.zero
          : _money(input['goldDailyCny']);
      final fund = input['fundDailyCny'] == null
          ? Rational.zero
          : _money(input['fundDailyCny']);
      return salary + stock + gold + fund - expense;
    case 'fundHeld':
      return _runFund(input).heldPnl!;
    case 'fundDaily':
      return _runFund(input).dailyPnl!;
    case 'monthAllocation':
      return _allocation(
        monthlyCny: _money(input['monthlyCny']),
        monthDays: _int(input['monthDays']),
        elapsedDaySeconds: _int(input['monthDays']) * 86400,
        daySeconds: 86400,
      );
    case 'closedStockDay':
      final statisticsDate = LocalDate.parse(input['statisticsDate'] as String);
      final tradingDate = LocalDate.parse(input['tradingDate'] as String);
      expect(tradingDate < statisticsDate, isTrue);
      return Rational.zero;
    case 'splitWage':
      var total = Rational.zero;
      for (final part in (input['parts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        total += wageFor(
          monthlyCny: _money(part['monthlyCny']),
          monthlyPaidSeconds: _int(part['monthlyPaidSeconds']),
          elapsedPaidSeconds: _int(part['elapsedPaidSeconds']),
        );
      }
      return total;
    case 'housingSwitch':
      final monthDays = _int(input['monthDays']);
      final parts = (input['parts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
      expect(
        parts.fold<int>(0, (sum, part) => sum + _int(part['fullDays'])),
        monthDays,
      );
      var total = Rational.zero;
      for (final part in parts) {
        total += _money(part['monthlyCny']) /
            Rational.fromInt(monthDays) *
            Rational.fromInt(_int(part['fullDays']));
      }
      return total;
    case 'sum':
      var total = Rational.zero;
      for (final value in (input['values'] as List<dynamic>)) {
        total += _money(value);
      }
      return total;
    default:
      throw ArgumentError('Unknown fixture operation $operation');
  }
}

({Rational? principal, Rational? interest}) _loanBreakdown(
  Map<String, dynamic> input,
) {
  final total = _allocation(
    monthlyCny: _money(input['monthlyCny']),
    monthDays: _int(input['monthDays']),
    elapsedDaySeconds: _int(input['elapsedDaySeconds']),
    daySeconds: _int(input['daySeconds']),
  );
  final principalInput = input['principalCny'];
  if (principalInput == null) {
    return (principal: null, interest: null);
  }
  final principal = _allocation(
    monthlyCny: _money(principalInput),
    monthDays: _int(input['monthDays']),
    elapsedDaySeconds: _int(input['elapsedDaySeconds']),
    daySeconds: _int(input['daySeconds']),
  );
  return (principal: principal, interest: total - principal);
}

String _completenessOf(Map<String, dynamic> input) {
  final fundKnown = input['fundDailyKnown'] as bool? ?? true;
  final complete = input['stockDailyCny'] != null &&
      input['goldDailyCny'] != null &&
      fundKnown;
  return complete ? 'complete' : 'partial';
}

/// Runs a fund case through the real [AssetCalculator], not a copy of it.
AssetPosition _runFund(Map<String, dynamic> input) {
  final statisticsDate = LocalDate.parse(input['statisticsDate'] as String);
  final navDate = LocalDate.parse(input['navDate'] as String);
  const instrumentId = 'FUND.CN.000001';
  final previousNav = input['previousNav'];
  final result = const AssetCalculator().calculate(
    asOfUtc: DateTime.utc(2026, 11, 9, 12),
    statisticsDate: statisticsDate,
    holdings: [
      Holding(
        id: 'fund-fixture',
        instrumentId: instrumentId,
        quantity: _money(input['quantity']),
        costPerUnit: _money(input['cost']),
        effectiveFromUtc: DateTime.utc(2020),
      ),
    ],
    quotes: const {},
    marketCalendar: const MarketCalendar({}),
    fundNavs: {
      instrumentId: FundNavSnapshot(
        instrumentId: instrumentId,
        navCny: _money(input['nav']),
        navDate: navDate,
        previousNavCny:
            previousNav == null ? null : _money(previousNav),
        previousNavDate: input['previousNavDate'] == null
            ? null
            : LocalDate.parse(input['previousNavDate'] as String),
        actionStatus: FundActionStatus.none,
        fundCalendar: FundCalendarKind.mainland,
        eligibility: FundEligibility.supported,
        fetchedAtUtc: DateTime.utc(2026, 11, 9, 12),
        publishedAtUtc: null,
        source: 'fixture',
        sourceRevision: null,
        quality: QuoteQuality.eod,
        sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
      ),
    },
    fundCalendar: MarketCalendar({
      statisticsDate: input['statisticsDayOpen'] == true
          ? MarketDayStatus.open
          : MarketDayStatus.closed,
    }),
  );
  return result.positions.single;
}

Rational _allocation({
  required Rational monthlyCny,
  required int monthDays,
  required int elapsedDaySeconds,
  required int daySeconds,
}) =>
    monthlyCny /
    Rational.fromInt(monthDays) *
    Rational.fromInt(elapsedDaySeconds) /
    Rational.fromInt(daySeconds);

Rational _money(Object? value) {
  if (value is String) return Rational.parse(value);
  if (value is num) return Rational.parse(value.toString());
  throw ArgumentError('Expected a decimal string, got $value');
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw ArgumentError('Expected an integer, got $value');
}
