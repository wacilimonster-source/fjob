import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:finance_core/finance_core.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:test/test.dart';

const ledgerId = '29a28961-3eb3-46ed-b4a3-f3a45c6e7fe7';
final now = DateTime.utc(2026, 11, 4, 6, 36);

LedgerBundle bundle([LedgerState? ledger]) => LedgerBundle.fromLedger(
  ledger ?? buildDemoLedger(BusinessCalendar.shanghai, now),
  ledgerId: ledgerId, exportedAt: now, appVersion: '0.2.0', platform: 'android',
);

String signed(Map<String, dynamic> json) {
  final body = Map<String, dynamic>.of(json)..remove('checksum');
  return jsonEncode({...body,
    'checksum': 'sha256:${sha256.convert(utf8.encode(LedgerBundle.canonicalJson(body)))}'});
}

void main() {
  test('configuration round trip is exact; caches/device preferences are absent', () {
    final demo = buildDemoLedger(BusinessCalendar.shanghai, now);
    final source = demo.copyWith(
      settings: demo.settings.copyWith(tone: AppTone.harsh, widgetPrivacy: true),
      instrumentNames: {'CN.SZ.000001': 'directory cache'},
      holdings: [...demo.holdings, Holding(id: 'fund', instrumentId: 'FUND.CN.000001',
        quantity: Rational.parse('1.2345'), costPerUnit: Rational.parse('0.1234'),
        effectiveFromUtc: now, pendingQuote: true)],
      bills: [MonthlyBill(expenseId: 'demo-housing', kind: ExpenseKind.housing,
        month: const LocalDate(2026, 11, 1), monthlyAmountCny: null,
        principalCny: null, status: BillStatus.missing)],
    );
    final exported = bundle(source);
    final decoded = LedgerBundle.decode(exported.encode());
    expect(bundle(decoded.ledger).encode(), exported.encode());
    expect(decoded.ledger.holdings.last.quantity, Rational.parse('1.2345'));
    expect(decoded.ledger.bills.single.monthlyAmountCny, isNull);
    expect(decoded.ledger.bills.single.principalCny, isNull);
    expect(decoded.ledger.quotes, isEmpty);
    expect(decoded.ledger.fundNavs, isEmpty);
    expect(decoded.ledger.instrumentNames, isEmpty);
    expect(decoded.ledger.settings.widgetPrivacy, isFalse);
    expect(decoded.encode(), isNot(contains('widgetPrivacy')));
    expect(decoded.encode(), isNot(contains('directory cache')));
    expect(decoded.encode(), isNot(contains('marketCalendar')));
    expect(decoded.ledger.settings.sampleMode, isFalse);
    decoded.ledger.holdings.clear();
    decoded.toJson()['ledgerRevision'] = 999;
    expect(decoded.encode(), exported.encode());
    expect(decoded.ledger.holdings, hasLength(3));
  });

  test('recursive key sorting agrees with independent SHA256; whitespace irrelevant', () {
    final original = bundle();
    final json = original.toJson();
    final reversed = {for (final key in json.keys.toList().reversed) key: json[key]};
    expect(LedgerBundle.decode(const JsonEncoder.withIndent('  ').convert(reversed)).encode(), original.encode());
    expect(LedgerBundle.canonicalJson({'z': {'b': 2, 'a': 1}, 'a': []}), '{"a":[],"z":{"a":1,"b":2}}');
    expect(LedgerBundle.decode(signed(json)).checksum, original.checksum);
  });

  test('tampering and unsupported versions fail without exposing amounts', () {
    expect(() => LedgerBundle.decode(bundle().encode().replaceFirst('12000', '13000')), throwsFormatException);
    final json = bundle().toJson()..['formatVersion'] = 2;
    expect(() => LedgerBundle.decode(signed(json)), throwsFormatException);
    expect(() => LedgerBundle.decode('[]'), throwsFormatException);
  });

  final invalidDecimals = <Object?>['', 'unknown', 'NaN', 'Infinity', '-1', '-0',
    '00', '01', '1.0', '1e2', ' 1', '1.', '.1', '1.001', '10000000.01', 1, null];
  for (final value in invalidDecimals) {
    test('rejects noncanonical/out-of-range salary ${jsonEncode(value)}', () {
      final j = bundle().toJson();
      (j['salaryVersions'] as List).first['monthlyNetCny'] = value;
      expect(() => LedgerBundle.decode(signed(j)), throwsFormatException);
    });
  }

  final corruptions = <String, void Function(Map<String, dynamic>)>{
    'unknown root field': (j) => j['deviceId'] = 'x',
    'UI preferences not synchronized': (j) => j['settings']['widgetPrivacy'] = true,
    'nested quote injection': (j) => j['holdingVersions'][0]['priceCny'] = '1',
    'missing explicit nullable field': (j) => j['monthlyBills'][0].remove('principalCny'),
    'invalid business date': (j) => j['monthlyBills'][0]['month'] = '2026-02-30',
    'not first of month': (j) => j['monthlyBills'][0]['month'] = '2026-11-02',
    'invalid UTC day': (j) => j['salaryVersions'][0]['effectiveFrom'] = '2026-02-30T00:00:00Z',
    'local timestamp': (j) => j['exportedAt'] = '2026-11-04T06:36:00',
    'invalid hour': (j) => j['exportedAt'] = '2026-11-04T24:00:00Z',
    'invalid timezone': (j) => j['timezone'] = 'Unknown/Nowhere',
    'empty period': (j) => j['salaryVersions'][0]['effectiveTo'] = j['salaryVersions'][0]['effectiveFrom'],
    'missing salary reference': (j) => j['salaryVersions'][0]['scheduleVersionId'] = 'missing',
    'salary outlives schedule': (j) => j['scheduleVersions'][0]['effectiveTo'] = '2026-12-01T00:00:00Z',
    'dangling bill': (j) => j['monthlyBills'][0]['expenseId'] = 'missing',
    'principal exceeds payment': (j) => j['monthlyBills'][0]['principalCny'] = '4801',
    'unknown principal string': (j) => j['monthlyBills'][0]['principalCny'] = 'unknown',
    'unknown is not zero': (j) => j['monthlyBills'][0]['monthlyAmountCny'] = '',
    'rent has no principal': (j) => j['housingVersions'][0]['mode'] = 'rent',
    'unknown enum': (j) => j['housingVersions'][0]['mode'] = 'unknown',
    'fractional revision': (j) => j['ledgerRevision'] = 1.5,
    'negative revision': (j) => j['ledgerRevision'] = -1,
    'unknown instrument': (j) => j['holdingVersions'][0]['instrumentId'] = 'UNKNOWN.000001',
    'wrong stock market': (j) => j['holdingVersions'][0]['instrumentId'] = 'CN.SH.000001',
    'nonintegral stock': (j) => j['holdingVersions'][0]['quantity'] = '1.2',
    'too precise gold': (j) => j['holdingVersions'][1]['quantity'] = '1.0001',
    'duplicate id': (j) => j['salaryVersions'].add(j['salaryVersions'][0]),
    'overlapping salary versions': (j) => j['salaryVersions'].add({...j['salaryVersions'][0], 'id': 'other'}),
    'overlapping housing': (j) => j['housingVersions'].add({...j['housingVersions'][0], 'id': 'other'}),
    'duplicate bill': (j) => j['monthlyBills'].add(j['monthlyBills'][0]),
    'invalid boolean': (j) => j['carVersions'][0]['enabled'] = 1,
    'malformed weekly day': (j) => j['scheduleVersions'][0]['week']['mondayFirst'][0] = null,
    'paid overlap': (j) => j['scheduleVersions'][0]['week']['mondayFirst'][0].add({'start': 600, 'end': 660, 'breaks': []}),
    'cross-midnight overlap': (j) => j['scheduleVersions'][0]['week']['mondayFirst'][0] = [{'start': 1320, 'end': 2040, 'breaks': []}],
    'positive salary zero denominator': (j) => j['scheduleVersions'][0]['week']['mondayFirst'] = List.generate(7, (_) => []),
  };
  for (final entry in corruptions.entries) {
    test('strict input: ${entry.key}', () {
      final json = bundle().toJson();
      entry.value(json);
      expect(() => LedgerBundle.decode(signed(json)), throwsFormatException);
    });
  }

  test('fund precision, ranges, identity and no imported eligibility assertion', () {
    final source = buildDemoLedger(BusinessCalendar.shanghai, now);
    final j = bundle(source.copyWith(holdings: [Holding(id: 'fund', instrumentId: 'FUND.CN.000001',
      quantity: Rational.parse('10000000'), costPerUnit: Rational.parse('100000'), effectiveFromUtc: now)])).toJson();
    expect(LedgerBundle.decode(signed(j)).ledger.holdings.single.kind, InstrumentKind.fund);
    for (final pair in [('quantity', '10000000.0001'), ('costPerUnit', '100000.0001'),
      ('quantity', '0.00001'), ('instrumentId', 'FUND.CN.1'), ('eligibility', 'supported')]) {
      final bad = jsonDecode(jsonEncode(j)) as Map<String, dynamic>;
      bad['holdingVersions'][0][pair.$1] = pair.$2;
      expect(() => LedgerBundle.decode(signed(bad)), throwsFormatException);
    }
  });

  test('date overrides and alternation survive; neighboring override overlap fails', () {
    final demo = buildDemoLedger(BusinessCalendar.shanghai, now);
    final schedule = demo.schedules.values.single;
    final small = WeekTemplate.standardOffice();
    final big = WeekTemplate([...small.byWeekday.take(5), small.byWeekday.first, []]);
    final modified = demo.copyWith(schedules: {schedule.id: ScheduleVersion(
      id: schedule.id, timezone: schedule.timezone, week: small,
      alternation: WeekAlternation(smallWeek: small, bigWeek: big, anchorMonday: const LocalDate(2026, 11, 2)),
      effectiveFromUtc: schedule.effectiveFromUtc,
    )}, overrides: [const ScheduleOverride(localDate: LocalDate(2026, 11, 4), paidIntervals: [], reason: 'rest')]);
    final restored = bundle(modified).ledger;
    expect(restored.schedules.values.single.alternation!.anchorMonday, const LocalDate(2026, 11, 2));
    expect(restored.overrides.single.isRestDay, isTrue);
    final j = bundle(modified).toJson();
    j['scheduleOverrides'][0]['paidIntervals'] = [{'start': 1320, 'end': 2100}];
    expect(() => LedgerBundle.decode(signed(j)), throwsFormatException);
  });

  test('whole-package merge rejects conflicts, including overlaps with distinct IDs', () {
    final a = bundle();
    expect(a.mergedWith(a).ledger.holdings, hasLength(2));
    final j = a.toJson();
    j['holdingVersions'][0]['quantity'] = '100';
    expect(() => a.mergedWith(LedgerBundle.decode(signed(j))), throwsA(isA<LedgerMergeConflictException>()));
    j['holdingVersions'][0]['id'] = 'distinct-id';
    expect(() => a.mergedWith(LedgerBundle.decode(signed(j))), throwsFormatException);
    final extra = bundle(LedgerState.empty().copyWith(holdings: [Holding(id: 'fund',
      instrumentId: 'FUND.CN.000001', quantity: Rational.one, costPerUnit: Rational.one,
      effectiveFromUtc: now)]));
    expect(a.mergedWith(extra).ledger.holdings, hasLength(3));
  });
}
