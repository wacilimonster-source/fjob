import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
