/// Expands weekly templates and date overrides into absolute paid intervals.
library;

import '../dashboard/dashboard_calculator.dart' show DayPhase;
import '../time/business_calendar.dart';
import '../time/local_date.dart';
import 'schedule_model.dart';
import 'work_session.dart';

/// A paid work interval resolved to UTC instants.
final class PaidSegment {
  const PaidSegment({
    required this.startUtc,
    required this.endUtc,
    required this.shiftDate,
  });

  final DateTime startUtc;
  final DateTime endUtc;

  /// Local date on which the shift started.
  final LocalDate shiftDate;

  int get seconds => endUtc.difference(startUtc).inSeconds;

  @override
  String toString() =>
      'PaidSegment(${startUtc.toIso8601String()} → ${endUtc.toIso8601String()})';
}

/// An unpaid window between two paid intervals of the same shift.
final class UnpaidWindow {
  const UnpaidWindow({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;

  bool contains(DateTime instant) =>
      !instant.isBefore(startUtc) && instant.isBefore(endUtc);
}

/// Everything the dashboard needs to describe today's shift.
final class DayTimeline {
  const DayTimeline({
    required this.date,
    required this.paidSegments,
    required this.unpaidWindows,
    required this.shiftStartUtc,
    required this.shiftEndUtc,
    required this.scheduleVersionId,
  });

  final LocalDate date;

  /// Paid segments clipped to this local day.
  final List<PaidSegment> paidSegments;

  /// Breaks and other unpaid gaps between the first and last paid segment.
  final List<UnpaidWindow> unpaidWindows;

  final DateTime? shiftStartUtc;
  final DateTime? shiftEndUtc;
  final String? scheduleVersionId;

  bool get isRestDay => paidSegments.isEmpty;

  int get paidSecondsTotal =>
      paidSegments.fold(0, (sum, segment) => sum + segment.seconds);

  /// Paid seconds already elapsed at [nowUtc].
  int paidSecondsElapsed(DateTime nowUtc) {
    var total = 0;
    for (final segment in paidSegments) {
      if (nowUtc.isAfter(segment.startUtc)) {
        final end = nowUtc.isBefore(segment.endUtc) ? nowUtc : segment.endUtc;
        total += end.difference(segment.startUtc).inSeconds;
      }
    }
    return total;
  }

  bool get hasStarted {
    final start = shiftStartUtc;
    return start != null;
  }
}

/// Expands schedules into UTC paid segments, clipping at every boundary.
final class ScheduleExpander {
  ScheduleExpander(this._calendarFor);

  final BusinessCalendar Function(String timezone) _calendarFor;

  /// Presence resolution half-window; shifts last at most 24h, so ±48h fully
  /// contains every shift that can intersect `now`.
  static const Duration _sessionResolutionWindow = Duration(hours: 48);

  /// Expands [version] between [fromUtc] and [toUtc).
  ///
  /// When [clipToVersion] is false the version's own effective period is
  /// ignored; the monthly denominator uses that mode so each version always
  /// divides by its own full-month schedule.
  List<PaidSegment> expand({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required DateTime fromUtc,
    required DateTime toUtc,
    bool clipToVersion = true,
  }) {
    if (!toUtc.isAfter(fromUtc)) return const <PaidSegment>[];
    final calendar = _calendarFor(version.timezone);
    final startDate = calendar.dateOf(fromUtc).addDays(-1);
    final endDate = calendar.dateOf(toUtc);
    final versionStart = version.effectiveFromUtc;
    final versionEnd = version.effectiveToUtc ?? DateTime.utc(9999);

    final segments = <PaidSegment>[];
    var date = startDate;
    while (date <= endDate) {
      final intervals = overrideFor(overrides, date) ??
          version.templateFor(date).paidIntervalsForWeekday(date.weekday);
      for (final interval in intervals) {
        if (interval.durationMinutes <= 0) continue;
        var start = calendar.instantAt(date, interval.startMinute);
        var end = calendar.instantAt(date, interval.endMinute);
        if (clipToVersion) {
          if (start.isBefore(versionStart)) start = versionStart;
          if (end.isAfter(versionEnd)) end = versionEnd;
        }
        if (start.isBefore(fromUtc)) start = fromUtc;
        if (end.isAfter(toUtc)) end = toUtc;
        if (end.isAfter(start)) {
          segments.add(PaidSegment(startUtc: start, endUtc: end, shiftDate: date));
        }
      }
      date = date.addDays(1);
    }
    return mergeSegments(segments);
  }

  /// Overlapping segments are merged defensively; validation rejects them
  /// before they reach storage, but imported legacy data can still carry them.
  static List<PaidSegment> mergeSegments(List<PaidSegment> segments) {
    if (segments.length < 2) return segments;
    final sorted = [...segments]
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
    final merged = <PaidSegment>[sorted.first];
    for (var index = 1; index < sorted.length; index++) {
      final previous = merged.last;
      final current = sorted[index];
      if (!current.startUtc.isAfter(previous.endUtc)) {
        if (current.endUtc.isAfter(previous.endUtc)) {
          merged[merged.length - 1] = PaidSegment(
            startUtc: previous.startUtc,
            endUtc: current.endUtc,
            shiftDate: previous.shiftDate,
          );
        }
      } else {
        merged.add(current);
      }
    }
    return merged;
  }

  /// Paid seconds inside the month containing [anchor], ignoring the version's
  /// own effective period (the CALC-WAGE denominator).
  int monthlyPaidSeconds({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required LocalDate anchor,
  }) {
    final calendar = _calendarFor(version.timezone);
    final segments = expand(
      version: version,
      overrides: overrides,
      fromUtc: calendar.startOfMonthUtc(anchor),
      toUtc: calendar.endOfMonthUtc(anchor),
      clipToVersion: false,
    );
    return segments.fold(0, (sum, segment) => sum + segment.seconds);
  }

  /// Number of local dates with any paid time inside the month.
  int monthlyPaidDays({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required LocalDate anchor,
  }) {
    final calendar = _calendarFor(version.timezone);
    final monthStart = calendar.startOfMonthUtc(anchor);
    final monthEnd = calendar.endOfMonthUtc(anchor);
    final segments = expand(
      version: version,
      overrides: overrides,
      fromUtc: monthStart,
      toUtc: monthEnd,
      clipToVersion: false,
    );
    final days = <LocalDate>{};
    for (final segment in segments) {
      var cursor = segment.startUtc;
      while (cursor.isBefore(segment.endUtc)) {
        final date = calendar.dateOf(cursor);
        days.add(date);
        final boundary = calendar.endOfDayUtc(date);
        cursor = boundary.isBefore(segment.endUtc) ? boundary : segment.endUtc;
      }
    }
    return days.length;
  }

  /// Builds today's shift view: paid segments, breaks, start and end.
  DayTimeline dayTimeline({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required LocalDate date,
    bool clipToVersion = true,
  }) {
    final calendar = _calendarFor(version.timezone);
    final dayStart = calendar.startOfDayUtc(date);
    final dayEnd = calendar.endOfDayUtc(date);
    final segments = expand(
      version: version,
      overrides: overrides,
      fromUtc: dayStart,
      toUtc: dayEnd,
      clipToVersion: clipToVersion,
    );
    final windows = <UnpaidWindow>[];
    if (segments.isNotEmpty) {
      var cursor = segments.first.startUtc;
      for (final segment in segments) {
        if (segment.startUtc.isAfter(cursor)) {
          windows.add(UnpaidWindow(startUtc: cursor, endUtc: segment.startUtc));
        }
        if (segment.endUtc.isAfter(cursor)) cursor = segment.endUtc;
      }
    }
    return DayTimeline(
      date: date,
      paidSegments: segments,
      unpaidWindows: windows,
      shiftStartUtc: segments.isEmpty ? null : segments.first.startUtc,
      shiftEndUtc: segments.isEmpty ? null : segments.last.endUtc,
      scheduleVersionId: segments.isEmpty ? null : version.id,
    );
  }

  /// SCN-01: complete-shift presence context, deliberately not clipped at the
  /// natural-day boundary. Wage and allocation math keeps using [dayTimeline].
  ///
  /// Shifts last at most 24 hours, so every shift intersecting `nowUtc ± 24h`
  /// is fully contained in the ±48h resolution window below.
  WorkSessionContext workSessionContext({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required DateTime nowUtc,
  }) {
    final calendar = _calendarFor(version.timezone);
    final now = nowUtc.toUtc();
    final segments = _expandComplete(
      version: version,
      overrides: overrides,
      fromUtc: now.subtract(_sessionResolutionWindow),
      toUtc: now.add(_sessionResolutionWindow),
    );
    final sessions = _sessionsFrom(segments, versionId: version.id);

    WorkSessionInfo? active;
    WorkSessionInfo? lastEnded;
    WorkSessionInfo? next;
    for (final session in sessions) {
      if (session.contains(now)) {
        active = session;
      } else if (session.endUtc.isBefore(now)) {
        lastEnded = session;
      } else if (session.startUtc.isAfter(now)) {
        next ??= session;
      }
    }

    return WorkSessionContext(
      phase: _presencePhase(
        calendar: calendar,
        now: now,
        active: active,
        lastEnded: lastEnded,
        next: next,
      ),
      scheduleValid: version.covers(now),
      activeSession: active,
      lastEndedSession: lastEnded,
      nextSession: next,
    );
  }

  /// Complete (unclipped at the query window, still clipped to the version's
  /// own effective period) paid intervals for every shift date that may touch
  /// the window. Segments are deliberately *not* merged across shifts.
  List<PaidSegment> _expandComplete({
    required ScheduleVersion version,
    required List<ScheduleOverride> overrides,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) {
    final calendar = _calendarFor(version.timezone);
    final startDate = calendar.dateOf(fromUtc).addDays(-1);
    final endDate = calendar.dateOf(toUtc).addDays(1);
    final versionStart = version.effectiveFromUtc;
    final versionEnd = version.effectiveToUtc ?? DateTime.utc(9999);

    final segments = <PaidSegment>[];
    var date = startDate;
    while (date <= endDate) {
      final intervals = overrideFor(overrides, date) ??
          version.templateFor(date).paidIntervalsForWeekday(date.weekday);
      for (final interval in intervals) {
        if (interval.durationMinutes <= 0) continue;
        var start = calendar.instantAt(date, interval.startMinute);
        var end = calendar.instantAt(date, interval.endMinute);
        if (start.isBefore(versionStart)) start = versionStart;
        if (end.isAfter(versionEnd)) end = versionEnd;
        if (end.isAfter(start)) {
          segments.add(
            PaidSegment(startUtc: start, endUtc: end, shiftDate: date),
          );
        }
      }
      date = date.addDays(1);
    }
    return segments;
  }

  /// Groups one shift date's intervals into a single session: the session
  /// ends at its last valid interval's end, breaks stay inside as unpaid
  /// windows. This is what keeps a lunch break from splitting the shift.
  List<WorkSessionInfo> _sessionsFrom(
    List<PaidSegment> segments, {
    required String versionId,
  }) {
    if (segments.isEmpty) return const <WorkSessionInfo>[];
    final sorted = [...segments]
      ..sort((a, b) {
        final byDate = a.shiftDate.compareTo(b.shiftDate);
        return byDate != 0 ? byDate : a.startUtc.compareTo(b.startUtc);
      });
    final sessions = <WorkSessionInfo>[];
    var group = <PaidSegment>[sorted.first];
    void flush() {
      final paid = [...group]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
      final windows = <UnpaidWindow>[];
      var cursor = paid.first.startUtc;
      for (final segment in paid) {
        if (segment.startUtc.isAfter(cursor)) {
          windows.add(
            UnpaidWindow(startUtc: cursor, endUtc: segment.startUtc),
          );
        }
        if (segment.endUtc.isAfter(cursor)) cursor = segment.endUtc;
      }
      sessions.add(
        WorkSessionInfo(
          key: '$versionId|${paid.first.shiftDate.toIsoString()}|'
              '${paid.first.startUtc.toIso8601String()}|'
              '${cursor.toIso8601String()}',
          startUtc: paid.first.startUtc,
          endUtc: cursor,
          shiftDate: paid.first.shiftDate,
          paidSegments: paid,
          unpaidWindows: windows,
        ),
      );
    }

    for (var index = 1; index < sorted.length; index++) {
      final segment = sorted[index];
      if (segment.shiftDate == group.first.shiftDate) {
        group.add(segment);
      } else {
        flush();
        group = <PaidSegment>[segment];
      }
    }
    flush();
    return sessions;
  }

  /// Phase order from docs/09 §7.1: in-shift (working/breakTime), then a
  /// shift that truly ended within the statistics day (afterShift), then a
  /// shift starting later today (beforeShift), then restDay.
  DayPhase _presencePhase({
    required BusinessCalendar calendar,
    required DateTime now,
    required WorkSessionInfo? active,
    required WorkSessionInfo? lastEnded,
    required WorkSessionInfo? next,
  }) {
    if (active != null) {
      for (final window in active.unpaidWindows) {
        if (window.contains(now)) return DayPhase.breakTime;
      }
      return DayPhase.working;
    }
    final statisticsDate = calendar.dateOf(now);
    final dayStartUtc = calendar.startOfDayUtc(statisticsDate);
    final ended = lastEnded;
    if (ended != null && !ended.endUtc.isBefore(dayStartUtc)) {
      return DayPhase.afterShift;
    }
    final upcoming = next;
    if (upcoming != null && upcoming.shiftDate == statisticsDate) {
      return DayPhase.beforeShift;
    }
    return DayPhase.restDay;
  }
}
