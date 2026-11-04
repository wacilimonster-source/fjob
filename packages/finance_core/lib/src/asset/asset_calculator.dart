/// CALC-ASSET: holdings, quotes and the two profit-and-loss figures.
library;

import '../money/rational.dart';
import '../time/local_date.dart';

enum InstrumentKind { stock, gold }

/// Internal canonical identifiers: `CN.SZ.000001`, `CN.SH.600000`,
/// `GOLD.CNY_GRAM.AU9999`.
InstrumentKind instrumentKindOf(String instrumentId) =>
    instrumentId.startsWith('GOLD.') ? InstrumentKind.gold : InstrumentKind.stock;

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
}

final class AssetPosition {
  const AssetPosition({
    required this.holding,
    required this.quote,
    required this.heldPnl,
    required this.dailyPnl,
    required this.status,
  });

  final Holding holding;
  final Quote? quote;
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
    required this.stockHeld,
    required this.goldHeld,
    required this.stockDailyKnown,
    required this.goldDailyKnown,
    required this.quotesAsOf,
    required this.quality,
    required this.pendingInstrumentIds,
    required this.quoteTimes,
  });

  final List<AssetPosition> positions;
  final Rational? stockDaily;
  final Rational? goldDaily;
  final Rational? stockHeld;
  final Rational? goldHeld;
  final bool stockDailyKnown;
  final bool goldDailyKnown;

  /// Earliest quote time used by any position, i.e. the age of the oldest data
  /// behind the summary. Null when no quote was used.
  final DateTime? quotesAsOf;
  final QuoteQuality quality;
  final List<String> pendingInstrumentIds;
  final Map<String, DateTime> quoteTimes;

  bool get hasHoldings => positions.isNotEmpty;
}

final class AssetCalculator {
  const AssetCalculator();

  AssetResult calculate({
    required DateTime asOfUtc,
    required LocalDate statisticsDate,
    required List<Holding> holdings,
    required Map<String, Quote> quotes,
    required MarketCalendar marketCalendar,
    bool goldReferenceSessionActive = false,
  }) {
    final current = _currentHoldings(holdings, asOfUtc);
    final positions = <AssetPosition>[];
    final pending = <String>[];
    final quoteTimes = <String, DateTime>{};
    final qualities = <QuoteQuality>[];

    Rational? stockDaily = Rational.zero;
    Rational? goldDaily = Rational.zero;
    Rational? stockHeld = Rational.zero;
    Rational? goldHeld = Rational.zero;

    for (final holding in current) {
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
      } else {
        goldDaily = _addKnown(goldDaily, result.dailyPnl);
        goldHeld = _addKnown(goldHeld, result.heldPnl);
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
      stockHeld: stockHeld,
      goldHeld: goldHeld,
      stockDailyKnown: stockDaily != null,
      goldDailyKnown: goldDaily != null,
      quotesAsOf: oldest,
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
}
