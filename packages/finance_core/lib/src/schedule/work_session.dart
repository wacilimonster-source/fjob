/// SCN-01: complete-shift presence context shared by the dashboard scene,
/// the countdown and the widget snapshot.
///
/// `DayTimeline` stays clipped to the natural statistics day for wage and
/// allocation math. Presence needs the *whole* shift instead: a 22:00–02:00
/// night shift must still report "working" after midnight and "afterShift"
/// until the next real shift starts. Nothing here feeds the ledgers.
library;

import '../dashboard/dashboard_calculator.dart' show DayPhase;
import '../time/local_date.dart';
import 'schedule_expander.dart';

/// One full shift (all paid intervals of a single shift date), never clipped
/// at midnight.
final class WorkSessionInfo {
  const WorkSessionInfo({
    required this.key,
    required this.startUtc,
    required this.endUtc,
    required this.shiftDate,
    required this.paidSegments,
    required this.unpaidWindows,
  });

  /// Schedule version + shift date + exact UTC bounds; stable across the
  /// midnight the shift crosses.
  final String key;

  final DateTime startUtc;

  /// Exclusive end of the last valid interval of the shift.
  final DateTime endUtc;

  /// Local date on which the shift started.
  final LocalDate shiftDate;

  /// Paid intervals of the whole shift, unclipped.
  final List<PaidSegment> paidSegments;

  /// Unpaid gaps (lunch and friends) between the shift's paid intervals.
  final List<UnpaidWindow> unpaidWindows;

  bool contains(DateTime instant) =>
      !instant.isBefore(startUtc) && instant.isBefore(endUtc);

  @override
  String toString() =>
      'WorkSessionInfo($key, ${startUtc.toIso8601String()} → '
      '${endUtc.toIso8601String()})';
}

/// Read-only view of "where is the worker" at one instant.
final class WorkSessionContext {
  const WorkSessionContext({
    required this.phase,
    required this.scheduleValid,
    this.activeSession,
    this.lastEndedSession,
    this.nextSession,
  });

  /// Unknown context for callers that have no schedule yet.
  static const WorkSessionContext empty = WorkSessionContext(
    phase: DayPhase.unknown,
    scheduleValid: false,
  );

  final DayPhase phase;
  final WorkSessionInfo? activeSession;
  final WorkSessionInfo? lastEndedSession;
  final WorkSessionInfo? nextSession;
  final bool scheduleValid;
}
