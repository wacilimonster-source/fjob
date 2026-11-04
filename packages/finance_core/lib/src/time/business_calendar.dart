/// Timezone-aware day and month boundaries for the pay calendar.
///
/// Wages and fixed costs are reported in an explicit statistics timezone
/// (`Asia/Shanghai` by default). A natural day therefore has a real length
/// taken from the tz database instead of a hard-coded 86 400 seconds: that
/// keeps the allocation formula exact if a user selects a DST zone.
library;

import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';

/// Initializes the bundled IANA timezone database exactly once per isolate.
abstract final class FinanceTimeZones {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }
}

final class BusinessCalendar {
  BusinessCalendar(this.location);

  factory BusinessCalendar.forZone(String ianaName) {
    FinanceTimeZones.ensureInitialized();
    return BusinessCalendar(tz.getLocation(ianaName));
  }

  static BusinessCalendar get shanghai => _shanghai;
  static final BusinessCalendar _shanghai = BusinessCalendar.forZone('Asia/Shanghai');

  static const String defaultTimezone = 'Asia/Shanghai';

  final tz.Location location;

  String get timezoneName => location.name;

  /// Local business date of an instant.
  LocalDate dateOf(DateTime instant) {
    final local = tz.TZDateTime.from(instant.toUtc(), location);
    return LocalDate(local.year, local.month, local.day);
  }

  /// Local wall-clock timestamp of an instant.
  tz.TZDateTime localTimeOf(DateTime instant) =>
      tz.TZDateTime.from(instant.toUtc(), location);

  /// Midnight of [date] as an instant.
  DateTime startOfDayUtc(LocalDate date) =>
      tz.TZDateTime(location, date.year, date.month, date.day).toUtc();

  /// Midnight after [date] as an instant.
  DateTime endOfDayUtc(LocalDate date) => startOfDayUtc(date.addDays(1));

  /// Real length of the natural day, from the tz database.
  int dayLengthSeconds(LocalDate date) =>
      endOfDayUtc(date).difference(startOfDayUtc(date)).inSeconds;

  /// Instant at [minuteOfDay] minutes after local midnight.
  ///
  /// Values of 1440 and above spill into the following local day, which is how
  /// cross-midnight shifts are expanded.
  DateTime instantAt(LocalDate date, int minuteOfDay) {
    final dayOffset = minuteOfDay ~/ 1440;
    final remainder = minuteOfDay % 1440;
    final day = date.addDays(dayOffset);
    return tz.TZDateTime(location, day.year, day.month, day.day, remainder ~/ 60,
            remainder % 60)
        .toUtc();
  }

  /// Local wall-clock hour/minute for a minute-of-day value.
  static (int, int) wallClock(int minuteOfDay) {
    final normalized = minuteOfDay % 1440;
    return (normalized ~/ 60, normalized % 60);
  }

  /// First instant of the month containing [date].
  DateTime startOfMonthUtc(LocalDate date) => startOfDayUtc(date.firstOfMonth);

  /// First instant of the following month.
  DateTime endOfMonthUtc(LocalDate date) =>
      startOfDayUtc(date.firstOfMonth.addMonths(1));

  int daysInMonth(LocalDate date) => date.firstOfMonth.daysInMonth;

  /// The `YYYY-MM` label used by monthly bills, in the statistics timezone.
  static String monthKey(LocalDate date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}
