/// Display formatting for money, hours and percentages.
library;

import 'package:finance_core/finance_core.dart';

String formatMoney(
  Rational? value, {
  bool signed = false,
  String placeholder = '待更新',
}) {
  if (value == null) return placeholder;
  final negative = value.isNegative && !value.isZero;
  final text = _group(value.abs().toDisplayString());
  final sign = negative ? '-' : (signed ? '+' : '');
  return '$sign¥$text';
}

String formatAmount(Rational? value, {String placeholder = '待更新'}) =>
    value == null ? placeholder : value.toDisplayString();

String formatSigned(Rational? value) {
  if (value == null) return '待更新';
  final sign = value.isNegative ? '-' : '+';
  return '$sign${value.abs().toFixed(2)}';
}

String formatHours(int seconds) => (seconds / 3600).toStringAsFixed(1);

String formatPercent(Rational? value) {
  if (value == null) return '—';
  final percent = value * Rational.fromInt(100);
  final sign = percent.isNegative ? '-' : '+';
  return '$sign${percent.abs().toFixed(2)}%';
}

String formatClock(DateTime? instantUtc, BusinessCalendar calendar) {
  if (instantUtc == null) return '—';
  final local = calendar.localTimeOf(instantUtc);
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String formatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${secs.toString().padLeft(2, '0')}';
}

String formatDate(LocalDate date) =>
    '${date.month}月${date.day.toString().padLeft(2, '0')}日';

String formatMonth(LocalDate date) => '${date.year}.${date.month.toString().padLeft(2, '0')}';

String weekdayLabel(int weekday) => const <String>[
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][weekday - 1];

String _group(String plain) {
  final parts = plain.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) buffer.write(',');
    buffer.write(whole[index]);
  }
  if (parts.length > 1) buffer.write('.${parts[1]}');
  return buffer.toString();
}
