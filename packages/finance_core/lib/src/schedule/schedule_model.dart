/// Pay-schedule domain: weekly shift templates, versioned schedules, overrides.
///
/// Intervals are expressed in *minutes after the local midnight of the shift's
/// start date*. Values of 1440 or more mean the next local day, which is how a
/// 22:00–06:00 shift is stored without special casing.
library;

import '../time/local_date.dart';

/// A paid-shift interval.
final class ShiftTemplate {
  const ShiftTemplate({
    required this.startMinute,
    required this.endMinute,
    this.breaks = const <BreakTemplate>[],
  });

  /// Minute of day (0–1439) at which the shift starts.
  final int startMinute;

  /// Exclusive end minute, up to `startMinute + 1440` for a cross-midnight shift.
  final int endMinute;

  /// Unpaid break windows inside the shift.
  final List<BreakTemplate> breaks;

  bool get crossesMidnight => endMinute > 1440 || endMinute <= startMinute;

  int get durationMinutes => endMinute - startMinute;

  /// Break windows resolved to absolute minutes from the shift date.
  ///
  /// A break whose clock time is earlier than the shift start belongs to the
  /// following day, so 02:00–02:30 inside a 22:00 shift stays where the user
  /// meant it.
  List<LocalInterval> absoluteBreaks() {
    final result = <LocalInterval>[];
    for (final entry in breaks) {
      var start = entry.startMinute;
      var end = entry.endMinute;
      if (start < startMinute) {
        start += 1440;
        end += 1440;
      }
      result.add(LocalInterval(startMinute: start, endMinute: end));
    }
    return result;
  }

  /// Paid intervals for the shift, with breaks removed.
  List<LocalInterval> paidIntervals() {
    var intervals = <LocalInterval>[
      LocalInterval(startMinute: startMinute, endMinute: endMinute),
    ];
    for (final pause in absoluteBreaks()) {
      intervals = _subtract(intervals, pause);
    }
    return intervals;
  }

  static List<LocalInterval> _subtract(
    List<LocalInterval> source,
    LocalInterval cut,
  ) {
    final result = <LocalInterval>[];
    for (final interval in source) {
      if (cut.endMinute <= interval.startMinute ||
          cut.startMinute >= interval.endMinute) {
        result.add(interval);
        continue;
      }
      if (cut.startMinute > interval.startMinute) {
        result.add(LocalInterval(
          startMinute: interval.startMinute,
          endMinute: cut.startMinute,
        ));
      }
      if (cut.endMinute < interval.endMinute) {
        result.add(LocalInterval(
          startMinute: cut.endMinute,
          endMinute: interval.endMinute,
        ));
      }
    }
    return result;
  }

  /// Throws [ScheduleValidationError] when the shift cannot be expanded.
  void validate() {
    if (startMinute < 0 || startMinute >= 1440) {
      throw const ScheduleValidationError(
        'invalidInterval',
        '上班时间必须在当天 00:00–23:59 之间。',
      );
    }
    if (endMinute <= startMinute || endMinute > startMinute + 1440) {
      throw const ScheduleValidationError(
        'invalidInterval',
        '下班时间必须晚于上班时间，跨夜班最长 24 小时。',
      );
    }
    final pauses = absoluteBreaks();
    for (final pause in pauses) {
      if (pause.durationMinutes <= 0 ||
          pause.startMinute < startMinute ||
          pause.endMinute > endMinute) {
        throw const ScheduleValidationError(
          'breakOutsideShift',
          '午休请安排在上下班之间，也给工资留一点出场时间。',
        );
      }
    }
    final sorted = [...pauses]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    for (var index = 1; index < sorted.length; index++) {
      if (sorted[index].startMinute < sorted[index - 1].endMinute) {
        throw const ScheduleValidationError(
          'overlappingBreaks',
          '两段午休打架了，请分开安排。',
        );
      }
    }
    if (paidIntervals().isEmpty) {
      throw const ScheduleValidationError(
        'emptyShift',
        '这个班次没有有效计薪时段。',
      );
    }
  }
}

