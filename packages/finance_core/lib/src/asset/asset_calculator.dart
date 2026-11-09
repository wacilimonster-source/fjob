/// CALC-ASSET: holdings, quotes and the two profit-and-loss figures.
library;

import '../money/rational.dart';
import '../time/local_date.dart';

enum InstrumentKind { stock, gold, fund }

/// Internal canonical identifiers: `CN.SZ.000001`, `CN.SH.600000`,
/// `GOLD.CNY_GRAM.AU9999` and `FUND.CN.000001`.
///
/// Only the explicit `FUND.CN.` prefix is a fund. An unknown identifier keeps
/// the historical stock behaviour and is never silently treated as a fund.
InstrumentKind instrumentKindOf(String instrumentId) {
  if (instrumentId.startsWith('FUND.CN.')) return InstrumentKind.fund;
  if (instrumentId.startsWith('GOLD.')) return InstrumentKind.gold;
  return InstrumentKind.stock;
}

enum QuoteDayBasis { exchangeTradingDay, referenceTradingDay }

enum MarketState { preopen, open, breakTime, closed, suspended, unknown }

/// `fixture` is the lowest severity: it only appears in example namespaces.
enum QuoteQuality { live, delayed, eod, stale, fixture, unavailable }

int _qualitySeverity(QuoteQuality quality) => switch (quality) {
      QuoteQuality.live => 1,
      QuoteQuality.delayed => 2,
      QuoteQuality.eod => 3,
      QuoteQuality.fixture => 0,
      QuoteQuality.stale => 4,
      QuoteQuality.unavailable => 5,
    };

QuoteQuality worstQuality(Iterable<QuoteQuality> qualities) {
  var worst = QuoteQuality.live;
  var found = false;
  for (final quality in qualities) {
    if (!found || _qualitySeverity(quality) > _qualitySeverity(worst)) {
      worst = quality;
      found = true;
    }
  }
  return found ? worst : QuoteQuality.unavailable;
}

final class Quote {
  const Quote({
    required this.instrumentId,
    required this.priceCny,
    required this.baselineCny,
    required this.quoteAtUtc,
    required this.fetchedAtUtc,
    required this.tradingDate,
    required this.dayBasis,
    required this.marketState,
    required this.quality,
    required this.source,
    required this.sourceRevision,
    this.delaySeconds,
  });

  final String instrumentId;
  final Rational? priceCny;

  /// Same-source previous-close or reference baseline. Null means the source
  /// could not supply one; the daily figure then becomes unknown, never zero.
  final Rational? baselineCny;
  final DateTime quoteAtUtc;
  final DateTime fetchedAtUtc;
  final LocalDate tradingDate;
  final QuoteDayBasis dayBasis;
  final MarketState marketState;
  final QuoteQuality quality;
  final String source;
  final int sourceRevision;
  final int? delaySeconds;

  Quote copyWith({
    Rational? priceCny,
    Rational? baselineCny,
    DateTime? quoteAtUtc,
    DateTime? fetchedAtUtc,
    LocalDate? tradingDate,
    QuoteDayBasis? dayBasis,
    MarketState? marketState,
    QuoteQuality? quality,
    String? source,
    int? sourceRevision,
  }) =>
      Quote(
        instrumentId: instrumentId,
        priceCny: priceCny ?? this.priceCny,
        baselineCny: baselineCny ?? this.baselineCny,
        quoteAtUtc: quoteAtUtc ?? this.quoteAtUtc,
        fetchedAtUtc: fetchedAtUtc ?? this.fetchedAtUtc,
        tradingDate: tradingDate ?? this.tradingDate,
        dayBasis: dayBasis ?? this.dayBasis,
        marketState: marketState ?? this.marketState,
        quality: quality ?? this.quality,
        source: source ?? this.source,
        sourceRevision: sourceRevision ?? this.sourceRevision,
        delaySeconds: delaySeconds,
      );
}

/// Dividend / split state between the previous and the current NAV date.
///
/// `none` is only valid when the source has explicit, complete coverage of the
/// interval and no event; a missing field or unverified semantics is `unknown`.
enum FundActionStatus { none, detected, unknown }

/// Whether the source has confirmed the mainland fund calendar applies.
enum FundCalendarKind { mainland, unknown }

/// Whether the product, unit, currency and holding channel are confirmed.
enum FundEligibility { supported, unsupported, unknown }

/// Public-display licence evidence for a source.
enum SourceLicenseStatus { verified, developmentOnly, unknown }

