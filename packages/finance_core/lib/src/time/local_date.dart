/// A calendar date without any time or host-timezone component.
///
/// Business dates (statistics day, trading day, override day) must not shift
/// when the device moves between timezones, so they are represented as plain
/// year/month/day fields and only converted to instants through an explicit
/// IANA timezone.
library;

final class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day)
      : assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  factory LocalDate.parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) throw FormatException('Invalid ISO date', value);
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = LocalDate(year, month, day);
    if (date.daysInMonth < day) {
      throw FormatException('Day out of range for month', value);
    }
    return date;
  }

  static LocalDate? tryParse(String? value) {
    if (value == null) return null;
    try {
      return LocalDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// ISO weekday, Monday = 1 ... Sunday = 7.
  int get weekday => _utc.weekday;

  bool get isWeekend => weekday >= DateTime.saturday;

  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  LocalDate get firstOfMonth => LocalDate(year, month, 1);
  LocalDate get lastOfMonth => LocalDate(year, month, daysInMonth);

  LocalDate addDays(int days) {
    final moved = _utc.add(Duration(days: days));
    return LocalDate(moved.year, moved.month, moved.day);
  }

  LocalDate addMonths(int months) {
    final total = (year * 12 + (month - 1)) + months;
    return LocalDate(total ~/ 12, total % 12 + 1, 1);
  }

  /// Every date in the month containing this date.
  List<LocalDate> datesOfMonth() {
    final first = firstOfMonth;
    return List<LocalDate>.generate(daysInMonth, (index) => first.addDays(index));
  }

  String toIsoString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  @override
  String toString() => toIsoString();

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}
