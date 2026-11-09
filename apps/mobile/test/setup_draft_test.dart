import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/domain/ledger.dart';
import 'package:todayagain/domain/setup_draft.dart';

void main() {
  SetupDraft fresh() =>
      SetupDraft.fresh('session', today: LocalDate(2026, 11, 4));

  test('salary is required and capped at two decimals', () {
    final draft = fresh();
    expect(draft.validate().errorFor('salary'), isNotNull);
    draft.salaryText = '12000.123';
    expect(draft.validate().errorFor('salary'), isNotNull);
    draft.salaryText = '10000001';
    expect(draft.validate().errorFor('salary'), isNotNull);
    draft.salaryText = '0';
    expect(draft.validate().errorFor('salary'), isNull);
    expect(draft.validate().isValid, isTrue);
  });

  test('zero salary allows an empty schedule', () {
    final draft = fresh()
      ..salaryText = '0'
      ..workdays = List<bool>.filled(7, false);
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    expect(validation.commit!.week.hasAnyShift, isFalse);
  });

  test('a positive salary without any paid interval is blocked', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..workdays = List<bool>.filled(7, false);
    expect(
      draft.validate().errorFor('schedule'),
      contains('这个月没有计薪时段'),
    );
  });

  test('a break outside the shift is rejected with a readable message', () {
    final draft = fresh()..breakStart = '07:00';
    expect(
      draft.validate().errorFor('schedule'),
      contains('午休请安排在上下班之间'),
    );
  });

  test('cross-midnight shifts are expanded to the next day', () {
    final draft = fresh()
      ..shiftStart = '22:00'
      ..shiftEnd = '06:00'
      ..breakEnabled = false;
    final week = draft.buildWeek();
    final shift = week.byWeekday.first.single;
    expect(shift.startMinute, 22 * 60);
    expect(shift.endMinute, 30 * 60);
    expect(shift.paidIntervals().single.durationMinutes, 8 * 60);
  });

  test('mortgage principal above the monthly amount is rejected', () {
    final draft = fresh()
      ..housingMode = HousingMode.mortgage
      ..mortgageMonthlyText = '4800'
      ..mortgagePrincipalText = '5000';
    expect(
      draft.validate().errorFor('housing'),
      contains('本金超过了本月月供'),
    );
  });

  test('unknown principal stays null while zero is explicit', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..housingMode = HousingMode.mortgage
      ..mortgageMonthlyText = '4800';
    expect(draft.validate().commit!.housingPrincipal, isNull);
    draft.mortgagePrincipalText = '0';
    expect(draft.validate().commit!.housingPrincipal, Rational.zero);
  });

  test('duplicate instruments in the same market are rejected', () {
    final draft = fresh()
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '100',
          costText: '12',
        ),
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '200',
          costText: '11',
        ),
      ];
    expect(
      draft.validate().errorFor('holdings'),
      contains('同一市场的同一代码'),
    );
  });

  test('stock quantity is a non-negative integer and cost allows 3 decimals',
      () {
    final draft = fresh()
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.sse,
          code: '600000',
          quantityText: '10.5',
          costText: '9.855',
        ),
      ];
    expect(draft.validate().errorFor('holdings'), contains('非负整数'));
    draft.holdings = [
      const HoldingDraft(
        market: StockMarket.sse,
        code: '600000',
        quantityText: '100',
        costText: '9.855',
      ),
    ];
    expect(draft.validate().errorFor('holdings'), isNull);
  });

  test('gold accepts three decimals for grams', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..goldEnabled = true
      ..goldQuantityText = '20.125'
      ..goldCostText = '850.50';
    final commit = draft.validate().commit!;
    expect(commit.goldQuantity, Rational.parse('20.125'));
    expect(commit.goldCost, Rational.parse('850.50'));
  });

  test('the draft round-trips through JSON', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..housingMode = HousingMode.rent
      ..rentMonthlyText = '3000'
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.bse,
          code: '430047',
          name: '示例',
          quantityText: '500',
          costText: '18.5',
        ),
      ];
    final restored = SetupDraft.fromJson(draft.toJson());
    expect(restored.salaryText, '12000');
    expect(restored.housingMode, HousingMode.rent);
    expect(restored.holdings.single.instrumentId, 'CN.BJ.430047');
    expect(restored.rentMonthlyText, '3000');
  });

  test('fund shares and unit cost keep four decimals and allow zero', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..holdings = [
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          name: '华夏成长混合',
          quantityText: '1000.2500',
          costText: '1.2000',
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    final commit = validation.commit!.holdings.single;
    expect(commit.instrumentId, 'FUND.CN.000001');
    expect(commit.quantity, Rational.parse('1000.25'));
    expect(commit.costPerUnit, Rational.parse('1.2'));

    draft.holdings = [
      const HoldingDraft(
        kind: HoldingKind.fund,
        code: '000001',
        quantityText: '0',
        costText: '0.0000',
      ),
    ];
    expect(draft.validate().isValid, isTrue);
  });

  test('fund input rejects five decimals, negatives and over-limit values', () {
    HoldingDraft fund(String quantity, String cost) => HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          quantityText: quantity,
          costText: cost,
        );
    final draft = fresh()
      ..salaryText = '12000'
      ..holdings = [fund('1000.25001', '1.2')];
    expect(draft.validate().errorFor('holdings'), contains('最多四位小数'));

    draft.holdings = [fund('-1', '1.2')];
    expect(draft.validate().errorFor('holdings'), contains('最多四位小数'));

    draft.holdings = [fund('10000000.0001', '1.2')];
    expect(draft.validate().errorFor('holdings'), contains('10,000,000'));

    draft.holdings = [fund('100', '100000.0001')];
    expect(draft.validate().errorFor('holdings'), contains('100,000'));
  });

  test('a stock and a fund may share the same six-digit code', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..holdings = [
        const HoldingDraft(
          market: StockMarket.szse,
          code: '000001',
          quantityText: '100',
          costText: '12',
        ),
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          quantityText: '1000.25',
          costText: '1.2',
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    expect(
      validation.commit!.holdings.map((holding) => holding.instrumentId),
      containsAll(['CN.SZ.000001', 'FUND.CN.000001']),
    );
  });

  test('duplicate fund codes are rejected', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..holdings = [
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          quantityText: '1',
          costText: '1',
        ),
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          quantityText: '2',
          costText: '1',
        ),
      ];
    expect(draft.validate().errorFor('holdings'), contains('同一基金代码'));
  });

  test('different fund codes (A/C shares) are separate holdings', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..holdings = [
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000001',
          quantityText: '1000.25',
          costText: '1.2',
        ),
        const HoldingDraft(
          kind: HoldingKind.fund,
          code: '000002',
          quantityText: '2000.5',
          costText: '1.1',
        ),
      ];
    final validation = draft.validate();
    expect(validation.isValid, isTrue);
    expect(validation.commit!.holdings, hasLength(2));
    expect(
      validation.commit!.holdings.map((holding) => holding.instrumentId),
      ['FUND.CN.000001', 'FUND.CN.000002'],
    );
  });

  test('old drafts without a kind decode as stocks', () {
    final restored = HoldingDraft.fromJson({
      'market': 'sse',
      'code': '600000',
      'name': '浦发银行',
      'quantity': '100',
      'cost': '9.855',
    });
    expect(restored.kind, HoldingKind.stock);
    expect(restored.pendingQuote, isFalse);
    expect(restored.instrumentId, 'CN.SH.600000');
  });

  test('fund drafts round-trip kind, precision and pending state', () {
    final restored = HoldingDraft.fromJson({
      'kind': 'fund',
      'code': '000001',
      'name': '华夏成长混合',
      'quantity': '1000.2500',
      'cost': '1.2000',
      'pendingQuote': true,
    });
    expect(restored.kind, HoldingKind.fund);
    expect(restored.instrumentId, 'FUND.CN.000001');
    expect(restored.pendingQuote, isTrue);
    expect(restored.quantityText, '1000.2500');
  });

  test('redo prefill keeps funds, names, precision and pending state', () {
    final calendar = BusinessCalendar.shanghai;
    final now = DateTime.utc(2026, 11, 4, 6, 36);
    final ledger = LedgerState(
      settings: const AppSettings(
        ledgerRevision: 4,
        onboardingCompletedAt: null,
      ),
      salaryVersions: const [],
      schedules: const {},
      overrides: const [],
      holdings: [
        Holding(
          id: 'fund-1',
          instrumentId: 'FUND.CN.000001',
          quantity: Rational.parse('1000.25'),
          costPerUnit: Rational.parse('1.2'),
          effectiveFromUtc: DateTime.utc(2026, 1, 1),
          pendingQuote: true,
        ),
        Holding(
          id: 'stock-1',
          instrumentId: 'CN.SZ.000001',
          quantity: Rational.parse('100'),
          costPerUnit: Rational.parse('12'),
          effectiveFromUtc: DateTime.utc(2026, 1, 1),
        ),
      ],
      housingVersions: const [],
      carVersions: const [],
      bills: const [],
      quotes: const {},
      marketCalendar: MarketCalendar({}),
      instrumentNames: const {
        'FUND.CN.000001': '华夏成长混合',
        'CN.SZ.000001': '平安银行',
      },
    );
    final draft = SetupDraft.fromLedger(
      ledger,
      'redo-session',
      today: calendar.dateOf(now),
      nowUtc: now,
    );
    expect(draft.holdings, hasLength(2));
    final fund = draft.holdings.firstWhere((item) => item.isFund);
    expect(fund.code, '000001');
    expect(fund.name, '华夏成长混合');
    expect(fund.quantityText, '1000.25');
    expect(fund.costText, '1.2');
    expect(fund.pendingQuote, isTrue);
    final stock = draft.holdings.firstWhere((item) => !item.isFund);
    expect(stock.instrumentId, 'CN.SZ.000001');
    expect(stock.quantityText, '100');
  });

  test('大小周 supports custom core days and an anchor flip', () {
    final draft = fresh()
      ..salaryText = '12000'
      ..scheduleMode = ScheduleMode.bigSmall
      ..workdays = [true, true, true, true, false, false, false]
      ..extraSaturday = true
      ..anchorMonday = '2026-11-02'
      ..anchorIsBig = true;
    final schedule = draft.buildSchedule();
    expect(schedule.alternation, isNotNull);
    expect(schedule.week.byWeekday[4], isEmpty); // Friday is not core
    expect(schedule.alternation!.bigWeek.byWeekday[5], isNotEmpty);
    expect(
      schedule.alternation!.isBigWeek(LocalDate(2026, 11, 2)),
      isTrue,
    );

    draft.anchorIsBig = false;
    final flipped = draft.buildSchedule();
    expect(
      flipped.alternation!.isBigWeek(LocalDate(2026, 11, 2)),
      isFalse,
    );
  });
}