/// An exchange-listed fund NAV expressed as date-only settlement data.
///
/// This is deliberately separate from [Quote]: the source publishes a NAV date
/// and no intraday price, so the type has no fabricated `quoteAt`. Every NAV
/// value is paired with its date; a value without a date is unknown.
final class FundNavSnapshot {
  const FundNavSnapshot({
    required this.instrumentId,
    required this.navCny,
    required this.navDate,
    required this.previousNavCny,
    required this.previousNavDate,
    required this.actionStatus,
    required this.fundCalendar,
    required this.eligibility,
    required this.fetchedAtUtc,
    required this.publishedAtUtc,
    required this.source,
    required this.sourceRevision,
    required this.quality,
    required this.sourceLicenseStatus,
  });

  final String instrumentId;

  /// Latest published unit NAV (not accumulated NAV, intraday estimate, market
  /// price or 10k-share income) and the settlement date it belongs to.
  final Rational? navCny;
  final LocalDate? navDate;

  /// Previous valid NAV from the same source, strictly earlier than [navDate].
  final Rational? previousNavCny;
  final LocalDate? previousNavDate;

  final FundActionStatus actionStatus;
  final FundCalendarKind fundCalendar;
  final FundEligibility eligibility;

  /// Real fetch instants, never the NAV date or a fabricated publication time.
  final DateTime fetchedAtUtc;
  final DateTime? publishedAtUtc;

  final String source;

  /// Source revision when the upstream can prove one; null when it cannot.
  final int? sourceRevision;
  final QuoteQuality quality;
  final SourceLicenseStatus sourceLicenseStatus;

  bool get hasNav => navCny != null && navDate != null;

  bool get hasComparableBaseline =>
      previousNavCny != null &&
      previousNavDate != null &&
      navDate != null &&
      previousNavDate!.compareTo(navDate!) < 0;
}

/// A versioned holdings row. Snapshot revaluation: editing quantity or cost
/// re-estimates the current value and never creates an implied trade.
final class Holding {
  const Holding({
    required this.id,
    required this.instrumentId,
    required this.quantity,
    required this.costPerUnit,
    required this.effectiveFromUtc,
    this.effectiveToUtc,
    this.pendingQuote = false,
  });

  final String id;
  final String instrumentId;
  final Rational quantity;
  final Rational costPerUnit;
  final DateTime effectiveFromUtc;
  final DateTime? effectiveToUtc;

  /// Symbol saved before the network confirmed it.
  final bool pendingQuote;

  InstrumentKind get kind => instrumentKindOf(instrumentId);

  bool covers(DateTime instantUtc) =>
      !instantUtc.isBefore(effectiveFromUtc) &&
      (effectiveToUtc == null || instantUtc.isBefore(effectiveToUtc!));
}

/// Trading-day state used by the daily-P&L rule.
enum MarketDayStatus { open, closed, unknown }

final class MarketCalendar {
  const MarketCalendar(this.days, {this.version = 'unknown', this.source = 'none'});

  final Map<LocalDate, MarketDayStatus> days;
  final String version;
  final String source;

  MarketDayStatus statusOn(LocalDate date) =>
      days[date] ?? MarketDayStatus.unknown;
}

enum PositionStatus {
  ok,

  /// No quote at all; the position is waiting for its first price.
  pendingQuote,

  /// Quantity is zero: the P&L is a known zero even without a price.
  zeroQuantity,

  /// The statistics day is a non-trading day; today's figure is a known zero.
  closedDay,

  /// The quote belongs to another trading day; today's baseline is invalid.
  staleBaseline,

  /// The market calendar has no entry; do not guess.
  calendarUnknown,

  /// The source supplied no baseline for the trading day.
  missingBaseline,

  /// Gold's reference baseline for the active session is not available yet.
  awaitingReferenceSession,

  /// No valid published NAV (or NAV date) has been received yet.
  pendingNav,

  /// The source explicitly says money-market, exchange-traded or a foreign
  /// currency share class: it must not be valued as an ordinary fund.
  fundUnsupported,

  /// The product, currency or holding channel is not confirmed yet.
  fundEligibilityUnknown,

  /// The NAV belongs to a date after the statistics day.
  fundNavFuture,

  /// The current NAV day is a mainland fund holiday confirmed by the calendar.
  fundClosedDay,

  /// The mainland calendar has no verified coverage for the statistics day.
  fundCalendarUnknown,

  /// Today's NAV has not been published yet; the last NAV stays for valuation.
  fundNavPending,

  /// The source cannot prove whether a dividend or split occurred.
  fundActionUnknown,

  /// A dividend/split was detected; the user must review shares and cost.
  fundActionDetected,

