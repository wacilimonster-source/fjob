/// CALC-WAGE: salary accrual over the paid seconds of a month.
library;

import '../money/rational.dart';
import '../schedule/schedule_expander.dart';
import '../schedule/schedule_model.dart';
import '../time/business_calendar.dart';
import '../time/local_date.dart';

/// A salary amount effective for a closed-open period, linked to a schedule.
final class SalaryVersion {
  SalaryVersion({
    required this.id,
    required this.monthlyNetCny,
    required this.effectiveFromUtc,
    this.effectiveToUtc,
    required this.scheduleVersionId,
  }) {
    if (monthlyNetCny.isNegative) {
      throw ArgumentError('monthlyNetCny must not be negative');
    }
    if (effectiveToUtc != null && !effectiveToUtc!.isAfter(effectiveFromUtc)) {
      throw ArgumentError('effectiveToUtc must be after effectiveFromUtc');
    }
  }

  final String id;
  final Rational monthlyNetCny;
  final DateTime effectiveFromUtc;
  final DateTime? effectiveToUtc;
  final String scheduleVersionId;

  bool covers(DateTime instantUtc) =>
      !instantUtc.isBefore(effectiveFromUtc) &&
      (effectiveToUtc == null || instantUtc.isBefore(effectiveToUtc!));

  bool overlaps(DateTime fromUtc, DateTime toUtc) =>
      fromUtc.isBefore(effectiveToUtc ?? DateTime.utc(9999)) &&
      effectiveFromUtc.isBefore(toUtc);
}

enum WageStatus { computed, invalidSchedule, missingSchedule }

/// One contiguous salary version/month contribution.
final class WageSlice {
  const WageSlice({
    required this.versionId,
    required this.month,
    required this.monthlyCny,
    required this.monthlyPaidSeconds,
    required this.paidSeconds,
    required this.amount,
  });

  final String versionId;

  /// First day of the month the slice belongs to.
  final LocalDate month;
  final Rational monthlyCny;
  final int monthlyPaidSeconds;
  final int paidSeconds;
  final Rational amount;

  Rational get hourlyRate => monthlyPaidSeconds == 0
      ? Rational.zero
      : monthlyCny / Rational.fromInt(monthlyPaidSeconds);

  Rational get perSecondRate => monthlyPaidSeconds == 0
      ? Rational.zero
      : monthlyCny / Rational.fromInt(monthlyPaidSeconds);
}

/// Full-month schedule statistics for the current configuration.
final class MonthWageStats {
  const MonthWageStats({
    required this.versionId,
    required this.month,
    required this.monthlyCny,
    required this.paidSeconds,
    required this.paidDays,
  });

  final String versionId;
  final LocalDate month;
  final Rational monthlyCny;
  final int paidSeconds;
  final int paidDays;

  Rational get paidHours => Rational.fromInt(paidSeconds) / Rational.fromInt(3600);
}

final class WageResult {
  const WageResult({
    required this.status,
    required this.slices,
    required this.paidSecondsInWindow,
    this.amount,
    this.monthStats,
  });

  final WageStatus status;
  final List<WageSlice> slices;
  final int paidSecondsInWindow;
  final Rational? amount;
  final MonthWageStats? monthStats;

  bool get isAvailable => amount != null;

  /// True when the window spans more than one salary version or month; the UI
  /// then labels the figure as a segmented estimate.
  bool get isSegmented =>
      slices.map((slice) => slice.versionId).toSet().length > 1;

  bool get isInvalid => status == WageStatus.invalidSchedule;
}

/// Raised when a positive salary has no paid seconds to divide by.
final class InvalidScheduleException implements Exception {
  const InvalidScheduleException();

  @override
  String toString() => 'invalidSchedule';
}

