import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/data/cn_market_calendar_2026.dart';

void main() {
  test('statutory closures and make-up Saturdays stay closed', () {
    final calendar = buildCnMarketCalendar(
      from: LocalDate(2026, 1, 1),
      to: LocalDate(2026, 12, 31),
    );
    expect(calendar.statusOn(LocalDate(2026, 2, 16)), MarketDayStatus.closed);
    expect(calendar.statusOn(LocalDate(2026, 2, 21)), MarketDayStatus.closed);
    expect(calendar.statusOn(LocalDate(2026, 2, 23)), MarketDayStatus.closed);
    expect(calendar.statusOn(LocalDate(2026, 2, 24)), MarketDayStatus.open);
    expect(calendar.statusOn(LocalDate(2026, 10, 1)), MarketDayStatus.closed);
    expect(calendar.statusOn(LocalDate(2026, 10, 8)), MarketDayStatus.open);
    expect(calendar.statusOn(LocalDate(2027, 1, 4)), MarketDayStatus.unknown);
  });
}
