/// 2026 A-share / SGE trading calendar with statutory closures.
///
/// Closure dates were derived from SSE index trading history and checked
/// against the 2026 statutory holiday arrangement. Make-up work Saturdays are
/// still exchange holidays. Dates outside 2026 return `unknown` instead of
/// guessing with a weekend rule.
library;

import 'package:finance_core/finance_core.dart';

const String cnMarketCalendarVersion = 'CN-A-2026-v1';
const String cnMarketCalendarSource = '2026 交易日由东方财富历史行情推导并核对法定休市安排';
const String cnMarketCalendarCoverage = '2026-01-01 ~ 2026-12-31';

const Set<String> _closures2026 = <String>{
  '2026-01-01',
  '2026-01-02',
  '2026-02-16',
  '2026-02-17',
  '2026-02-18',
  '2026-02-19',
  '2026-02-20',
  '2026-02-23',
  '2026-04-06',
  '2026-05-01',
  '2026-05-04',
  '2026-05-05',
  '2026-06-19',
  '2026-09-25',
  '2026-10-01',
  '2026-10-02',
  '2026-10-05',
  '2026-10-06',
  '2026-10-07',
};

MarketCalendar buildCnMarketCalendar({
  required LocalDate from,
  required LocalDate to,
}) {
  final days = <LocalDate, MarketDayStatus>{};
  var date = from;
  while (date <= to) {
    if (date.year == 2026) {
      days[date] =
          date.weekday > 5 || _closures2026.contains(date.toIsoString())
              ? MarketDayStatus.closed
              : MarketDayStatus.open;
    } else {
      days[date] = MarketDayStatus.unknown;
    }
    date = date.addDays(1);
  }
  return MarketCalendar(
    days,
    version: cnMarketCalendarVersion,
    source: cnMarketCalendarSource,
  );
}
