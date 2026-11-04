/// Quote refresh and calendar seeding.
library;

import 'package:finance_core/finance_core.dart';

import 'ledger_repository.dart';
import 'market_client.dart';

final class QuoteRefreshOutcome {
  const QuoteRefreshOutcome({
    required this.success,
    required this.quoteCount,
    required this.serverTime,
    this.message,
    this.errors = const {},
  });

  final bool success;
  final int quoteCount;
  final DateTime serverTime;
  final String? message;
  final Map<String, String> errors;

  static QuoteRefreshOutcome failure(String message, DateTime now) =>
      QuoteRefreshOutcome(
        success: false,
        quoteCount: 0,
        serverTime: now,
        message: message,
      );
}

final class QuoteRepository {
  QuoteRepository({
    required this.client,
    required this.ledger,
    required this.calendar,
  });

  final MarketClient client;
  final LedgerRepository ledger;
  final BusinessCalendar calendar;

  bool _calendarChecked = false;

  String get sourceLabel => client.sourceLabel;

  bool get isFixture => client.isFixture;

  Future<void> ensureCalendar({required DateTime nowUtc}) async {
    if (_calendarChecked) return;
    final today = calendar.dateOf(nowUtc);
    final covered = await ledger.hasCalendarDay(market: 'SSE', date: today) &&
        await ledger.hasCalendarDay(market: 'SGE', date: today);
    if (covered) {
      _calendarChecked = true;
      return;
    }
    try {
      final from = today.addDays(-7);
      final to = today.addDays(45);
      final sse = await client.fetchCalendar(market: 'SSE', from: from, to: to);
      await ledger.saveCalendarDays(market: 'SSE', days: sse.days);
      final sge = await client.fetchCalendar(market: 'SGE', from: from, to: to);
      await ledger.saveCalendarDays(market: 'SGE', days: sge.days);
      _calendarChecked = true;
    } on Object {
      // A missing calendar is not fatal: the asset rule reports unknown rather
      // than guessing whether today is a trading day.
    }
  }

  Future<QuoteRefreshOutcome> refresh(
    List<String> instrumentIds, {
    required DateTime nowUtc,
  }) async {
    await ensureCalendar(nowUtc: nowUtc);
    if (instrumentIds.isEmpty) {
      return QuoteRefreshOutcome(
        success: true,
        quoteCount: 0,
        serverTime: nowUtc,
      );
    }
    try {
      final batch = await client.fetchQuotes(instrumentIds, nowUtc: nowUtc);
      await ledger.saveQuotes(batch.quotes.values.toList());
      final allFailed =
          batch.quotes.isEmpty && batch.errors.isNotEmpty;
      return QuoteRefreshOutcome(
        success: !allFailed,
        quoteCount: batch.quotes.length,
        serverTime: batch.serverTime,
        message: allFailed ? '报价暂时没赶上，工资还在走。' : null,
        errors: batch.errors,
      );
    } on MarketUnavailableException catch (error) {
      return QuoteRefreshOutcome.failure(error.message, nowUtc);
    } on Object {
      return QuoteRefreshOutcome.failure(
        '报价暂时没赶上，工资还在走。当前显示上次缓存。',
        nowUtc,
      );
    }
  }
}