  /// The previous-NAV baseline is missing, out of order or not comparable.
  fundBaselineUnknown,
}

final class AssetPosition {
  const AssetPosition({
    required this.holding,
    required this.quote,
    required this.heldPnl,
    required this.dailyPnl,
    required this.status,
    this.fundNav,
  });

  final Holding holding;
  final Quote? quote;

  /// Fund positions use the date-only NAV instead of a [Quote].
  final FundNavSnapshot? fundNav;
  final Rational? heldPnl;
  final Rational? dailyPnl;
  final PositionStatus status;

  String get instrumentId => holding.instrumentId;
  InstrumentKind get kind => holding.kind;
  bool get dailyKnown => dailyPnl != null;
}

final class AssetResult {
  const AssetResult({
    required this.positions,
    required this.stockDaily,
    required this.goldDaily,
    required this.fundDaily,
    required this.stockHeld,
    required this.goldHeld,
    required this.fundHeld,
    required this.stockDailyKnown,
    required this.goldDailyKnown,
    required this.fundDailyKnown,
    required this.knownStockDaily,
    required this.knownGoldDaily,
    required this.knownFundDaily,
    required this.quotesAsOf,
    required this.quality,
    required this.pendingInstrumentIds,
    required this.quoteTimes,
  });

  final List<AssetPosition> positions;
  final Rational? stockDaily;
  final Rational? goldDaily;
  final Rational? fundDaily;
  final Rational? stockHeld;
  final Rational? goldHeld;
  final Rational? fundHeld;
  final bool stockDailyKnown;
  final bool goldDailyKnown;
  final bool fundDailyKnown;

  /// Sum of the known positions only, per class. Unlike [stockDaily] these
  /// never turn null because one sibling is waiting, so CALC-TOTAL can show a
  /// truthful known subtotal without promoting it to a complete class total.
  final Rational knownStockDaily;
  final Rational knownGoldDaily;
  final Rational knownFundDaily;

  /// Earliest quote time used by any position, i.e. the age of the oldest data
  /// behind the summary. Null when no quote was used.
  final DateTime? quotesAsOf;
  final QuoteQuality quality;
  final List<String> pendingInstrumentIds;
  final Map<String, DateTime> quoteTimes;

  bool get hasHoldings => positions.isNotEmpty;

  /// Widget-only combined figure: exactly the sum of both complete classes,
  /// otherwise null. Native code must never add these itself.
  Rational? get stockFundDaily {
    final stocks = stockDaily;
    final funds = fundDaily;
    if (stocks == null || funds == null) return null;
    return stocks + funds;
  }
}

final class AssetCalculator {
  const AssetCalculator();

