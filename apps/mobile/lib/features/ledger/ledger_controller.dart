/// Ledger mutations, quote refresh and widget publishing orchestration.
library;

import 'dart:async';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/ledger_repository.dart';
import '../../domain/ledger.dart';
import '../../domain/setup_draft.dart';

final ledgerControllerProvider =
    AsyncNotifierProvider<LedgerController, LedgerState>(LedgerController.new);

final busyProvider = StateProvider<bool>((ref) => false);

final class LedgerActionException implements Exception {
  const LedgerActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class LedgerController extends AsyncNotifier<LedgerState> {
  bool _refreshingQuotes = false;

  @override
  Future<LedgerState> build() async {
    final repository = await ref.watch(ledgerRepositoryProvider.future);
    final quoteRepository = await ref.watch(quoteRepositoryProvider.future);
    final now = ref.read(clockProvider).nowUtc();
    await quoteRepository.ensureCalendar(nowUtc: now);
    final state = await repository.read(nowUtc: now);
    if (state.isConfigured) {
      // Start after the first frame: the cached ledger is usable immediately.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        unawaited(refreshQuotes());
      });
    }
    return state;
  }

  LedgerState get _current => state.value ?? LedgerState.empty();

  int get _revision => _current.settings.ledgerRevision;

  Future<LedgerRepository> get _repository =>
      ref.read(ledgerRepositoryProvider.future);

  Future<void> _withBusy(Future<void> Function() action) async {
    if (ref.read(busyProvider)) return;
    ref.read(busyProvider.notifier).state = true;
    try {
      await action();
    } finally {
      ref.read(busyProvider.notifier).state = false;
    }
  }

  Future<void> commitSetup(
    SetupCommit commit,
    String setupSessionId, {
    bool replaceExisting = false,
  }) async {
    final repository = await _repository;
    final now = ref.read(clockProvider).nowUtc();
    try {
      final next = await repository.commitSetup(
        commit: commit,
        setupSessionId: setupSessionId,
        nowUtc: now,
        replaceExisting: replaceExisting,
      );
      state = AsyncData(next);
    } on Object catch (error) {
      throw LedgerActionException('配置没有写进去：$error。草稿已保留，可以重试。');
    }
    await refreshQuotes();
  }

  Future<void> updateTheme(ThemeSetting theme) async {
    final repository = await _repository;
    await _commitSettings(() => repository.updateSettings(
          expectedRevision: _revision,
          theme: theme,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
  }

  Future<void> updateMotion(MotionSetting motion) async {
    final repository = await _repository;
    await _commitSettings(() => repository.updateSettings(
          expectedRevision: _revision,
          motion: motion,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
  }

  Future<void> updateTone(AppTone tone) async {
    final repository = await _repository;
    await _commitSettings(() => repository.updateSettings(
          expectedRevision: _revision,
          tone: tone,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
  }

  Future<void> updatePrivacy(bool privacy) async {
    final repository = await _repository;
    await _commitSettings(() => repository.updateSettings(
          expectedRevision: _revision,
          widgetPrivacy: privacy,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
    await publishWidgets();
  }

  Future<void> _commitSettings(Future<LedgerState> Function() action) async {
    try {
      final next = await action();
      state = AsyncData(next);
    } on RevisionConflictException {
      await _reload();
      throw const LedgerActionException('账本刚被其他操作更新，已重新加载。');
    }
    await publishWidgets();
  }

  Future<void> saveCompensation({
    required Rational monthlySalary,
    required WeekTemplate week,
    required LocalDate effectiveFrom,
  }) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.replaceCompensation(
        expectedRevision: _revision,
        monthlySalary: monthlySalary,
        week: week,
        effectiveFrom: effectiveFrom,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> saveHousing({
    required HousingMode mode,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
  }) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.replaceHousing(
        expectedRevision: _revision,
        mode: mode,
        monthlyAmount: monthlyAmount,
        principal: principal,
        effectiveFrom: effectiveFrom,
        billMonth: billMonth,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> saveCar({
    required bool enabled,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
  }) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.replaceCar(
        expectedRevision: _revision,
        enabled: enabled,
        monthlyAmount: monthlyAmount,
        principal: principal,
        effectiveFrom: effectiveFrom,
        billMonth: billMonth,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> upsertHolding({
    required String instrumentId,
    required Rational quantity,
    required Rational costPerUnit,
  }) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.upsertHolding(
        expectedRevision: _revision,
        instrumentId: instrumentId,
        quantity: quantity,
        costPerUnit: costPerUnit,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> deleteHolding(String instrumentId) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.deleteHolding(
        expectedRevision: _revision,
        instrumentId: instrumentId,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> saveBill(MonthlyBill bill) async {
    final repository = await _repository;
    await _mutate(() async {
      final next = await repository.saveBill(
        expectedRevision: _revision,
        bill: bill,
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
      state = AsyncData(next);
    });
    await publishWidgets();
  }

  Future<void> clearLedger() async {
    final repository = await _repository;
    final now = ref.read(clockProvider).nowUtc();
    final next = await repository.clearAll(nowUtc: now);
    state = AsyncData(next);
    final publisher = await ref.read(widgetPublisherProvider.future);
    await publisher.clearWidgets(
      ledgerRevision: next.settings.ledgerRevision,
      nowUtc: now,
    );
  }

  Future<void> refreshQuotes() async {
    if (_refreshingQuotes) return;
    final current = state.value;
    if (current == null || !current.isConfigured) return;
    _refreshingQuotes = true;
    final now = ref.read(clockProvider).nowUtc();
    ref.read(quoteStatusProvider.notifier).state =
        const QuoteRefreshState(status: QuoteStatus.refreshing);
    try {
      final quoteRepository = await ref.read(quoteRepositoryProvider.future);
      final ids = <String>{
        for (final holding in current.holdings)
          if (holding.covers(now)) holding.instrumentId,
      }.toList();
      final outcome = await quoteRepository.refresh(ids, nowUtc: now);
      final repository = await _repository;
      final updated = await repository.read(nowUtc: now);
      state = AsyncData(updated);
      ref.read(quoteStatusProvider.notifier).state = outcome.success
          ? QuoteRefreshState(
              status: QuoteStatus.ok,
              lastSuccessAt: outcome.serverTime,
              message: outcome.errors.isEmpty ? null : '个别标的没更新：${outcome.errors.length} 个',
            )
          : QuoteRefreshState(
              status: QuoteStatus.failed,
              message: outcome.message ?? '报价暂时没赶上，工资还在走。',
              lastSuccessAt: ref.read(quoteStatusProvider).lastSuccessAt,
            );
      if (outcome.success) {
        await publishWidgets();
      }
    } finally {
      _refreshingQuotes = false;
    }
  }

  Future<void> publishWidgets() async {
    final current = state.value;
    if (current == null || !current.isConfigured) return;
    try {
      final publisher = await ref.read(widgetPublisherProvider.future);
      await publisher.publish(
        ledger: current,
        nowUtc: ref.read(clockProvider).nowUtc(),
        privacy: current.settings.widgetPrivacy,
        tone: current.settings.tone,
      );
    } on Object {
      // The job stays queued; the next foreground pass retries.
    }
  }

  Future<void> retryPendingWidgetJobs() async {
    try {
      final publisher = await ref.read(widgetPublisherProvider.future);
      await publisher.flushPending(nowUtc: ref.read(clockProvider).nowUtc());
    } on Object {
      // Ignore: native widget availability is best effort.
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    await _withBusy(() async {
      try {
        await action();
      } on RevisionConflictException {
        await _reload();
        throw const LedgerActionException('账本刚被其他操作更新，已重新加载。');
      }
    });
  }

  Future<void> _reload() async {
    final repository = await _repository;
    state = AsyncData(await repository.read(nowUtc: ref.read(clockProvider).nowUtc()));
  }
}
