/// CALC-EXPENSE: natural-day allocation of housing and car bills.
library;

import '../money/rational.dart';
import '../time/business_calendar.dart';
import '../time/local_date.dart';

enum HousingMode { mortgage, rent, none }

enum ExpenseKind { housing, car }

/// `confirmed` bills are user-supplied; `carriedForwardEstimate` repeats the
/// previous month with an explicit marker; `missing` keeps the amount unknown.
enum BillStatus { confirmed, carriedForwardEstimate, missing }

/// A monthly bill belonging to one expense plan version.
///
/// Bills reference the plan version rather than the kind, so a mid-month
/// housing switch can keep both plans' amounts without ambiguity.
final class MonthlyBill {
  const MonthlyBill({
    required this.expenseId,
    required this.kind,
    required this.month,
    required this.monthlyAmountCny,
    this.principalCny,
    this.status = BillStatus.confirmed,
    this.revision = 1,
    this.note,
  });

  final String expenseId;
  final ExpenseKind kind;

  /// First day of the billed month in the statistics timezone.
  final LocalDate month;
  final Rational? monthlyAmountCny;

  /// Null means the user has not supplied the principal yet; zero is an
  /// explicit "this month's principal is zero".
  final Rational? principalCny;
  final BillStatus status;
  final int revision;
  final String? note;

  bool get isEstimate => status == BillStatus.carriedForwardEstimate;

  bool get isUsable =>
      status != BillStatus.missing && monthlyAmountCny != null;

  MonthlyBill copyWith({
    Rational? monthlyAmountCny,
    Rational? principalCny,
    BillStatus? status,
    int? revision,
    String? note,
  }) =>
      MonthlyBill(
        expenseId: expenseId,
        kind: kind,
        month: month,
        monthlyAmountCny: monthlyAmountCny ?? this.monthlyAmountCny,
        principalCny: principalCny ?? this.principalCny,
        status: status ?? this.status,
        revision: revision ?? this.revision,
        note: note ?? this.note,
      );
}

sealed class ExpensePlanVersion {
  ExpensePlanVersion({
    required this.id,
    required this.effectiveFromUtc,
    this.effectiveToUtc,
  }) {
    if (effectiveToUtc != null && !effectiveToUtc!.isAfter(effectiveFromUtc)) {
      throw ArgumentError('effectiveToUtc must be after effectiveFromUtc');
    }
  }

  final String id;
  final DateTime effectiveFromUtc;
  final DateTime? effectiveToUtc;

  ExpenseKind get kind;

  /// False for `housing mode none` and for a disabled car loan.
  bool get isActive;

  bool covers(DateTime instantUtc) =>
      !instantUtc.isBefore(effectiveFromUtc) &&
      (effectiveToUtc == null || instantUtc.isBefore(effectiveToUtc!));

  bool overlaps(DateTime fromUtc, DateTime toUtc) =>
      fromUtc.isBefore(effectiveToUtc ?? DateTime.utc(9999)) &&
      effectiveFromUtc.isBefore(toUtc);
}

final class HousingVersion extends ExpensePlanVersion {
  HousingVersion({
    required super.id,
    required this.mode,
    required super.effectiveFromUtc,
    super.effectiveToUtc,
  });

  final HousingMode mode;

  @override
  ExpenseKind get kind => ExpenseKind.housing;

  @override
  bool get isActive => mode != HousingMode.none;
}

final class CarVersion extends ExpensePlanVersion {
  CarVersion({
    required super.id,
    required this.enabled,
    required super.effectiveFromUtc,
    super.effectiveToUtc,
  });

  final bool enabled;

  @override
  ExpenseKind get kind => ExpenseKind.car;

  @override
  bool get isActive => enabled;
}

/// Allocation totals for one expense kind, for today and month-to-date.
final class ExpenseBreakdown {
  const ExpenseBreakdown({
    required this.kind,
    required this.housingMode,
    required this.configured,
    required this.amountKnown,
    required this.breakdownKnown,
    required this.estimate,
    required this.monthDays,
    required this.dayShare,
    required this.monthlyAmount,
    required this.dayAmount,
    required this.monthToDateAmount,
    required this.dayPrincipal,
    required this.monthToDatePrincipal,
    required this.dayInterest,
    required this.monthToDateInterest,
    required this.dayRent,
    required this.monthToDateRent,
    required this.missingMonths,
    required this.activePlanId,
  });

  factory ExpenseBreakdown.notConfigured({
    required ExpenseKind kind,
    required HousingMode? housingMode,
    required int monthDays,
  }) =>
      ExpenseBreakdown(
        kind: kind,
        housingMode: housingMode,
        configured: false,
        amountKnown: true,
        breakdownKnown: true,
        estimate: false,
        monthDays: monthDays,
        dayShare: Rational.zero,
        monthlyAmount: null,
        dayAmount: Rational.zero,
        monthToDateAmount: Rational.zero,
        dayPrincipal: Rational.zero,
        monthToDatePrincipal: Rational.zero,
        dayInterest: Rational.zero,
        monthToDateInterest: Rational.zero,
        dayRent: Rational.zero,
        monthToDateRent: Rational.zero,
        missingMonths: const <String>[],
        activePlanId: null,
      );