  AssetResult calculate({
    required DateTime asOfUtc,
    required LocalDate statisticsDate,
    required List<Holding> holdings,
    required Map<String, Quote> quotes,
    required MarketCalendar marketCalendar,
    Map<String, FundNavSnapshot> fundNavs = const {},
    MarketCalendar fundCalendar = const MarketCalendar({}),
    bool goldReferenceSessionActive = false,
  }) {
    final current = _currentHoldings(holdings, asOfUtc);
    final positions = <AssetPosition>[];
    final pending = <String>[];
    final quoteTimes = <String, DateTime>{};
    final qualities = <QuoteQuality>[];
    var hasFundPosition = false;

    Rational? stockDaily = Rational.zero;
    Rational? goldDaily = Rational.zero;
    Rational? fundDaily = Rational.zero;
    Rational? stockHeld = Rational.zero;
    Rational? goldHeld = Rational.zero;
    Rational? fundHeld = Rational.zero;
    var knownStockDaily = Rational.zero;
    var knownGoldDaily = Rational.zero;
    var knownFundDaily = Rational.zero;

    for (final holding in current) {
      if (holding.kind == InstrumentKind.fund) {
        final nav = fundNavs[holding.instrumentId];
        // A zero-share fund is a known zero; it neither waits for data nor
        // removes the precise as-of time from the summary.
        if (!holding.quantity.isZero) {
          hasFundPosition = true;
          if (nav == null || !nav.hasNav) {
            pending.add(holding.instrumentId);
            qualities.add(QuoteQuality.unavailable);
          } else {
            qualities.add(nav.quality);
          }
        }
        final result = _evaluateFund(
          holding: holding,
          nav: nav,
          statisticsDate: statisticsDate,
          fundCalendar: fundCalendar,
        );
        positions.add(result);
        fundDaily = _addKnown(fundDaily, result.dailyPnl);
        fundHeld = _addKnown(fundHeld, result.heldPnl);
        if (result.dailyPnl != null) knownFundDaily += result.dailyPnl!;
        continue;
      }

      final quote = quotes[holding.instrumentId];
      if (quote == null || quote.priceCny == null) {
        pending.add(holding.instrumentId);
        qualities.add(QuoteQuality.unavailable);
      } else {
        quoteTimes[holding.instrumentId] = quote.quoteAtUtc;
        qualities.add(quote.quality);
      }

      final result = _evaluate(
        holding: holding,
        quote: quote,
        statisticsDate: statisticsDate,
        marketCalendar: marketCalendar,
        goldReferenceSessionActive: goldReferenceSessionActive,
      );
      positions.add(result);

      if (holding.kind == InstrumentKind.stock) {
        stockDaily = _addKnown(stockDaily, result.dailyPnl);
        stockHeld = _addKnown(stockHeld, result.heldPnl);
        if (result.dailyPnl != null) knownStockDaily += result.dailyPnl!;
      } else {
        goldDaily = _addKnown(goldDaily, result.dailyPnl);
        goldHeld = _addKnown(goldHeld, result.heldPnl);
        if (result.dailyPnl != null) knownGoldDaily += result.dailyPnl!;
      }
    }

    DateTime? oldest;
    for (final time in quoteTimes.values) {
      if (oldest == null || time.isBefore(oldest)) oldest = time;
    }

    return AssetResult(
      positions: positions,
      stockDaily: stockDaily,
      goldDaily: goldDaily,
      fundDaily: fundDaily,
      stockHeld: stockHeld,
      goldHeld: goldHeld,
      fundHeld: fundHeld,
      stockDailyKnown: stockDaily != null,
      goldDailyKnown: goldDaily != null,
      fundDailyKnown: fundDaily != null,
      knownStockDaily: knownStockDaily,
      knownGoldDaily: knownGoldDaily,
      knownFundDaily: knownFundDaily,
      // A fund only has a settlement date, not a trustworthy quote instant, so
      // a summary that includes one cannot claim a precise as-of time.
      quotesAsOf: hasFundPosition ? null : oldest,
      quality: worstQuality(qualities),
      pendingInstrumentIds: pending,
      quoteTimes: quoteTimes,
    );
  }

  static Rational? _addKnown(Rational? sum, Rational? value) {
    if (sum == null || value == null) return null;
    return sum + value;
  }

  List<Holding> _currentHoldings(List<Holding> holdings, DateTime asOfUtc) {
    final latest = <String, Holding>{};
    for (final holding in holdings) {
      if (!holding.covers(asOfUtc)) continue;
      final existing = latest[holding.instrumentId];
      if (existing == null ||
          holding.effectiveFromUtc.isAfter(existing.effectiveFromUtc)) {
        latest[holding.instrumentId] = holding;
      }
    }
    final result = latest.values.toList()
      ..sort((a, b) => a.instrumentId.compareTo(b.instrumentId));
    return result;
  }

