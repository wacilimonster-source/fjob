/// Quote refresh and calendar seeding.
library;

import 'package:finance_core/finance_core.dart';

import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'market_client.dart';

final class QuoteRefreshOutcome {
  const QuoteRefreshOutcome({
    required this.success,
    required this.quoteCount,
    required this.serverTime,
    this.fundCount = 0,
    this.message,
    this.errors = const {},
  });

  final bool success;
  final int quoteCount;
  final int fundCount;
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
    // Always refresh once per session so an older fixture calendar is replaced
    // by the versioned statutory-holiday calendar.
    try {
      final from = today.addDays(-7);
      final to = today.addDays(45);
      final sse = await client.fetchCalendar(market: 'SSE', from: from, to: to);
      await ledger.saveCalendarDays(market: 'SSE', days: sse.days);
      final sge = await client.fetchCalendar(market: 'SGE', from: from, to: to);
      await ledger.saveCalendarDays(market: 'SGE', days: sge.days);
      final fund =
          await client.fetchCalendar(market: 'FUND_CN', from: from, to: to);
      await ledger.saveCalendarDays(market: 'FUND_CN', days: fund.days);
      _calendarChecked = true;
    } on Object {
      // A missing calendar is not fatal: the asset rule reports unknown rather
      // than guessing whether today is a trading day.
    }
  }

  Future<QuoteRefreshOutcome> refresh(
    List<String> instrumentIds, {
    required DateTime nowUtc,
    bool manual = false,
  }) async {
    await ensureCalendar(nowUtc: nowUtc);
    if (instrumentIds.isEmpty) {
      return QuoteRefreshOutcome(
        success: true,
        quoteCount: 0,
        serverTime: nowUtc,
      );
    }
    final securityIds = <String>[
      for (final id in instrumentIds)
        if (!isFundInstrumentId(id)) id,
    ];
    final fundIds = <String>[
      for (final id in instrumentIds)
        if (isFundInstrumentId(id)) id,
    ];
    final errors = <String, String>{};
    var quoteCount = 0;
    var fundCount = 0;
    var succeeded = 0;
    var attempted = 0;
    String? message;
    var serverTime = nowUtc;

    if (securityIds.isNotEmpty) {
      attempted += securityIds.length;
      try {
        final batch = await client.fetchQuotes(securityIds, nowUtc: nowUtc);
        await ledger.saveQuotes(batch.quotes.values.toList());
        quoteCount = batch.quotes.length;
        succeeded += batch.quotes.length;
        errors.addAll(batch.errors);
        serverTime = batch.serverTime;
      } on MarketUnavailableException catch (error) {
        message = error.message;
        for (final id in securityIds) {
          errors[id] = error.message;
        }
      } on Object {
        message = '报价暂时没赶上，工资还在走。当前显示上次缓存。';
        for (final id in securityIds) {
          errors[id] = '行情请求失败';
        }
      }
    }

    if (fundIds.isNotEmpty) {
      // Fund NAV is end-of-day data: ordinary automatic refreshes keep a
      // 30-minute floor, while an explicit user refresh may retry immediately.
      var shouldFetch = manual;
      if (!shouldFetch) {
        final oldest = await ledger.oldestFundFetchedAt(fundIds);
        shouldFetch = oldest == null ||
            nowUtc.difference(oldest) >= AppConfig.fundRefreshInterval;
      }
      if (shouldFetch) {
        attempted += fundIds.length;
        try {
          final batch = await client.fetchFundNavs(fundIds, nowUtc: nowUtc);
          await ledger.saveFundNavs(batch.navs.values.toList());
          fundCount = batch.navs.length;
          succeeded += batch.navs.length;
          errors.addAll(batch.errors);
          serverTime = batch.serverTime;
        } on MarketUnavailableException catch (error) {
          message ??= error.message;
          for (final id in fundIds) {
            errors[id] = error.message;
          }
        } on Object {
          message ??= '基金净值暂时没赶上，持仓和上次净值还保留着。';
          for (final id in fundIds) {
            errors[id] = '基金净值请求失败';
          }
        }
      }
    }

    final allFailed = attempted > 0 && succeeded == 0 && errors.isNotEmpty;
    if (allFailed) {
      message ??= '报价暂时没赶上，工资还在走。';
    } else if (errors.isNotEmpty && message == null) {
      message = '部分标的没更新：${errors.length} 个，其余照常。';
    }
    return QuoteRefreshOutcome(
      success: !allFailed,
      quoteCount: quoteCount,
      fundCount: fundCount,
      serverTime: serverTime,
      message: message,
      errors: errors,
    );
  }
}