  final ExpenseKind kind;
  final HousingMode? housingMode;

  /// A plan of this kind is active at the as-of instant.
  final bool configured;
  final bool amountKnown;
  final bool breakdownKnown;

  /// At least one day used a carried-forward estimate.
  final bool estimate;
  final int monthDays;
  final Rational dayShare;
  final Rational? monthlyAmount;
  final Rational? dayAmount;
  final Rational? monthToDateAmount;
  final Rational? dayPrincipal;
  final Rational? monthToDatePrincipal;
  final Rational? dayInterest;
  final Rational? monthToDateInterest;
  final Rational? dayRent;
  final Rational? monthToDateRent;

  /// Month keys (`YYYY-MM`) that needed a bill but had none.
  final List<String> missingMonths;
  final String? activePlanId;

  /// True when the housing plan is rent, so the UI labels the amount as rent.
  bool get isRent => housingMode == HousingMode.rent;
}

final class ExpenseCalculator {
  ExpenseCalculator(this.calendar);

  final BusinessCalendar calendar;

  ExpenseBreakdown housing({
    required DateTime asOfUtc,
    required List<HousingVersion> versions,
    required List<MonthlyBill> bills,
  }) =>
      _breakdown(
        kind: ExpenseKind.housing,
        asOfUtc: asOfUtc,
        plans: versions,
        bills: bills,
        housingModeOf: (plan) =>
            plan is HousingVersion ? plan.mode : null,
      );

  ExpenseBreakdown car({
    required DateTime asOfUtc,
    required List<CarVersion> versions,
    required List<MonthlyBill> bills,
  }) =>
      _breakdown(
        kind: ExpenseKind.car,
        asOfUtc: asOfUtc,
        plans: versions,
        bills: bills,
        housingModeOf: (plan) => null,
      );

  /// Full-month allocation of the housing plans for [month].
  ///
  /// Returns null when a needed bill is missing. With a stable plan the result
  /// equals the monthly amount, which is the CALC-EXPENSE conservation check.
  Rational? housingMonthTotal({
    required LocalDate month,
    required List<HousingVersion> versions,
    required List<MonthlyBill> bills,
  }) =>
      _monthTotal(
        kind: ExpenseKind.housing,
        month: month,
        plans: versions,
        bills: bills,
      );

  /// Full-month allocation of the car plans for [month].
  Rational? carMonthTotal({
    required LocalDate month,
    required List<CarVersion> versions,
    required List<MonthlyBill> bills,
  }) =>
      _monthTotal(
        kind: ExpenseKind.car,
        month: month,
        plans: versions,
        bills: bills,
      );

  Rational? _monthTotal({
    required ExpenseKind kind,
    required LocalDate month,
    required List<ExpensePlanVersion> plans,
    required List<MonthlyBill> bills,
  }) {
    final allocation = _allocateWindow(
      plans: plans,
      bills: bills,
      kind: kind,
      fromUtc: calendar.startOfMonthUtc(month),
      toUtc: calendar.endOfMonthUtc(month),
    );
    if (!allocation.amountKnown) return null;
    return allocation.amount;
  }

  ExpenseBreakdown _breakdown({
    required ExpenseKind kind,
    required DateTime asOfUtc,
    required List<ExpensePlanVersion> plans,
    required List<MonthlyBill> bills,
    required HousingMode? Function(ExpensePlanVersion plan) housingModeOf,
  }) {
    final today = calendar.dateOf(asOfUtc);
    final monthStart = calendar.startOfMonthUtc(today);
    final monthDays = calendar.daysInMonth(today);

    ExpensePlanVersion? activePlan;
    for (final plan in plans) {
      if (!plan.isActive || !plan.covers(asOfUtc)) continue;
      if (activePlan == null ||
          plan.effectiveFromUtc.isAfter(activePlan.effectiveFromUtc)) {
        activePlan = plan;
      }
    }
    final housingMode = activePlan == null ? null : housingModeOf(activePlan);

    if (activePlan == null) {
      return ExpenseBreakdown.notConfigured(
        kind: kind,
        housingMode: housingMode,
        monthDays: monthDays,
      );
    }

    final day = _allocateWindow(
      plans: plans,
      bills: bills,
      kind: kind,
      fromUtc: calendar.startOfDayUtc(today),
      toUtc: asOfUtc,
    );
    final monthToDate = _allocateWindow(
      plans: plans,
      bills: bills,
      kind: kind,
      fromUtc: monthStart,
      toUtc: asOfUtc,
    );

    final bill = _activeBill(activePlan.id, today, bills);
    final monthlyAmount = bill?.monthlyAmountCny;
    final dayShare = monthlyAmount == null
        ? null
        : monthlyAmount / Rational.fromInt(monthDays);

    return ExpenseBreakdown(
      kind: kind,
      housingMode: housingMode,
      configured: true,
      amountKnown: day.amountKnown,
      breakdownKnown: day.principalKnown,
      estimate: monthToDate.estimate,
      monthDays: monthDays,
      dayShare: dayShare ?? Rational.zero,
      monthlyAmount: monthlyAmount,
      dayAmount: day.amountKnown ? day.amount : null,
      monthToDateAmount: monthToDate.amountKnown ? monthToDate.amount : null,
      dayPrincipal: day.principalKnown ? day.principal : null,
      monthToDatePrincipal:
          monthToDate.principalKnown ? monthToDate.principal : null,
      dayInterest: day.principalKnown ? day.interest : null,
      monthToDateInterest:
          monthToDate.principalKnown ? monthToDate.interest : null,
      dayRent: day.amountKnown ? day.rent : null,
      monthToDateRent: monthToDate.amountKnown ? monthToDate.rent : null,
      missingMonths: {
        ...day.missingMonths,
        ...monthToDate.missingMonths,
      }.toList()
        ..sort(),
      activePlanId: activePlan.id,
    );
  }

