/// CALC-TOTAL: the dashboard snapshot assembled from all calculators.
library;

import '../asset/asset_calculator.dart';
import '../expense/expense_calculator.dart';
import '../money/rational.dart';
import '../schedule/schedule_expander.dart';
import '../schedule/schedule_model.dart';
import '../time/business_calendar.dart';
import '../time/local_date.dart';
import '../wage/wage_calculator.dart';

enum Completeness { complete, partial, unavailable }

enum DayPhase { working, breakTime, beforeShift, afterShift, restDay, unknown }

/// Machine-readable explanations; the UI owns the Chinese copy.
enum DashboardNote {
  invalidSchedule,
  missingSchedule,
  missingQuotes,
  pendingQuoteConfirmation,
  missingBaseline,
  staleQuotes,
  carriedForwardEstimate,
  missingHousingBill,
  missingCarBill,
  principalUnknown,
  segmentedWage,
  noHoldings,
  housingNotConfigured,
  carNotConfigured,
}

final class CalculationInput {
  const CalculationInput({
    required this.nowUtc,
    required this.ledgerRevision,
    required this.calendar,
    required this.salaryVersions,
    required this.schedules,
    required this.overrides,
    required this.holdings,
    required this.quotes,
    required this.marketCalendar,
    required this.housingVersions,
    required this.carVersions,
    required this.bills,
    this.goldReferenceSessionActive = false,
  });

  final DateTime nowUtc;
  final int ledgerRevision;
  final BusinessCalendar calendar;
  final List<SalaryVersion> salaryVersions;
  final Map<String, ScheduleVersion> schedules;
  final List<ScheduleOverride> overrides;
  final List<Holding> holdings;
  final Map<String, Quote> quotes;
  final MarketCalendar marketCalendar;
  final List<HousingVersion> housingVersions;
  final List<CarVersion> carVersions;
  final List<MonthlyBill> bills;
  final bool goldReferenceSessionActive;
}

final class DashboardSnapshot {
  const DashboardSnapshot({
    required this.computedAtUtc,
    required this.ledgerRevision,
    required this.statisticsDate,
    required this.timezone,
    required this.wage,
    required this.stockDaily,
    required this.goldDaily,
    required this.housing,
    required this.car,
    required this.principal,
    required this.interest,
    required this.rent,
    required this.total,
    required this.completeness,
    required this.wageSegmented,
    required this.breakdownComplete,
    required this.estimate,
    required this.phase,
    required this.timeline,
    required this.monthStats,
    required this.wageDetail,
    required this.assets,
    required this.housingDetail,
    required this.carDetail,
    required this.quotesAsOf,
    required this.quoteQuality,
    required this.notes,
    required this.dayLengthSeconds,
    required this.monthDays,
  });

  final DateTime computedAtUtc;
  final int ledgerRevision;
  final LocalDate statisticsDate;
  final String timezone;

  final Rational? wage;
  final Rational? stockDaily;
  final Rational? goldDaily;
  final Rational? housing;
  final Rational? car;
  final Rational? principal;
  final Rational? interest;
  final Rational? rent;
  final Rational? total;

  final Completeness completeness;
  final bool wageSegmented;
  final bool breakdownComplete;
  final bool estimate;

  final DayPhase phase;
  final DayTimeline? timeline;
  final MonthWageStats? monthStats;

  final WageResult wageDetail;
  final AssetResult assets;
  final ExpenseBreakdown housingDetail;
  final ExpenseBreakdown carDetail;

  final DateTime? quotesAsOf;
  final QuoteQuality quoteQuality;
  final List<DashboardNote> notes;

  final int dayLengthSeconds;
  final int monthDays;

  bool get isPartial => completeness == Completeness.partial;
  bool get isUnavailable => completeness == Completeness.unavailable;

  /// Fixed cost already allocated today (housing + car).
  Rational? get allocatedExpenses {
    final housingValue = housing;
    final carValue = car;
    if (housingValue == null || carValue == null) return null;
    return housingValue + carValue;
  }

  bool get hasNotePinnedQuotes => notes.contains(DashboardNote.missingQuotes);
}

final class DashboardCalculator {
  DashboardCalculator(this.calendar) {
    wageCalculator = WageCalculator(calendar);
    expenseCalculator = ExpenseCalculator(calendar);
  }

  final BusinessCalendar calendar;
  late final WageCalculator wageCalculator;
  late final ExpenseCalculator expenseCalculator;
  static const AssetCalculator assetCalculator = AssetCalculator();

