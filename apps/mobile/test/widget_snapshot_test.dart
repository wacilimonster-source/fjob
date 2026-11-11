import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/data/widget_snapshot.dart';
import 'package:ledger_model/ledger_model.dart';

import 'support/test_env.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final schema = readWidgetSchema();
  final properties = schema['properties'] as Map<String, dynamic>;
  final required = (schema['required'] as List<dynamic>).cast<String>();
  final amountDefs = schema[r'$defs'] as Map<String, dynamic>;
  final amountRequired =
      (amountDefs['amounts']['required'] as List<dynamic>).cast<String>();
  final amountPattern =
      RegExp(amountDefs['amount']['pattern'] as String);
  final extrasAllowed = schema['additionalProperties'] as bool? ?? true;

  void validateEntry(Map<String, dynamic> entry) {
    for (final key in required) {
      expect(entry.containsKey(key), isTrue, reason: 'missing $key');
    }
    if (!extrasAllowed) {
      expect(
        entry.keys.toSet().difference(properties.keys.toSet()),
        isEmpty,
        reason: 'additional properties are forbidden',
      );
    }
    expect(entry['schemaVersion'], properties['schemaVersion']['const']);
    expect(entry['ledgerRevision'], isA<int>());
    expect(entry['ledgerRevision'] as int, greaterThanOrEqualTo(0));
    expect(entry['privacy'], isA<bool>());
    expect(entry['tombstone'], isA<bool>());
    for (final key in [
      'completeness',
      'quoteQuality',
      'housingMode',
      'scene',
      'deepLink',
    ]) {
      final allowed = (properties[key]['enum'] as List<dynamic>).cast<String>();
      expect(allowed, contains(entry[key]), reason: key);
    }
    for (final key in ['createdAt', 'computedAt', 'validUntil']) {
      expect(DateTime.tryParse(entry[key]! as String), isNotNull, reason: key);
    }
    final quotesAsOf = entry['quotesAsOf'];
    if (quotesAsOf != null) {
      expect(DateTime.tryParse(quotesAsOf as String), isNotNull);
    }
    expect((entry['timezone'] as String), isNotEmpty);
    expect((entry['caption'] as String).length, lessThanOrEqualTo(100));

    final amounts = entry['amounts'] as Map<String, dynamic>;
    expect(amounts.keys.toSet(), amountRequired.toSet());
    for (final value in amounts.values) {
      if (value == null) continue;
      expect(amountPattern.hasMatch(value as String), isTrue, reason: value);
    }
    if (entry['privacy'] == true) {
      for (final value in amounts.values) {
        expect(value, isNull, reason: 'privacy must null all amounts');
      }
      final caption = entry['caption'] as String;
      expect(RegExp(r'[0-9¥]').hasMatch(caption), isFalse,
          reason: 'private caption must not leak money');
    }
    if (entry['tombstone'] == true) {
      expect(entry['completeness'], 'unavailable');
      expect(entry['privacy'], isTrue);
    }
  }

  void validateTimeline(Map<String, dynamic> timeline) {
    expect(timeline['timelineVersion'], 1);
    expect(timeline['ledgerRevision'], isA<int>());
    final entries = (timeline['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(entries, isNotEmpty);
    expect(entries.length, lessThanOrEqualTo(289));
    for (final entry in entries) {
      validateEntry(entry);
    }
    final first = DateTime.parse(entries.first['computedAt'] as String);
    final last = DateTime.parse(entries.last['computedAt'] as String);
    expect(last.difference(first).inHours, lessThanOrEqualTo(24));
  }

  test('v2 carries the pre-computed stock+fund sum and a real NAV date', () {
    final demo = buildDemoLedger(calendar, fixedNow);
    final ledger = demo.copyWith(
      holdings: [
        ...demo.holdings,
        Holding(
          id: 'fund-1',
          instrumentId: 'FUND.CN.000001',
          quantity: Rational.parse('1000.25'),
          costPerUnit: Rational.parse('1.2'),
          effectiveFromUtc: DateTime.utc(2026, 1, 1),
        ),
      ],
      fundNavs: {
        'FUND.CN.000001': FundNavSnapshot(
          instrumentId: 'FUND.CN.000001',
          navCny: Rational.parse('1.2356'),
          navDate: LocalDate(2026, 11, 4),
          previousNavCny: Rational.parse('1.2256'),
          previousNavDate: LocalDate(2026, 11, 3),
          actionStatus: FundActionStatus.none,
          fundCalendar: FundCalendarKind.mainland,
          eligibility: FundEligibility.supported,
          fetchedAtUtc: fixedNow,
          publishedAtUtc: null,
          source: 'fixture',
          sourceRevision: null,
          quality: QuoteQuality.eod,
          sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
        ),
      },
      fundCalendar: demo.marketCalendar,
    );
    final calculator = DashboardCalculator(calendar);
    final snapshot = calculator.calculate(
      ledger.toCalculationInput(calendar: calendar, nowUtc: fixedNow),
    );
    expect(snapshot.quotesAsOf, isNull);
    final entry = WidgetSnapshotBuilder.entry(
      snapshot: snapshot,
      privacy: false,
      timezone: calendar.timezoneName,
      tone: AppTone.gentle,
    );
    validateEntry(entry);
    expect(entry['schemaVersion'], 2);
    expect(entry['amounts']['stockFundDaily'], '-340.00');
    expect(entry['amounts']['stockDaily'], '-350.00');
    expect(entry['fundNavDate'], '2026-11-04');
    expect(entry['quotesAsOf'], isNull);
  });

  test('v2 privacy nulls stockFundDaily as well', () {
    final demo = buildDemoLedger(calendar, fixedNow);
    final calculator = DashboardCalculator(calendar);
    final snapshot = calculator.calculate(
      demo.toCalculationInput(calendar: calendar, nowUtc: fixedNow),
    );
    final entry = WidgetSnapshotBuilder.entry(
      snapshot: snapshot,
      privacy: true,
      timezone: calendar.timezoneName,
      tone: AppTone.harsh,
    );
    validateEntry(entry);
    expect(entry['amounts']['stockFundDaily'], isNull);
  });

  test('a future timeline entry never predicts a new fund NAV', () {
    final lateNow = DateTime.utc(2026, 11, 4, 15, 50); // 23:50 Shanghai
    final demo = buildDemoLedger(calendar, lateNow);
    final ledger = demo.copyWith(
      holdings: [
        ...demo.holdings,
        Holding(
          id: 'fund-1',
          instrumentId: 'FUND.CN.000001',
          quantity: Rational.parse('1000.25'),
          costPerUnit: Rational.parse('1.2'),
          effectiveFromUtc: DateTime.utc(2026, 1, 1),
        ),
      ],
      fundNavs: {
        'FUND.CN.000001': FundNavSnapshot(
          instrumentId: 'FUND.CN.000001',
          navCny: Rational.parse('1.2356'),
          navDate: LocalDate(2026, 11, 4),
          previousNavCny: Rational.parse('1.2256'),
          previousNavDate: LocalDate(2026, 11, 3),
          actionStatus: FundActionStatus.none,
          fundCalendar: FundCalendarKind.mainland,
          eligibility: FundEligibility.supported,
          fetchedAtUtc: lateNow,
          publishedAtUtc: null,
          source: 'fixture',
          sourceRevision: null,
          quality: QuoteQuality.eod,
          sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
        ),
      },
      fundCalendar: demo.marketCalendar,
    );
    final timeline = WidgetSnapshotBuilder.timeline(
      ledger: ledger,
      calendar: calendar,
      calculator: DashboardCalculator(calendar),
      nowUtc: lateNow,
      privacy: false,
      tone: AppTone.gentle,
      stepMinutes: 30,
      horizonHours: 1,
    );
    final entries = (timeline['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(entries, hasLength(3));
    // The same-day entry can use the published NAV.
    expect(entries.first['fundNavDate'], '2026-11-04');
    expect(entries.first['amounts']['stockFundDaily'], isNotNull);
    // After midnight the NAV date is still 11-04 and today's move is unknown;
    // the snapshot must not invent 11-05's NAV or reuse 11-04's move.
    for (final entry in entries.skip(1)) {
      expect(entry['fundNavDate'], '2026-11-04');
      expect(entry['amounts']['stockFundDaily'], isNull);
      expect(entry['completeness'], 'partial');
    }
  });

  test('the v1 fixture still satisfies the retained v1 contract', () {
    final v1 = readWidgetSchemaV1();
    final fixture = readWidgetFixtureV1();
    expect(fixture['schemaVersion'], v1['properties']['schemaVersion']['const']);
    final v1AmountKeys = ((v1[r'$defs'] as Map<String, dynamic>)['amounts']
            as Map<String, dynamic>)['required'] as List<dynamic>;
    expect(
      (fixture['amounts'] as Map<String, dynamic>).keys.toSet(),
      v1AmountKeys.toSet(),
    );
    expect(v1AmountKeys, isNot(contains('stockFundDaily')));
  });

  test('timeline entries satisfy the widget snapshot contract', () {
    final ledger = buildDemoLedger(calendar, fixedNow);
    final calculator = DashboardCalculator(calendar);
    final timeline = WidgetSnapshotBuilder.timeline(
      ledger: ledger,
      calendar: calendar,
      calculator: calculator,
      nowUtc: fixedNow,
      privacy: false,
      tone: AppTone.gentle,
      stepMinutes: 30,
      horizonHours: 2,
    );
    validateTimeline(timeline);
  });

  test('the full 24 hour timeline stays within 289 entries', () {
    final ledger = buildDemoLedger(calendar, fixedNow);
    final calculator = DashboardCalculator(calendar);
    final stopwatch = Stopwatch()..start();
    final timeline = WidgetSnapshotBuilder.timeline(
      ledger: ledger,
      calendar: calendar,
      calculator: calculator,
      nowUtc: fixedNow,
      privacy: false,
      tone: AppTone.gentle,
    );
    stopwatch.stop();
    final entries = (timeline['entries'] as List<dynamic>);
    expect(entries, hasLength(289));
    validateTimeline(timeline);
    // The timeline is generated on save/manual refresh, not every tick.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('privacy removes every amount and never leaks digits', () {
    final ledger = buildDemoLedger(calendar, fixedNow);
    final calculator = DashboardCalculator(calendar);
    final timeline = WidgetSnapshotBuilder.timeline(
      ledger: ledger,
      calendar: calendar,
      calculator: calculator,
      nowUtc: fixedNow,
      privacy: true,
      tone: AppTone.harsh,
      stepMinutes: 60,
      horizonHours: 1,
    );
    validateTimeline(timeline);
    for (final entry
        in (timeline['entries'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(
        (entry['amounts'] as Map<String, dynamic>).values,
        everyElement(isNull),
      );
    }
  });

  test('the tombstone snapshot clears content and masks amounts', () {
    final tombstone = WidgetSnapshotBuilder.tombstone(
      ledgerRevision: 7,
      nowUtc: fixedNow,
      timezone: calendar.timezoneName,
    );
    validateTimeline(tombstone);
    final entry =
        (tombstone['entries'] as List<dynamic>).single as Map<String, dynamic>;
    expect(entry['tombstone'], isTrue);
    expect(entry['privacy'], isTrue);
    expect(entry['amounts']['total'], isNull);
    expect(entry['ledgerRevision'], 7);
  });
}
