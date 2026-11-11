import 'dart:async';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';

import 'providers.dart';

final ledgerControllerProvider =
    AsyncNotifierProvider<LedgerController, LedgerState>(LedgerController.new);

final busyProvider = StateProvider<bool>((ref) => false);

final class LedgerActionException implements Exception {
  const LedgerActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Desktop ledger orchestration: local mutations, quote refresh and .fjob
/// transfer. No native widget bridge; the fixed card consumes the same
/// DashboardSnapshot through the main engine.
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

  Future<void> _mutate(Future<void> Function() action) async {
    if (ref.read(busyProvider)) return;
    ref.read(busyProvider.notifier).state = true;
    try {
      await action();
    } on RevisionConflictException {
      await _reload();
      throw const LedgerActionException('账本刚被其他操作更新，已重新加载。');
    } finally {
      ref.read(busyProvider.notifier).state = false;
    }
  }

  Future<void> commitSetup(SetupCommit commit, String sessionId,
      {bool replaceExisting = false}) async {
    final repository = await _repository;
    final next = await repository.commitSetup(
      commit: commit,
      setupSessionId: sessionId,
      nowUtc: ref.read(clockProvider).nowUtc(),
      replaceExisting: replaceExisting,
    );
    state = AsyncData(next);
    await refreshQuotes();
  }

  Future<void> saveConfiguration(LedgerState configuration) => _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.saveConfiguration(
          configuration: configuration,
          expectedRevision: _revision,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> saveCompensation({
    required Rational monthlySalary,
    required WeekTemplate week,
    WeekAlternation? alternation,
    required LocalDate effectiveFrom,
  }) =>
      _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.replaceCompensation(
          expectedRevision: _revision,
          monthlySalary: monthlySalary,
          week: week,
          alternation: alternation,
          effectiveFrom: effectiveFrom,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> saveHousing({
    required HousingMode mode,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
  }) =>
      _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.replaceHousing(
          expectedRevision: _revision,
          mode: mode,
          monthlyAmount: monthlyAmount,
          principal: principal,
          effectiveFrom: effectiveFrom,
          billMonth: billMonth,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> saveCar({
    required bool enabled,
    required Rational? monthlyAmount,
    required Rational? principal,
    required LocalDate effectiveFrom,
    required LocalDate billMonth,
  }) =>
      _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.replaceCar(
          expectedRevision: _revision,
          enabled: enabled,
          monthlyAmount: monthlyAmount,
          principal: principal,
          effectiveFrom: effectiveFrom,
          billMonth: billMonth,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> updateMotion(MotionSetting motion) => _settings(
      (r, now) => r.updateSettings(
          expectedRevision: _revision, motion: motion, nowUtc: now));

  Future<void> updateTone(AppTone tone) => _settings(
      (r, now) => r.updateSettings(
          expectedRevision: _revision, tone: tone, nowUtc: now));

  Future<void> updatePrivacy(bool privacy) => _settings(
      (r, now) => r.updateSettings(
          expectedRevision: _revision, widgetPrivacy: privacy, nowUtc: now));

  Future<void> _settings(
      Future<LedgerState> Function(LedgerRepository, DateTime) action) async {
    final repository = await _repository;
    try {
      state = AsyncData(
          await action(repository, ref.read(clockProvider).nowUtc()));
    } on RevisionConflictException {
      await _reload();
      throw const LedgerActionException('账本刚被其他操作更新，已重新加载。');
    }
  }

  Future<void> upsertHolding({
    required String instrumentId,
    required Rational quantity,
    required Rational costPerUnit,
    String? name,
    bool pendingQuote = false,
    String? previousInstrumentId,
  }) =>
      _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.upsertHolding(
          expectedRevision: _revision,
          instrumentId: instrumentId,
          quantity: quantity,
          costPerUnit: costPerUnit,
          name: name,
          pendingQuote: pendingQuote,
          previousInstrumentId: previousInstrumentId,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> deleteHolding(String instrumentId) => _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.deleteHolding(
          expectedRevision: _revision,
          instrumentId: instrumentId,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> saveBill(MonthlyBill bill) => _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.saveBill(
          expectedRevision: _revision,
          bill: bill,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<LedgerBundle> exportBundle() async {
    final repository = await _repository;
    return repository.exportBundle(
      exportedAt: ref.read(clockProvider).nowUtc(),
      appVersion: desktopAppVersion,
      platform: 'windows',
    );
  }

  Future<void> importBundle(LedgerBundle bundle,
          {required LedgerImportMode mode}) =>
      _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.importBundle(
          bundle,
          expectedRevision: _revision,
          mode: mode,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
        await refreshQuotes();
      });

  Future<List<LedgerBackup>> listBackups() async =>
      (await _repository).listBackups();

  Future<void> restoreBackup(int backupId) => _mutate(() async {
        final repository = await _repository;
        state = AsyncData(await repository.restoreBackup(
          backupId,
          expectedRevision: _revision,
          nowUtc: ref.read(clockProvider).nowUtc(),
        ));
      });

  Future<void> clearLedger() async {
    final repository = await _repository;
    state = AsyncData(
        await repository.clearAll(nowUtc: ref.read(clockProvider).nowUtc()));
  }

  Future<void> refreshQuotes({bool manual = false}) async {
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
      final outcome =
          await quoteRepository.refresh(ids, nowUtc: now, manual: manual);
      final repository = await _repository;
      state = AsyncData(await repository.read(nowUtc: now));
      ref.read(quoteStatusProvider.notifier).state = outcome.success
          ? QuoteRefreshState(
              status: QuoteStatus.ok,
              lastSuccessAt: outcome.serverTime,
              message: outcome.errors.isEmpty
                  ? null
                  : '个别标的没更新：${outcome.errors.length} 个',
            )
          : QuoteRefreshState(
              status: QuoteStatus.failed,
              message: outcome.message ?? '报价暂时没赶上，工资还在走。',
              lastSuccessAt: ref.read(quoteStatusProvider).lastSuccessAt,
            );
    } finally {
      _refreshingQuotes = false;
    }
  }

  Future<void> _reload() async {
    final repository = await _repository;
    state = AsyncData(
        await repository.read(nowUtc: ref.read(clockProvider).nowUtc()));
  }
}
