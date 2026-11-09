import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  final calendar = BusinessCalendar.shanghai;
  final calculator = DashboardCalculator(calendar);

  final schedule = ScheduleVersion(
    id: 'schedule-1',
    timezone: 'Asia/Shanghai',
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: DateTime.utc(2026, 1, 1),
  );

  SalaryVersion salary({String monthly = '12000', String id = 'salary-1'}) =>
      SalaryVersion(
        id: id,
        monthlyNetCny: Rational.parse(monthly),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
        scheduleVersionId: 'schedule-1',
      );

  HousingVersion housing({HousingMode mode = HousingMode.mortgage}) =>
      HousingVersion(
        id: 'housing-1',
        mode: mode,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  CarVersion carPlan() => CarVersion(
        id: 'car-1',
        enabled: true,
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  MonthlyBill housingBill({String? principal = '2800', BillStatus? status}) =>
      MonthlyBill(
        expenseId: 'housing-1',
        kind: ExpenseKind.housing,
        month: LocalDate(2026, 11, 1),
        monthlyAmountCny: Rational.parse('4800'),
        principalCny: principal == null ? null : Rational.parse(principal),
        status: status ?? BillStatus.confirmed,
      );

  MonthlyBill carBill({String? principal = '1500'}) => MonthlyBill(
        expenseId: 'car-1',
        kind: ExpenseKind.car,
        month: LocalDate(2026, 11, 1),
        monthlyAmountCny: Rational.parse('1800'),
        principalCny: principal == null ? null : Rational.parse(principal),
      );

  MarketCalendar calendarFor(LocalDate date) => MarketCalendar(
        {
          for (var day = 1; day <= date.daysInMonth; day++)
            if (LocalDate(date.year, date.month, day).weekday <= 5)
              LocalDate(date.year, date.month, day): MarketDayStatus.open
            else
              LocalDate(date.year, date.month, day): MarketDayStatus.closed,
        },
        version: 'SSE@test',
      );

  Holding stock() => Holding(
        id: 'holding-1',
        instrumentId: 'CN.SZ.000001',
        quantity: Rational.parse('1000'),
        costPerUnit: Rational.parse('13'),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  Holding gold() => Holding(
        id: 'gold',
        instrumentId: 'GOLD.CNY_GRAM.AU9999',
        quantity: Rational.parse('20'),
        costPerUnit: Rational.parse('850'),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  Map<String, Quote> quotesAt(DateTime quoteAt) => {
        'CN.SZ.000001': Quote(
          instrumentId: 'CN.SZ.000001',
          priceCny: Rational.parse('12.05'),
          baselineCny: Rational.parse('12.4'),
          quoteAtUtc: quoteAt,
          fetchedAtUtc: quoteAt,
          tradingDate: LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.exchangeTradingDay,
          marketState: MarketState.open,
          quality: QuoteQuality.fixture,
          source: 'fixture',
          sourceRevision: 1,
        ),
        'GOLD.CNY_GRAM.AU9999': Quote(
          instrumentId: 'GOLD.CNY_GRAM.AU9999',
          priceCny: Rational.parse('905'),
          baselineCny: Rational.parse('900'),
          quoteAtUtc: quoteAt,
          fetchedAtUtc: quoteAt,
          tradingDate: LocalDate(2026, 11, 4),
          dayBasis: QuoteDayBasis.referenceTradingDay,
          marketState: MarketState.open,
          quality: QuoteQuality.fixture,
          source: 'fixture',
          sourceRevision: 1,
        ),
      };

  CalculationInput input({
    DateTime? now,
    List<Holding>? holdings,
    Map<String, Quote>? quotes,
    List<MonthlyBill>? bills,
    List<SalaryVersion>? salaries,
    ScheduleVersion? scheduleVersion,
    Map<String, FundNavSnapshot> fundNavs = const {},
    MarketCalendar? fundCalendar,
  }) {
    final instant = now ?? DateTime.utc(2026, 11, 4, 6, 36);
    return CalculationInput(
      nowUtc: instant,
      ledgerRevision: 3,
      calendar: calendar,
      salaryVersions: salaries ?? [salary()],
      schedules: {'schedule-1': scheduleVersion ?? schedule},
      overrides: const [],
      holdings: holdings ?? [stock(), gold()],
      quotes: quotes ?? quotesAt(instant),
      marketCalendar: calendarFor(calendar.dateOf(instant)),
      fundNavs: fundNavs,
      fundCalendar: fundCalendar ?? calendarFor(calendar.dateOf(instant)),
      housingVersions: [housing()],
      carVersions: [carPlan()],
      bills: bills ?? [housingBill(), carBill()],
    );
  }

  Holding fundHolding(
    String code, {
    String quantity = '1000.25',
    String cost = '1.2000',
  }) =>
      Holding(
        id: 'fund-$code',
        instrumentId: 'FUND.CN.$code',
        quantity: Rational.parse(quantity),
        costPerUnit: Rational.parse(cost),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );

  FundNavSnapshot fundNav({
    String code = '000001',
    String navCny = '1.2356',
    String previousNav = '1.2256',
    FundActionStatus action = FundActionStatus.none,
    FundEligibility eligibility = FundEligibility.supported,
    LocalDate? navDate,
  }) =>
      FundNavSnapshot(
        instrumentId: 'FUND.CN.$code',
        navCny: Rational.parse(navCny),
        navDate: navDate ?? LocalDate(2026, 11, 4),
        previousNavCny: Rational.parse(previousNav),
        previousNavDate: LocalDate(2026, 11, 3),
        actionStatus: action,
        fundCalendar: FundCalendarKind.mainland,
        eligibility: eligibility,
        fetchedAtUtc: DateTime.utc(2026, 11, 4, 6, 36),
        publishedAtUtc: null,
        source: 'fixture',
        sourceRevision: null,
        quality: QuoteQuality.eod,
        sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
      );

  group('CALC-TOTAL', () {
    test('the reference scenario reproduces -55.26', () {
      final snapshot = calculator.calculate(input());
      expect(snapshot.total!.toDisplayString(), '-55.26');
      expect(snapshot.wage!.toDisplayString(), '328.57');
      expect(snapshot.stockDaily!.toDisplayString(), '-350.00');
      expect(snapshot.goldDaily!.toDisplayString(), '100.00');
      expect(snapshot.housing!.toDisplayString(), '97.33');
      expect(snapshot.car!.toDisplayString(), '36.50');
      expect(snapshot.principal!.toDisplayString(), '87.19');
      expect(snapshot.interest!.toDisplayString(), '46.64');
      expect(snapshot.completeness, Completeness.complete);
      expect(snapshot.breakdownComplete, isTrue);
      expect(snapshot.ledgerRevision, 3);
      expect(snapshot.statisticsDate, LocalDate(2026, 11, 4));
      expect(snapshot.timezone, 'Asia/Shanghai');
      expect(snapshot.quoteQuality, QuoteQuality.fixture);
    });

    test('missing quotes keep a partial subtotal (CALC-17)', () {
      final snapshot = calculator.calculate(input(quotes: const {}));
      expect(snapshot.total!.toDisplayString(), '194.74');
      expect(snapshot.completeness, Completeness.partial);
      expect(snapshot.stockDaily, isNull);
      expect(snapshot.goldDaily, isNull);
      expect(snapshot.notes, contains(DashboardNote.missingQuotes));
    });

    test('an invalid schedule makes the headline unavailable', () {
      final empty = ScheduleVersion(
        id: 'empty',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(List<List<ShiftTemplate>>.filled(7, const [])),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      final snapshot = calculator.calculate(
        input(scheduleVersion: empty, bills: const []),
      );
      expect(snapshot.completeness, Completeness.unavailable);
      expect(snapshot.total, isNull);
      expect(snapshot.notes, contains(DashboardNote.invalidSchedule));
    });

    test('zero holdings and no fixed costs are known zeros', () {
      final instant = DateTime.utc(2026, 11, 4, 6, 36);
      final snapshot = calculator.calculate(
        CalculationInput(
          nowUtc: instant,
          ledgerRevision: 1,
          calendar: calendar,
          salaryVersions: [salary()],
          schedules: {'schedule-1': schedule},
          overrides: const [],
          holdings: const [],
          quotes: const {},
          marketCalendar: calendarFor(calendar.dateOf(instant)),
          housingVersions: [
            HousingVersion(
              id: 'housing-none',
              mode: HousingMode.none,
              effectiveFromUtc: DateTime.utc(2026, 1, 1),
            ),
          ],
          carVersions: const [],
          bills: const [],
        ),
      );
      expect(snapshot.completeness, Completeness.complete);
      expect(snapshot.total!.toDisplayString(), '328.57');
      expect(snapshot.stockDaily, Rational.zero);
      expect(snapshot.goldDaily, Rational.zero);
      expect(snapshot.housing, Rational.zero);
      expect(snapshot.car, Rational.zero);
      expect(snapshot.principal, Rational.zero);
      expect(snapshot.quoteQuality, QuoteQuality.live);
      expect(snapshot.notes, contains(DashboardNote.noHoldings));
      expect(snapshot.notes, contains(DashboardNote.housingNotConfigured));
    });

    test('a missing housing bill is partial, not unavailable', () {
      final snapshot = calculator.calculate(
        input(bills: [carBill()]),
      );
      expect(snapshot.completeness, Completeness.partial);
      expect(snapshot.housing, isNull);
      expect(snapshot.total, isNotNull);
      expect(snapshot.notes, contains(DashboardNote.missingHousingBill));
    });

    test('an unknown principal only affects the break-down', () {
      final snapshot = calculator.calculate(
        input(bills: [housingBill(principal: null), carBill()]),
      );
      expect(snapshot.completeness, Completeness.complete);
      expect(snapshot.total!.toDisplayString(), '-55.26');
      expect(snapshot.breakdownComplete, isFalse);
      expect(snapshot.principal, isNull);
      expect(snapshot.interest, isNull);
      expect(snapshot.notes, contains(DashboardNote.principalUnknown));
    });

    test('a carried-forward bill is marked as an estimate', () {
      final snapshot = calculator.calculate(
        input(bills: [
          housingBill(status: BillStatus.carriedForwardEstimate),
          carBill(),
        ]),
      );
      expect(snapshot.estimate, isTrue);
      expect(snapshot.notes, contains(DashboardNote.carriedForwardEstimate));
    });
  });

  group('CALC-TOTAL-FUND', () {
    test('FND-15 a known fund keeps the partial subtotal alive', () {
      final snapshot = calculator.calculate(
        input(
          holdings: [
            stock(),
            gold(),
            fundHolding('000001'),
            fundHolding('110022'),
          ],
          fundNavs: {'FUND.CN.000001': fundNav()},
        ),
      );
      expect(snapshot.fundDaily, isNull);
      expect(snapshot.assets.knownFundDaily, Rational.parse('10.0025'));
      expect(snapshot.stockDaily, Rational.parse('-350'));
      expect(snapshot.goldDaily, Rational.parse('100'));
      expect(snapshot.completeness, Completeness.partial);
      expect(snapshot.notes, contains(DashboardNote.fundNavPending));
      // The known fund subtotal never disappears because another one is
      // waiting; the total is the old formula plus that known fund part.
      final expected = snapshot.wage! -
          snapshot.housing! -
          snapshot.car! +
          snapshot.stockDaily! +
          snapshot.goldDaily! +
          Rational.parse('10.0025');
      expect(snapshot.total, expected);
      expect(snapshot.stockFundDaily, isNull);
    });

    test('FND-18 complete stock and fund classes expose one widget sum', () {
      final snapshot = calculator.calculate(
        input(
          holdings: [stock(), gold(), fundHolding('000001')],
          fundNavs: {'FUND.CN.000001': fundNav()},
        ),
      );
      expect(snapshot.completeness, Completeness.complete);
      expect(snapshot.fundDaily, Rational.parse('10.0025'));
      final stocks = snapshot.stockDaily!;
      final funds = snapshot.fundDaily!;
      expect(snapshot.stockFundDaily, stocks + funds);
      // -350 + 10.0025 = -339.9975, HALF_UP at two decimals is -340.00.
      expect(snapshot.stockFundDaily!.toDisplayString(), '-340.00');
      // Gold stays a separate bucket and is never folded into the widget sum.
      expect(snapshot.goldDaily, Rational.parse('100'));
    });

    test('no fund holdings keep a known zero and the old total', () {
      final snapshot = calculator.calculate(input());
      expect(snapshot.fundDaily, Rational.zero);
      expect(snapshot.stockFundDaily, snapshot.stockDaily);
      expect(snapshot.total!.toDisplayString(), '-55.26');
    });

    test('fund action review and eligibility notes are distinct', () {
      final review = calculator.calculate(
        input(
          holdings: [fundHolding('000001')],
          fundNavs: {
            'FUND.CN.000001': fundNav(action: FundActionStatus.detected),
          },
        ),
      );
      expect(review.notes, contains(DashboardNote.fundActionReview));
      expect(review.completeness, Completeness.partial);
      expect(review.fundDaily, isNull);

      final unsupported = calculator.calculate(
        input(
          holdings: [fundHolding('000198')],
          fundNavs: {
            'FUND.CN.000198': fundNav(
              code: '000198',
              eligibility: FundEligibility.unsupported,
            ),
          },
        ),
      );
      expect(
        unsupported.notes,
        contains(DashboardNote.fundEligibilityUnconfirmed),
      );
      expect(unsupported.fundDaily, isNull);
    });
  });

  group('day phase', () {
    test('working, break, before and after the shift', () {
      DayPhase phaseAt(int hour, int minute) => calculator
          .calculate(input(now: DateTime.utc(2026, 11, 4, hour - 8, minute)))
          .phase;

      expect(phaseAt(8, 30), DayPhase.beforeShift);
      expect(phaseAt(10, 0), DayPhase.working);
      expect(phaseAt(12, 30), DayPhase.breakTime);
      expect(phaseAt(14, 36), DayPhase.working);
      expect(phaseAt(19, 0), DayPhase.afterShift);
    });

    test('a weekend is a rest day', () {
      final snapshot = calculator.calculate(
        input(
          now: DateTime.utc(2026, 11, 7, 4),
          quotes: quotesAt(DateTime.utc(2026, 11, 6, 7)),
          bills: [housingBill(), carBill()],
        ),
      );
      expect(snapshot.phase, DayPhase.restDay);
      expect(snapshot.statisticsDate, LocalDate(2026, 11, 7));
      expect(snapshot.wage, Rational.zero);
      // 12:00 Shanghai on a rest day: half of the 220 daily fixed cost.
      expect(snapshot.total!.toDisplayString(), '-110.00');
    });
  });
}