/// An unpaid window inside a shift.
final class BreakTemplate {
  const BreakTemplate({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;
}

/// A minute interval relative to a local date's midnight.
final class LocalInterval {
  const LocalInterval({required this.startMinute, required this.endMinute});

  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;

  bool overlaps(LocalInterval other) =>
      startMinute < other.endMinute && other.startMinute < endMinute;

  @override
  String toString() => '[$startMinute, $endMinute)';
}

/// The seven-day work template, Monday first (`weekday - 1` indexing).
final class WeekTemplate {
  WeekTemplate(this.byWeekday) {
    if (byWeekday.length != 7) {
      throw ArgumentError.value(byWeekday.length, 'byWeekday', 'must have 7 days');
    }
    validate();
  }

  /// Monday–Friday 09:00–18:00 with a 12:00–13:00 unpaid lunch.
  factory WeekTemplate.standardOffice() {
    const shift = ShiftTemplate(
      startMinute: 9 * 60,
      endMinute: 18 * 60,
      breaks: <BreakTemplate>[
        BreakTemplate(startMinute: 12 * 60, endMinute: 13 * 60),
      ],
    );
    return WeekTemplate(<List<ShiftTemplate>>[
      for (var index = 0; index < 7; index++)
        if (index < 5) <ShiftTemplate>[shift] else const <ShiftTemplate>[],
    ]);
  }

  final List<List<ShiftTemplate>> byWeekday;

  List<ShiftTemplate> shiftsForWeekday(int weekday) => byWeekday[weekday - 1];

  List<LocalInterval> paidIntervalsForWeekday(int weekday) {
    final intervals = <LocalInterval>[
      for (final shift in shiftsForWeekday(weekday)) ...shift.paidIntervals(),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return intervals;
  }

  bool get hasAnyShift => byWeekday.any((shifts) => shifts.isNotEmpty);

  /// Rejects overlapping shifts or breaks on the same weekday.
  void validate() {
    for (final shifts in byWeekday) {
      for (final shift in shifts) {
        shift.validate();
      }
      final paid = <LocalInterval>[
        for (final shift in shifts) ...shift.paidIntervals(),
      ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      for (var index = 1; index < paid.length; index++) {
        if (paid[index].startMinute < paid[index - 1].endMinute) {
          throw const ScheduleValidationError(
            'overlappingShifts',
            '同一天的班次重叠了，请错开时间。',
          );
        }
      }
    }
  }
}

/// A versioned schedule template with an effective period.
final class ScheduleVersion {
  ScheduleVersion({
    required this.id,
    required this.timezone,
    required this.week,
    required this.effectiveFromUtc,
    this.effectiveToUtc,
    this.calendarSourceVersion = 'WORK_CN@builtin',
  }) {
    if (effectiveToUtc != null && !effectiveToUtc!.isAfter(effectiveFromUtc)) {
      throw ArgumentError('effectiveToUtc must be after effectiveFromUtc');
    }
    week.validate();
  }

  final String id;
  final String timezone;
  final WeekTemplate week;
  final DateTime effectiveFromUtc;
  final DateTime? effectiveToUtc;
  final String calendarSourceVersion;

  bool covers(DateTime instantUtc) =>
      !instantUtc.isBefore(effectiveFromUtc) &&
      (effectiveToUtc == null || instantUtc.isBefore(effectiveToUtc!));

  bool overlaps(DateTime fromUtc, DateTime toUtc) =>
      fromUtc.isBefore(effectiveToUtc ?? _maxInstant) &&
      effectiveFromUtc.isBefore(toUtc);

  static final DateTime _maxInstant = DateTime.utc(9999);
}

/// A confirmed date override that replaces the weekly template for one day.
final class ScheduleOverride {
  const ScheduleOverride({
    required this.localDate,
    required this.paidIntervals,
    this.reason = 'override',
    this.confirmed = true,
  });

  final LocalDate localDate;

  /// Paid intervals replacing the template for this shift date. An empty list
  /// marks a rest day, a leave day or a swapped day off.
  final List<LocalInterval> paidIntervals;

  /// `leave`, `rest`, `swap`, `halfDay` or `override`.
  final String reason;
  final bool confirmed;

  bool get isRestDay => paidIntervals.isEmpty;
}

/// Validation failure with a stable code and a user-facing Chinese message.
final class ScheduleValidationError implements Exception {
  const ScheduleValidationError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ScheduleValidationError($code): $message';
}

/// Keeps only overrides that replace the template for [localDate].
List<LocalInterval>? overrideFor(
  List<ScheduleOverride> overrides,
  LocalDate localDate,
) {
  for (final override in overrides) {
    if (override.localDate == localDate && override.confirmed) {
      return override.paidIntervals;
    }
  }
  return null;
}
