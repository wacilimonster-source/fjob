/// Isolated example ledger for the welcome screen's demo mode.
///
/// It mirrors the prototype numbers, uses the fixed 2026-11-04 14:36 Shanghai
/// clock and never touches storage.
library;

import 'package:finance_core/finance_core.dart';

import 'ledger.dart';

LedgerState buildDemoLedger(BusinessCalendar calendar, DateTime nowUtc) {
  final date = calendar.dateOf(nowUtc);
  final month = date.firstOfMonth;
  final effective = calendar.startOfDayUtc(month);
  final monthDays = month.datesOfMonth();

  final schedule = ScheduleVersion(
    id: 'demo-schedule',
    timezone: calendar.timezoneName,
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: effective,
  );
  final salary = SalaryVersion(
    id: 'demo-salary',
    monthlyNetCny: Rational.parse('12000'),
    effectiveFromUtc: effective,
    scheduleVersionId: schedule.id,
  );

  final calendarDays = <LocalDate, MarketDayStatus>{};
  for (final day in monthDays) {
    calendarDays[day] =
        day.weekday <= 5 ? MarketDayStatus.open : MarketDayStatus.closed;
  }

  Quote quote({
    required String id,
    required String price,
    required String baseline,
    required QuoteDayBasis basis,
  }) =>
      Quote(
        instrumentId: id,
        priceCny: Rational.parse(price),
        baselineCny: Rational.parse(baseline),
        quoteAtUtc: nowUtc,
        fetchedAtUtc: nowUtc,
        tradingDate: date,
        dayBasis: basis,
        marketState: MarketState.open,
        quality: QuoteQuality.fixture,
        source: 'fixture',
        sourceRevision: 1,
      );

  return LedgerState(
    settings: AppSettings(
      ledgerRevision: 1,
      salaryTimezone: calendar.timezoneName,
      onboardingCompletedAt: nowUtc,
      sampleMode: true,
    ),
    salaryVersions: [salary],
    schedules: {schedule.id: schedule},
    overrides: const [],
    holdings: [
      Holding(
        id: 'demo-stock',
        instrumentId: 'CN.SZ.000001',
        quantity: Rational.parse('1000'),
        costPerUnit: Rational.parse('13'),
        effectiveFromUtc: nowUtc,
      ),
      Holding(
        id: 'demo-gold',
        instrumentId: 'GOLD.CNY_GRAM.AU9999',
        quantity: Rational.parse('20'),
        costPerUnit: Rational.parse('850'),
        effectiveFromUtc: nowUtc,
      ),
    ],
    housingVersions: [
      HousingVersion(
        id: 'demo-housing',
        mode: HousingMode.mortgage,
        effectiveFromUtc: effective,
      ),
    ],
    carVersions: [
      CarVersion(id: 'demo-car', enabled: true, effectiveFromUtc: effective),
    ],
    bills: [
      MonthlyBill(
        expenseId: 'demo-housing',
        kind: ExpenseKind.housing,
        month: month,
        monthlyAmountCny: Rational.parse('4800'),
        principalCny: Rational.parse('2800'),
      ),
      MonthlyBill(
        expenseId: 'demo-car',
        kind: ExpenseKind.car,
        month: month,
        monthlyAmountCny: Rational.parse('1800'),
        principalCny: Rational.parse('1500'),
      ),
    ],
    quotes: {
      'CN.SZ.000001': quote(
        id: 'CN.SZ.000001',
        price: '12.05',
        baseline: '12.4',
        basis: QuoteDayBasis.exchangeTradingDay,
      ),
      'GOLD.CNY_GRAM.AU9999': quote(
        id: 'GOLD.CNY_GRAM.AU9999',
        price: '905',
        baseline: '900',
        basis: QuoteDayBasis.referenceTradingDay,
      ),
    },
    marketCalendar: MarketCalendar(
      calendarDays,
      version: 'FIXTURE@demo',
      source: 'fixture',
    ),
    goldReferenceSessionActive: true,
  );
}