/// Pure wage arithmetic shared by the engine, the fixture tests and validation.
Rational wageFor({
  required Rational monthlyCny,
  required int monthlyPaidSeconds,
  required int elapsedPaidSeconds,
}) {
  if (monthlyCny.isZero) return Rational.zero;
  if (monthlyPaidSeconds <= 0) throw const InvalidScheduleException();
  if (elapsedPaidSeconds <= 0) return Rational.zero;
  return monthlyCny *
      Rational.fromInt(elapsedPaidSeconds) /
      Rational.fromInt(monthlyPaidSeconds);
}

final class WageCalculator {
  WageCalculator(this.calendar);

  final BusinessCalendar calendar;
  late final ScheduleExpander expander = ScheduleExpander(
    (timezone) => timezone == calendar.timezoneName
        ? calendar
        : BusinessCalendar.forZone(timezone),
  );

  /// Accrues salary between two instants for every overlapping salary version.
  WageResult accrual({
    required DateTime fromUtc,
    required DateTime toUtc,
    required List<SalaryVersion> salaryVersions,
    required Map<String, ScheduleVersion> schedules,
    required List<ScheduleOverride> overrides,
    DateTime? nowUtc,
  }) {
    if (!toUtc.isAfter(fromUtc)) {
      return WageResult(
        status: WageStatus.computed,
        slices: const <WageSlice>[],
        paidSecondsInWindow: 0,
        amount: Rational.zero,
      );
    }
    final applicable = salaryVersions
        .where((version) => version.overlaps(fromUtc, toUtc))
        .toList()
      ..sort((a, b) => a.effectiveFromUtc.compareTo(b.effectiveFromUtc));

    final slicesByKey = <String, WageSlice>{};
    var paidSeconds = 0;
    var invalidSchedule = false;

    for (final version in applicable) {
      if (invalidSchedule) break;
      final schedule = schedules[version.scheduleVersionId];
      if (schedule == null) {
        return WageResult(
          status: WageStatus.missingSchedule,
          slices: const <WageSlice>[],
          paidSecondsInWindow: 0,
          monthStats: _monthStatsFor(
            nowUtc: nowUtc ?? toUtc,
            salaryVersions: salaryVersions,
            schedules: schedules,
            overrides: overrides,
          ),
        );
      }
      final start = version.effectiveFromUtc.isAfter(fromUtc)
          ? version.effectiveFromUtc
          : fromUtc;
      final rawEnd = version.effectiveToUtc ?? DateTime.utc(9999);
      final end = rawEnd.isBefore(toUtc) ? rawEnd : toUtc;
      if (!end.isAfter(start)) continue;

      // A positive salary divided by a month with no paid seconds is an invalid
      // configuration even when the requested window contains no shift.
      var monthCursor = calendar.dateOf(start).firstOfMonth;
      final lastMonth = calendar
          .dateOf(end.subtract(const Duration(microseconds: 1)))
          .firstOfMonth;
      while (monthCursor <= lastMonth) {
        final denominator = _denominator(
          schedule: schedule,
          overrides: overrides,
          month: monthCursor,
        );
        if (denominator == 0 && version.monthlyNetCny.isPositive) {
          invalidSchedule = true;
          break;
        }
        monthCursor = monthCursor.addMonths(1);
      }
      if (invalidSchedule) break;

      final segments = expander.expand(
        version: schedule,
        overrides: overrides,
        fromUtc: start,
        toUtc: end,
      );
      for (final segment in segments) {
        _forEachMonthPart(segment, (partStart, partEnd, monthAnchor) {
          if (invalidSchedule) return;
          final seconds = partEnd.difference(partStart).inSeconds;
          final denominator = _denominator(
            schedule: schedule,
            overrides: overrides,
            month: monthAnchor,
          );
          if (denominator == 0 && version.monthlyNetCny.isPositive) {
            invalidSchedule = true;
            return;
          }
          final rate = denominator == 0
              ? Rational.zero
              : version.monthlyNetCny / Rational.fromInt(denominator);
          final amount = rate * Rational.fromInt(seconds);
          paidSeconds += seconds;
          final key = '${version.id}|${monthAnchor.toIsoString()}';
          final existing = slicesByKey[key];
          if (existing == null) {
            slicesByKey[key] = WageSlice(
              versionId: version.id,
              month: monthAnchor,
              monthlyCny: version.monthlyNetCny,
              monthlyPaidSeconds: denominator,
              paidSeconds: seconds,
              amount: amount,
            );
          } else {
            slicesByKey[key] = WageSlice(
              versionId: version.id,
              month: monthAnchor,
              monthlyCny: existing.monthlyCny,
              monthlyPaidSeconds: existing.monthlyPaidSeconds,
              paidSeconds: existing.paidSeconds + seconds,
              amount: existing.amount + amount,
            );
          }
        });
      }
    }

    if (invalidSchedule) {
      return const WageResult(
        status: WageStatus.invalidSchedule,
        slices: <WageSlice>[],
        paidSecondsInWindow: 0,
      );
    }

    final slices = slicesByKey.values.toList()
      ..sort((a, b) {
        final byMonth = a.month.compareTo(b.month);
        return byMonth != 0 ? byMonth : a.versionId.compareTo(b.versionId);
      });
    var total = Rational.zero;
    for (final slice in slices) {
      total += slice.amount;
    }
    return WageResult(
      status: WageStatus.computed,
      slices: slices,
      paidSecondsInWindow: paidSeconds,
      amount: total,
      monthStats: _monthStatsFor(
        nowUtc: nowUtc ?? toUtc,
        salaryVersions: salaryVersions,
        schedules: schedules,
        overrides: overrides,
      ),
    );
  }

