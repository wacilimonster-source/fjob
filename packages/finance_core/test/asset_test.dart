import 'package:finance_core/finance_core.dart';
import 'package:test/test.dart';

void main() {
  const calculator = AssetCalculator();
  final statisticsDate = LocalDate(2026, 11, 4);
  final now = DateTime.utc(2026, 11, 4, 6, 36);

  MarketCalendar openCalendar() => MarketCalendar(
        {
          for (var day = 1; day <= 30; day++)
            if (LocalDate(2026, 11, day).weekday <= 5)
              LocalDate(2026, 11, day): MarketDayStatus.open
            else
              LocalDate(2026, 11, day): MarketDayStatus.closed,
        },
        version: 'SSE@test',
      );

  Holding holding({
    String id = 'holding-1',
    String instrumentId = 'CN.SZ.000001',
    String quantity = '1000',
    String cost = '13',
    DateTime? from,
    bool pending = false,
  }) =>
      Holding(
        id: id,
        instrumentId: instrumentId,
        quantity: Rational.parse(quantity),
        costPerUnit: Rational.parse(cost),
        effectiveFromUtc: from ?? DateTime.utc(2026, 1, 1),
        pendingQuote: pending,
      );

  Quote quote({
    String instrumentId = 'CN.SZ.000001',
    String? price = '12.05',
    String? baseline = '12.4',
    LocalDate? tradingDate,
    QuoteDayBasis basis = QuoteDayBasis.exchangeTradingDay,
    MarketState state = MarketState.open,
    QuoteQuality quality = QuoteQuality.live,
    DateTime? quoteAt,
  }) =>
      Quote(
        instrumentId: instrumentId,
        priceCny: price == null ? null : Rational.parse(price),
        baselineCny: baseline == null ? null : Rational.parse(baseline),
        quoteAtUtc: quoteAt ?? now,
        fetchedAtUtc: now,
        tradingDate: tradingDate ?? statisticsDate,
        dayBasis: basis,
        marketState: state,
        quality: quality,
        source: 'fixture',
        sourceRevision: 1,
      );

  group('CALC-ASSET', () {
    test('AC-ASSET-01 multiple holdings and gold are summed per class', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [
          holding(quantity: '1000', cost: '13'),
          holding(
            id: 'holding-2',
            instrumentId: 'CN.SH.600000',
            quantity: '500',
            cost: '10',
          ),
          holding(
            id: 'gold',
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            quantity: '20',
            cost: '850',
          ),
        ],
        quotes: {
          'CN.SZ.000001': quote(),
          'CN.SH.600000': quote(
            instrumentId: 'CN.SH.600000',
            price: '11',
            baseline: '10.5',
          ),
          'GOLD.CNY_GRAM.AU9999': quote(
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            price: '905',
            baseline: '900',
            basis: QuoteDayBasis.referenceTradingDay,
          ),
        },
        marketCalendar: openCalendar(),
      );
      expect(result.stockDaily, Rational.parse('-350') + Rational.parse('250'));
      expect(result.stockHeld, Rational.parse('-950') + Rational.parse('500'));
      expect(result.goldDaily, Rational.parse('100'));
      expect(result.goldHeld, Rational.parse('1100'));
      expect(result.pendingInstrumentIds, isEmpty);
      expect(result.quality, QuoteQuality.live);
    });

    test('AC-CALC-07 a missing quote leaves the class unknown', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding(), holding(id: 'gold', instrumentId: 'GOLD.CNY_GRAM.AU9999', quantity: '20', cost: '850')],
        quotes: {
          'GOLD.CNY_GRAM.AU9999': quote(
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            price: '905',
            baseline: '900',
            basis: QuoteDayBasis.referenceTradingDay,
          ),
        },
        marketCalendar: openCalendar(),
      );
      expect(result.stockDaily, isNull);
      expect(result.stockDailyKnown, isFalse);
      expect(result.goldDaily, Rational.parse('100'));
      expect(result.pendingInstrumentIds, ['CN.SZ.000001']);
      expect(result.quality, QuoteQuality.unavailable);
    });

    test('AC-ASSET-02 a closed trading day keeps holdings and zeroes today', () {
      final result = calculator.calculate(
        asOfUtc: DateTime.utc(2026, 11, 7, 4),
        statisticsDate: LocalDate(2026, 11, 7),
        holdings: [holding()],
        quotes: {
          'CN.SZ.000001': quote(tradingDate: LocalDate(2026, 11, 6)),
        },
        marketCalendar: openCalendar(),
      );
      final position = result.positions.single;
      expect(position.status, PositionStatus.closedDay);
      expect(position.dailyPnl, Rational.zero);
      expect(position.heldPnl, Rational.parse('-950'));
      expect(result.stockDaily, Rational.zero);
    });

    test('a suspended stock does not fake a daily move', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding()],
        quotes: {'CN.SZ.000001': quote(state: MarketState.suspended)},
        marketCalendar: openCalendar(),
      );
      expect(result.positions.single.status, PositionStatus.closedDay);
      expect(result.stockDaily, Rational.zero);
    });

    test('a quote from another trading day is unknown, not zero', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding()],
        quotes: {
          'CN.SZ.000001': quote(tradingDate: LocalDate(2026, 11, 3)),
        },
        marketCalendar: openCalendar(),
      );
      expect(result.positions.single.status, PositionStatus.staleBaseline);
      expect(result.stockDaily, isNull);
    });

    test('missing baseline is unknown, hard zero is preserved', () {
      final missing = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding()],
        quotes: {'CN.SZ.000001': quote(baseline: null)},
        marketCalendar: openCalendar(),
      );
      expect(missing.positions.single.status, PositionStatus.missingBaseline);
      expect(missing.stockDaily, isNull);

      final zero = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding(quantity: '0')],
        quotes: const {},
        marketCalendar: openCalendar(),
      );
      expect(zero.positions.single.status, PositionStatus.zeroQuantity);
      expect(zero.stockDaily, Rational.zero);
    });

    test('AC-ASSET-03 gold night session keeps the reference day explicit', () {
      final inactive = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [
          holding(
            id: 'gold',
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            quantity: '20',
            cost: '850',
          ),
        ],
        quotes: {
          'GOLD.CNY_GRAM.AU9999': quote(
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            price: '905',
            baseline: '900',
            basis: QuoteDayBasis.referenceTradingDay,
            tradingDate: LocalDate(2026, 11, 3),
            state: MarketState.closed,
          ),
        },
        marketCalendar: openCalendar(),
      );
      expect(inactive.positions.single.status, PositionStatus.closedDay);
      expect(inactive.goldDaily, Rational.zero);

      final active = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [
          holding(
            id: 'gold',
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            quantity: '20',
            cost: '850',
          ),
        ],
        quotes: {
          'GOLD.CNY_GRAM.AU9999': quote(
            instrumentId: 'GOLD.CNY_GRAM.AU9999',
            price: '905',
            baseline: '900',
            basis: QuoteDayBasis.referenceTradingDay,
            tradingDate: LocalDate(2026, 11, 3),
            state: MarketState.open,
          ),
        },
        marketCalendar: openCalendar(),
        goldReferenceSessionActive: true,
      );
      expect(
        active.positions.single.status,
        PositionStatus.awaitingReferenceSession,
      );
      expect(active.goldDaily, isNull);
    });

    test('stale quotes are reported as stale', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding()],
        quotes: {
          'CN.SZ.000001': quote(quality: QuoteQuality.stale),
        },
        marketCalendar: openCalendar(),
      );
      expect(result.quality, QuoteQuality.stale);
      expect(result.stockDaily!.toDisplayString(), '-350.00');
    });

    test('the newest holding version wins', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [
          holding(quantity: '1000', cost: '13'),
          holding(
            id: 'holding-2',
            quantity: '2000',
            cost: '13',
            from: DateTime.utc(2026, 11, 1),
          ),
        ],
        quotes: {'CN.SZ.000001': quote()},
        marketCalendar: openCalendar(),
      );
      expect(result.positions.single.holding.id, 'holding-2');
      expect(result.stockDaily!.toDisplayString(), '-700.00');
    });

    test('the oldest used quote defines quotesAsOf', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [
          holding(),
          holding(id: 'h2', instrumentId: 'CN.SH.600000', quantity: '100', cost: '10'),
        ],
        quotes: {
          'CN.SZ.000001': quote(quoteAt: DateTime.utc(2026, 11, 4, 6, 30)),
          'CN.SH.600000': quote(
            instrumentId: 'CN.SH.600000',
            price: '11',
            baseline: '10.5',
            quoteAt: DateTime.utc(2026, 11, 4, 6, 36),
          ),
        },
        marketCalendar: openCalendar(),
      );
      expect(result.quotesAsOf, DateTime.utc(2026, 11, 4, 6, 30));
    });
  });

  group('CALC-FUND', () {
    Holding fundHolding({
      String id = 'fund-1',
      String code = '000001',
      String quantity = '1000.25',
      String cost = '1.2000',
    }) =>
        Holding(
          id: id,
          instrumentId: 'FUND.CN.$code',
          quantity: Rational.parse(quantity),
          costPerUnit: Rational.parse(cost),
          effectiveFromUtc: DateTime.utc(2026, 1, 1),
        );

    FundNavSnapshot nav({
      String code = '000001',
      String? navCny = '1.2356',
      LocalDate? navDate,
      String? previousNav = '1.2256',
      LocalDate? previousDate,
      FundActionStatus action = FundActionStatus.none,
      FundCalendarKind calendarKind = FundCalendarKind.mainland,
      FundEligibility eligibility = FundEligibility.supported,
      DateTime? fetchedAt,
      DateTime? publishedAt,
      QuoteQuality quality = QuoteQuality.eod,
    }) =>
        FundNavSnapshot(
          instrumentId: 'FUND.CN.$code',
          navCny: navCny == null ? null : Rational.parse(navCny),
          navDate: navDate ?? statisticsDate,
          previousNavCny:
              previousNav == null ? null : Rational.parse(previousNav),
          previousNavDate: previousDate ?? LocalDate(2026, 11, 3),
          actionStatus: action,
          fundCalendar: calendarKind,
          eligibility: eligibility,
          fetchedAtUtc: fetchedAt ?? now,
          publishedAtUtc: publishedAt,
          source: 'fixture',
          sourceRevision: null,
          quality: quality,
          sourceLicenseStatus: SourceLicenseStatus.developmentOnly,
        );

    MarketCalendar fundCalendar({Set<LocalDate> closed = const {}}) =>
        MarketCalendar(
          {
            for (var day = 1; day <= 30; day++)
              LocalDate(2026, 11, day): closed.contains(LocalDate(2026, 11, day))
                  ? MarketDayStatus.closed
                  : MarketDayStatus.open,
          },
          version: 'FUND_CN@test',
        );

    test('FND-01 stock and fund keep separate identities and totals', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [holding(), fundHolding()],
        quotes: {'CN.SZ.000001': quote()},
        marketCalendar: openCalendar(),
        fundNavs: {'FUND.CN.000001': nav()},
        fundCalendar: fundCalendar(),
      );
      expect(result.positions, hasLength(2));
      expect(result.stockDaily, Rational.parse('-350'));
      expect(result.fundDaily, Rational.parse('10.0025'));
      expect(result.stockHeld, Rational.parse('-950'));
      expect(result.fundHeld, Rational.parse('35.6089'));
      expect(result.stockFundDaily, Rational.parse('-339.9975'));
      expect(
        result.positions.map((position) => position.instrumentId),
        containsAll(['CN.SZ.000001', 'FUND.CN.000001']),
      );
    });

    test('FND-08 same-source NAV gives exact daily and held P&L', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {'FUND.CN.000001': nav()},
        fundCalendar: fundCalendar(),
      );
      final position = result.positions.single;
      expect(position.dailyPnl, Rational.parse('10.0025'));
      expect(position.dailyPnl!.toDisplayString(), '10.00');
      expect(position.heldPnl, Rational.parse('35.6089'));
      expect(position.heldPnl!.toDisplayString(), '35.61');
      expect(position.status, PositionStatus.ok);
    });

    test('FND-09 zero shares are a known zero without any NAV', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding(quantity: '0')],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: const {},
        fundCalendar: fundCalendar(),
      );
      final position = result.positions.single;
      expect(position.status, PositionStatus.zeroQuantity);
      expect(position.dailyPnl, Rational.zero);
      expect(position.heldPnl, Rational.zero);
      expect(result.fundDaily, Rational.zero);
    });

    test('FND-10 an unpublished current NAV waits instead of reusing a move',
        () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: LocalDate(2026, 11, 9),
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(navDate: LocalDate(2026, 11, 6)),
        },
        fundCalendar: fundCalendar(),
      );
      final position = result.positions.single;
      expect(position.status, PositionStatus.fundNavPending);
      expect(position.dailyPnl, isNull);
      expect(position.heldPnl, Rational.parse('35.6089'));
      expect(result.fundDaily, isNull);
    });

    test('FND-11 a confirmed mainland holiday is a known zero', () {
      final result = calculator.calculate(
        asOfUtc: DateTime.utc(2026, 11, 7, 6),
        statisticsDate: LocalDate(2026, 11, 7),
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(navDate: LocalDate(2026, 11, 6)),
        },
        fundCalendar: fundCalendar(
          closed: {LocalDate(2026, 11, 7)},
        ),
      );
      final position = result.positions.single;
      expect(position.status, PositionStatus.fundClosedDay);
      expect(position.dailyPnl, Rational.zero);
      expect(position.heldPnl, Rational.parse('35.6089'));
    });

    test('FND-12 an unknown or non-mainland calendar never guesses', () {
      final qdii = calculator.calculate(
        asOfUtc: now,
        statisticsDate: LocalDate(2026, 11, 7),
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(
            navDate: LocalDate(2026, 11, 6),
            calendarKind: FundCalendarKind.unknown,
          ),
        },
        fundCalendar: fundCalendar(closed: {LocalDate(2026, 11, 7)}),
      );
      expect(qdii.positions.single.status, PositionStatus.fundCalendarUnknown);
      expect(qdii.positions.single.dailyPnl, isNull);

      final uncovered = calculator.calculate(
        asOfUtc: now,
        statisticsDate: LocalDate(2026, 12, 1),
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(navDate: LocalDate(2026, 11, 28)),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        uncovered.positions.single.status,
        PositionStatus.fundCalendarUnknown,
      );
    });

    test('FND-13 missing, out-of-order or eventful baselines stay unknown', () {
      final missing = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {'FUND.CN.000001': nav(previousNav: null)},
        fundCalendar: fundCalendar(),
      );
      expect(
        missing.positions.single.status,
        PositionStatus.fundBaselineUnknown,
      );
      expect(missing.positions.single.heldPnl, Rational.parse('35.6089'));

      final outOfOrder = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(previousDate: statisticsDate),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        outOfOrder.positions.single.status,
        PositionStatus.fundBaselineUnknown,
      );

      final unknownEvent = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(action: FundActionStatus.unknown),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        unknownEvent.positions.single.status,
        PositionStatus.fundActionUnknown,
      );

      final detected = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(action: FundActionStatus.detected),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        detected.positions.single.status,
        PositionStatus.fundActionDetected,
      );
      expect(detected.positions.single.dailyPnl, isNull);
    });

    test('FND-13b confirmed unsupported and unconfirmed eligibility differ', () {
      final unsupported = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(eligibility: FundEligibility.unsupported),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        unsupported.positions.single.status,
        PositionStatus.fundUnsupported,
      );
      expect(unsupported.fundDaily, isNull);

      final unknown = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(eligibility: FundEligibility.unknown),
        },
        fundCalendar: fundCalendar(),
      );
      expect(
        unknown.positions.single.status,
        PositionStatus.fundEligibilityUnknown,
      );
    });

    test('FND-14 a NAV-only source has no fabricated quote time', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(publishedAt: null),
        },
        fundCalendar: fundCalendar(),
      );
      final snapshot = result.positions.single.fundNav!;
      expect(snapshot.publishedAtUtc, isNull);
      expect(snapshot.navDate, statisticsDate);
      expect(result.quotesAsOf, isNull);
    });

    test('FND-22 a future NAV is never used', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: LocalDate(2026, 11, 9),
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {
          'FUND.CN.000001': nav(navDate: LocalDate(2026, 11, 10)),
        },
        fundCalendar: fundCalendar(),
      );
      expect(result.positions.single.status, PositionStatus.fundNavFuture);
      expect(result.positions.single.heldPnl, isNull);
      expect(result.fundDaily, isNull);
    });

    test('funds never fall into the gold or stock P&L buckets', () {
      final result = calculator.calculate(
        asOfUtc: now,
        statisticsDate: statisticsDate,
        holdings: [fundHolding()],
        quotes: const {},
        marketCalendar: openCalendar(),
        fundNavs: {'FUND.CN.000001': nav()},
        fundCalendar: fundCalendar(),
      );
      expect(result.stockDaily, Rational.zero);
      expect(result.goldDaily, Rational.zero);
      expect(result.fundDaily, Rational.parse('10.0025'));
    });
  });
}