  AssetPosition _evaluate({
    required Holding holding,
    required Quote? quote,
    required LocalDate statisticsDate,
    required MarketCalendar marketCalendar,
    required bool goldReferenceSessionActive,
  }) {
    if (holding.quantity.isZero) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: Rational.zero,
        dailyPnl: Rational.zero,
        status: PositionStatus.zeroQuantity,
      );
    }
    if (quote == null || quote.priceCny == null) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: null,
        dailyPnl: null,
        status: PositionStatus.pendingQuote,
      );
    }

    final price = quote.priceCny!;
    final held = (price - holding.costPerUnit) * holding.quantity;

    if (holding.kind == InstrumentKind.gold) {
      if (quote.tradingDate == statisticsDate) {
        final baseline = quote.baselineCny;
        if (baseline == null) {
          return AssetPosition(
            holding: holding,
            quote: quote,
            heldPnl: held,
            dailyPnl: null,
            status: PositionStatus.missingBaseline,
          );
        }
        return AssetPosition(
          holding: holding,
          quote: quote,
          heldPnl: held,
          dailyPnl: (price - baseline) * holding.quantity,
          status: PositionStatus.ok,
        );
      }
      if (!goldReferenceSessionActive) {
        return AssetPosition(
          holding: holding,
          quote: quote,
          heldPnl: held,
          dailyPnl: Rational.zero,
          status: PositionStatus.closedDay,
        );
      }
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: null,
        status: PositionStatus.awaitingReferenceSession,
      );
    }

    final dayStatus = marketCalendar.statusOn(statisticsDate);
    if (dayStatus == MarketDayStatus.closed) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: Rational.zero,
        status: PositionStatus.closedDay,
      );
    }
    if (dayStatus == MarketDayStatus.unknown) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: null,
        status: PositionStatus.calendarUnknown,
      );
    }
    if (quote.marketState == MarketState.suspended) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: Rational.zero,
        status: PositionStatus.closedDay,
      );
    }
    if (quote.tradingDate != statisticsDate) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: null,
        status: PositionStatus.staleBaseline,
      );
    }
    final baseline = quote.baselineCny;
    if (baseline == null) {
      return AssetPosition(
        holding: holding,
        quote: quote,
        heldPnl: held,
        dailyPnl: null,
        status: PositionStatus.missingBaseline,
      );
    }
    return AssetPosition(
      holding: holding,
      quote: quote,
      heldPnl: held,
      dailyPnl: (price - baseline) * holding.quantity,
      status: PositionStatus.ok,
    );
  }

  /// CALC-FUND-HELD and CALC-FUND-DAILY for one open-ended fund position.
  ///
  /// Funds never fall through the stock trading-day branch: a fund NAV has a
  /// settlement date, not an exchange quote, and its daily move needs the same
  /// source's previous NAV plus a confirmed no-event interval.
  AssetPosition _evaluateFund({
    required Holding holding,
    required FundNavSnapshot? nav,
    required LocalDate statisticsDate,
    required MarketCalendar fundCalendar,
  }) {
    if (holding.quantity.isZero) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: Rational.zero,
        dailyPnl: Rational.zero,
        status: PositionStatus.zeroQuantity,
      );
    }
    if (nav == null || !nav.hasNav || nav.navCny == null || nav.navDate == null) {
      final status = switch (nav?.eligibility) {
        FundEligibility.unsupported => PositionStatus.fundUnsupported,
        FundEligibility.unknown => PositionStatus.fundEligibilityUnknown,
        _ => PositionStatus.pendingNav,
      };
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: null,
        dailyPnl: null,
        status: status,
      );
    }
    if (nav.eligibility == FundEligibility.unsupported) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: null,
        dailyPnl: null,
        status: PositionStatus.fundUnsupported,
      );
    }
    if (nav.eligibility == FundEligibility.unknown) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: null,
        dailyPnl: null,
        status: PositionStatus.fundEligibilityUnknown,
      );
    }

    final navValue = nav.navCny!;
    final navDate = nav.navDate!;
    if (navDate.compareTo(statisticsDate) > 0) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: null,
        dailyPnl: null,
        status: PositionStatus.fundNavFuture,
      );
    }

    final held = (navValue - holding.costPerUnit) * holding.quantity;

    if (navDate == statisticsDate) {
      if (nav.actionStatus == FundActionStatus.detected) {
        return AssetPosition(
          holding: holding,
          quote: null,
          fundNav: nav,
          heldPnl: held,
          dailyPnl: null,
          status: PositionStatus.fundActionDetected,
        );
      }
      if (nav.actionStatus == FundActionStatus.unknown) {
        return AssetPosition(
          holding: holding,
          quote: null,
          fundNav: nav,
          heldPnl: held,
          dailyPnl: null,
          status: PositionStatus.fundActionUnknown,
        );
      }
      if (!nav.hasComparableBaseline) {
        return AssetPosition(
          holding: holding,
          quote: null,
          fundNav: nav,
          heldPnl: held,
          dailyPnl: null,
          status: PositionStatus.fundBaselineUnknown,
        );
      }
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: held,
        dailyPnl: (navValue - nav.previousNavCny!) * holding.quantity,
        status: PositionStatus.ok,
      );
    }

    // The latest NAV predates the statistics day. Only a confirmed mainland
    // fund holiday can make today's figure a known zero; everything else waits
    // for today's NAV instead of reusing the previous day's move.
    if (nav.fundCalendar != FundCalendarKind.mainland) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: held,
        dailyPnl: null,
        status: PositionStatus.fundCalendarUnknown,
      );
    }
    final dayStatus = fundCalendar.statusOn(statisticsDate);
    if (dayStatus == MarketDayStatus.closed) {
      return AssetPosition(
        holding: holding,
        quote: null,
        fundNav: nav,
        heldPnl: held,
        dailyPnl: Rational.zero,
        status: PositionStatus.fundClosedDay,
      );
    }
    return AssetPosition(
      holding: holding,
      quote: null,
      fundNav: nav,
      heldPnl: held,
      dailyPnl: null,
      status: dayStatus == MarketDayStatus.open
          ? PositionStatus.fundNavPending
          : PositionStatus.fundCalendarUnknown,
    );
  }
}