  /// Full-month paid seconds for a schedule.
  ///
  /// Deliberately uncached: overrides belong to the calculation input, and a
  /// calculator instance survives ledger edits in the app, so caching by
  /// schedule and month alone would return a stale denominator.
  int _denominator({
    required ScheduleVersion schedule,
    required List<ScheduleOverride> overrides,
    required LocalDate month,
  }) =>
      expander.monthlyPaidSeconds(
        version: schedule,
        overrides: overrides,
        anchor: month,
      );

  MonthWageStats? _monthStatsFor({
    required DateTime nowUtc,
    required List<SalaryVersion> salaryVersions,
    required Map<String, ScheduleVersion> schedules,
    required List<ScheduleOverride> overrides,
  }) {
    SalaryVersion? active;
    for (final version in salaryVersions) {
      if (version.covers(nowUtc)) {
        if (active == null ||
            version.effectiveFromUtc.isAfter(active.effectiveFromUtc)) {
          active = version;
        }
      }
    }
    if (active == null) return null;
    final schedule = schedules[active.scheduleVersionId];
    if (schedule == null) return null;
    final month = calendar.dateOf(nowUtc).firstOfMonth;
    return MonthWageStats(
      versionId: active.id,
      month: month,
      monthlyCny: active.monthlyNetCny,
      paidSeconds: _denominator(
        schedule: schedule,
        overrides: overrides,
        month: month,
      ),
      paidDays: expander.monthlyPaidDays(
        version: schedule,
        overrides: overrides,
        anchor: month,
      ),
    );
  }

  /// Splits a paid segment at statistics-timezone month boundaries so each
  /// part is priced with its own month's denominator.
  void _forEachMonthPart(
    PaidSegment segment,
    void Function(DateTime start, DateTime end, LocalDate month) visit,
  ) {
    var cursor = segment.startUtc;
    while (cursor.isBefore(segment.endUtc)) {
      final month = calendar.dateOf(cursor).firstOfMonth;
      final nextMonth = calendar.startOfMonthUtc(month.addMonths(1));
      final end = nextMonth.isBefore(segment.endUtc) ? nextMonth : segment.endUtc;
      visit(cursor, end, month);
      cursor = end;
    }
  }
}