  DashboardSnapshot calculate(CalculationInput input) {
    final now = input.nowUtc.toUtc();
    final date = calendar.dateOf(now);
    final dayStart = calendar.startOfDayUtc(date);
    final notes = <DashboardNote>[];

    final wage = wageCalculator.accrual(
      fromUtc: dayStart,
      toUtc: now,
      salaryVersions: input.salaryVersions,
      schedules: input.schedules,
      overrides: input.overrides,
      nowUtc: now,
    );
    if (wage.status == WageStatus.invalidSchedule) {
      notes.add(DashboardNote.invalidSchedule);
    } else if (wage.status == WageStatus.missingSchedule) {
      notes.add(DashboardNote.missingSchedule);
    }
    if (wage.isSegmented) notes.add(DashboardNote.segmentedWage);

    final assets = assetCalculator.calculate(
      asOfUtc: now,
      statisticsDate: date,
      holdings: input.holdings,
      quotes: input.quotes,
      marketCalendar: input.marketCalendar,
      goldReferenceSessionActive: input.goldReferenceSessionActive,
    );
    if (!assets.hasHoldings) {
      notes.add(DashboardNote.noHoldings);
    }
    if (assets.pendingInstrumentIds.isNotEmpty) {
      notes.add(DashboardNote.missingQuotes);
    }
    if (assets.positions.any((position) =>
        position.status == PositionStatus.missingBaseline ||
        position.status == PositionStatus.staleBaseline ||
        position.status == PositionStatus.awaitingReferenceSession ||
        position.status == PositionStatus.calendarUnknown)) {
      notes.add(DashboardNote.missingBaseline);
    }
    if (assets.quality == QuoteQuality.stale) {
      notes.add(DashboardNote.staleQuotes);
    }
    if (input.holdings.any((holding) => holding.pendingQuote)) {
      notes.add(DashboardNote.pendingQuoteConfirmation);
    }

    final housing = expenseCalculator.housing(
      asOfUtc: now,
      versions: input.housingVersions,
      bills: input.bills,
    );
    final car = expenseCalculator.car(
      asOfUtc: now,
      versions: input.carVersions,
      bills: input.bills,
    );
    if (housing.configured && !housing.amountKnown) {
      notes.add(DashboardNote.missingHousingBill);
    }
    if (car.configured && !car.amountKnown) {
      notes.add(DashboardNote.missingCarBill);
    }
    if (!housing.configured) notes.add(DashboardNote.housingNotConfigured);
    if (!car.configured) notes.add(DashboardNote.carNotConfigured);
    if (housing.estimate || car.estimate) {
      notes.add(DashboardNote.carriedForwardEstimate);
    }
    final breakdownComplete = housing.breakdownKnown && car.breakdownKnown;
    if (!breakdownComplete) notes.add(DashboardNote.principalUnknown);

    final phase = _phaseFor(input, date, now);

    Rational? totalRational;
    Completeness completeness;
    if (wage.amount == null) {
      completeness = Completeness.unavailable;
      totalRational = null;
    } else {
      final wageValue = wage.amount!;
      final housingValue = housing.dayAmount;
      final carValue = car.dayAmount;
      final stockValue = assets.stockDaily;
      final goldValue = assets.goldDaily;
      totalRational = wageValue -
          (housingValue ?? Rational.zero) -
          (carValue ?? Rational.zero) +
          (stockValue ?? Rational.zero) +
          (goldValue ?? Rational.zero);
      completeness = (stockValue == null ||
              goldValue == null ||
              housingValue == null ||
              carValue == null)
          ? Completeness.partial
          : Completeness.complete;
    }

    Rational? principal;
    Rational? interest;
    if (breakdownComplete) {
      principal = (housing.dayPrincipal ?? Rational.zero) +
          (car.dayPrincipal ?? Rational.zero);
      interest = (housing.dayInterest ?? Rational.zero) +
          (car.dayInterest ?? Rational.zero);
    }

    Rational? rent;
    if (housing.isRent) {
      rent = housing.dayRent;
    } else {
      rent = Rational.zero;
    }

    final quoteQuality = assets.hasHoldings ? assets.quality : QuoteQuality.live;

    return DashboardSnapshot(
      computedAtUtc: now,
      ledgerRevision: input.ledgerRevision,
      statisticsDate: date,
      timezone: calendar.timezoneName,
      wage: wage.amount,
      stockDaily: assets.stockDaily,
      goldDaily: assets.goldDaily,
      housing: housing.dayAmount,
      car: car.dayAmount,
      principal: principal,
      interest: interest,
      rent: rent,
      total: totalRational,
      completeness: completeness,
      wageSegmented: wage.isSegmented,
      breakdownComplete: breakdownComplete,
      estimate: housing.estimate || car.estimate,
      phase: phase,
      timeline: _timelineFor(input, date),
      monthStats: wage.monthStats,
      wageDetail: wage,
      assets: assets,
      housingDetail: housing,
      carDetail: car,
      quotesAsOf: assets.quotesAsOf,
      quoteQuality: quoteQuality,
      notes: notes,
      dayLengthSeconds: calendar.dayLengthSeconds(date),
      monthDays: calendar.daysInMonth(date),
    );
  }

  /// The schedule version governing [date], preferring the latest start.
  ScheduleVersion? scheduleVersionAt(CalculationInput input, DateTime instant) {
    ScheduleVersion? selected;
    for (final version in input.schedules.values) {
      if (!version.covers(instant)) continue;
      if (selected == null ||
          version.effectiveFromUtc.isAfter(selected.effectiveFromUtc)) {
        selected = version;
      }
    }
    return selected;
  }

  DayTimeline? _timelineFor(CalculationInput input, LocalDate date) {
    final version = scheduleVersionAt(input, input.nowUtc);
    if (version == null) return null;
    return wageCalculator.expander.dayTimeline(
      version: version,
      overrides: input.overrides,
      date: date,
    );
  }

  DayPhase _phaseFor(
    CalculationInput input,
    LocalDate date,
    DateTime now,
  ) {
    final timeline = _timelineFor(input, date);
    if (timeline == null) return DayPhase.unknown;
    if (timeline.isRestDay) return DayPhase.restDay;
    for (final segment in timeline.paidSegments) {
      if (!now.isBefore(segment.startUtc) && now.isBefore(segment.endUtc)) {
        return DayPhase.working;
      }
    }
    for (final window in timeline.unpaidWindows) {
      if (window.contains(now)) return DayPhase.breakTime;
    }
    final start = timeline.shiftStartUtc;
    final end = timeline.shiftEndUtc;
    if (start != null && now.isBefore(start)) return DayPhase.beforeShift;
    if (end != null && !now.isBefore(end)) return DayPhase.afterShift;
    return DayPhase.unknown;
  }
}