  _Allocation _allocateWindow({
    required List<ExpensePlanVersion> plans,
    required List<MonthlyBill> bills,
    required ExpenseKind kind,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) {
    final result = _Allocation();
    if (!toUtc.isAfter(fromUtc)) return result;

    final firstDate = calendar.dateOf(fromUtc);
    final lastDate = calendar.dateOf(toUtc.isAfter(fromUtc)
        ? toUtc.subtract(const Duration(microseconds: 1))
        : fromUtc);

    var date = firstDate;
    while (true) {
      final dayStart = calendar.startOfDayUtc(date);
      final dayEnd = calendar.endOfDayUtc(date);
      final dayLength = calendar.dayLengthSeconds(date);
      final windowStart = fromUtc.isAfter(dayStart) ? fromUtc : dayStart;
      final windowEnd = toUtc.isBefore(dayEnd) ? toUtc : dayEnd;
      if (windowEnd.isAfter(windowStart) && dayLength > 0) {
        final month = date.firstOfMonth;
        final daysInMonth = calendar.daysInMonth(date);
        for (final plan in plans) {
          if (plan.kind != kind || !plan.isActive) continue;
          final planStart = plan.effectiveFromUtc.isAfter(windowStart)
              ? plan.effectiveFromUtc
              : windowStart;
          final planEnd = (plan.effectiveToUtc ?? DateTime.utc(9999))
              .isBefore(windowEnd)
              ? plan.effectiveToUtc!
              : windowEnd;
          if (!planEnd.isAfter(planStart)) continue;
          result.seenActive = true;

          final bill = _billFor(plan.id, month, bills);
          if (bill == null || !bill.isUsable) {
            result.amountKnown = false;
            result.principalKnown = false;
            result.missingMonths.add(BusinessCalendar.monthKey(month));
            continue;
          }
          if (bill.isEstimate) result.estimate = true;

          final seconds = planEnd.difference(planStart).inSeconds;
          final coefficient = Rational.fromInt(seconds) /
              Rational.fromInt(dayLength) /
              Rational.fromInt(daysInMonth);
          final amount = bill.monthlyAmountCny! * coefficient;
          result.amount += amount;
          if (plan is HousingVersion && plan.mode == HousingMode.rent) {
            result.rent += amount;
          } else {
            final principal = bill.principalCny;
            if (principal == null) {
              result.principalKnown = false;
            } else {
              result.principal += principal * coefficient;
            }
          }
        }
      }
      if (date >= lastDate) break;
      date = date.addDays(1);
    }

    if (result.principalKnown) {
      result.interest = result.amount - result.rent - result.principal;
    }
    return result;
  }

  MonthlyBill? _activeBill(
    String planId,
    LocalDate date,
    List<MonthlyBill> bills,
  ) =>
      _billFor(planId, date.firstOfMonth, bills);

  MonthlyBill? _billFor(
    String planId,
    LocalDate month,
    List<MonthlyBill> bills,
  ) {
    MonthlyBill? selected;
    for (final bill in bills) {
      if (bill.expenseId != planId || bill.month != month) continue;
      if (selected == null || bill.revision >= selected.revision) {
        selected = bill;
      }
    }
    return selected;
  }
}

final class _Allocation {
  Rational amount = Rational.zero;
  Rational principal = Rational.zero;
  Rational rent = Rational.zero;
  Rational? interest = Rational.zero;
  bool amountKnown = true;
  bool principalKnown = true;
  bool estimate = false;
  bool seenActive = false;
  final Set<String> missingMonths = <String>{};
}
