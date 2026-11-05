/// Onboarding draft lifecycle: persist, validate and commit atomically.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/setup_draft.dart';
import '../ledger/ledger_controller.dart';

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, SetupDraft>(OnboardingController.new);

/// True while the user re-runs onboarding from settings.
final onboardingRedoProvider = StateProvider<bool>((ref) => false);

class OnboardingController extends AsyncNotifier<SetupDraft> {
  Timer? _saveTimer;
  bool _committing = false;

  @override
  Future<SetupDraft> build() async {
    ref.onDispose(() => _saveTimer?.cancel());
    final repository = await ref.watch(ledgerRepositoryProvider.future);
    final calendar = ref.watch(calendarProvider);
    final now = ref.read(clockProvider).nowUtc();
    final row = await repository.loadDraft();
    if (row != null) {
      final draft = SetupDraft.fromJson(row.payload);
      draft.step = row.step.clamp(0, SetupDraft.stepCount - 1);
      return draft;
    }
    final ledger = ref.read(ledgerControllerProvider).value;
    final redo = ref.read(onboardingRedoProvider);
    if (redo && ledger != null && ledger.isConfigured) {
      return SetupDraft.fromLedger(
        ledger,
        _newSessionId(),
        today: calendar.dateOf(now),
        nowUtc: now,
      );
    }
    return SetupDraft.fresh(_newSessionId(), today: calendar.dateOf(now));
  }

  SetupDraft get _draft => state.value ?? SetupDraft.fresh(_newSessionId());

  /// Applies a field change and schedules a debounced draft write.
  void edit(SetupDraft next) {
    state = AsyncData(next);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final draft = state.value;
    if (draft == null) return;
    try {
      final repository = await ref.read(ledgerRepositoryProvider.future);
      await repository.saveDraft(
        setupSessionId: draft.setupSessionId,
        step: draft.step,
        payload: draft.toJson(),
        nowUtc: ref.read(clockProvider).nowUtc(),
      );
    } on Object {
      // A failed draft write keeps the in-memory draft; the next edit retries.
    }
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    await _persist();
  }

  String? currentStepError() => _stepError(_draft);

  /// Advances one step, or commits on the review step.
  /// Returns an error message, or null when the step succeeded.
  Future<String?> next() async {
    final draft = state.value;
    if (draft == null) return '草稿还没准备好，请稍等。';
    final error = _stepError(draft);
    if (error != null) return error;
    if (draft.step >= SetupDraft.stepCount - 1) return commit();
    final updated = draft.copyWith(step: draft.step + 1);
    state = AsyncData(updated);
    await saveNow();
    return null;
  }

  Future<void> back() async {
    final draft = state.value;
    if (draft == null || draft.step == 0) return;
    state = AsyncData(draft.copyWith(step: draft.step - 1));
    await saveNow();
  }

  Future<String?> commit() async {
    if (_committing) return '正在登记，请稍候。';
    final draft = state.value;
    if (draft == null) return '草稿还没准备好，请稍等。';
    final validation = draft.validate();
    if (!validation.isValid) return validation.firstError;
    _committing = true;
    final wasConfigured =
        ref.read(ledgerControllerProvider).value?.isConfigured ?? false;
    if (wasConfigured && !validation.commit!.effectiveDate.isMonday) {
      final effectiveInstant = ref
          .read(calendarProvider)
          .startOfDayUtc(validation.commit!.effectiveDate);
      final existing = ref
          .read(ledgerControllerProvider)
          .value
          ?.salaryVersions
          .any((version) =>
              version.effectiveFromUtc.isAtSameMomentAs(effectiveInstant)) ??
          false;
      if (!existing) {
        _committing = false;
        return '排班切换需要从周一生效，避免一周被两套配置切开。';
      }
    }
    try {
      final ledger = ref.read(ledgerControllerProvider.notifier);
      await ledger.commitSetup(
        validation.commit!,
        draft.setupSessionId,
        replaceExisting: wasConfigured,
      );
      ref.read(onboardingRedoProvider.notifier).state = false;
      return null;
    } on LedgerActionException catch (error) {
      return error.message;
    } on Object catch (error) {
      return '写入失败，草稿已保留。$error';
    } finally {
      _committing = false;
    }
  }

  /// Cancels a redo without touching the working ledger.
  Future<void> cancelRedo() async {
    final draft = state.value;
    if (draft != null) {
      final repository = await ref.read(ledgerRepositoryProvider.future);
      await repository.deleteDraft(draft.setupSessionId);
    }
    ref.read(onboardingRedoProvider.notifier).state = false;
  }

  /// Starts a fresh redo draft from the current configuration.
  void startRedo() {
    ref.read(onboardingRedoProvider.notifier).state = true;
    final ledger = ref.read(ledgerControllerProvider).value;
    final calendar = ref.read(calendarProvider);
    final now = ref.read(clockProvider).nowUtc();
    if (ledger == null || !ledger.isConfigured) return;
    state = AsyncData(
      SetupDraft.fromLedger(
        ledger,
        _newSessionId(),
        today: calendar.dateOf(now),
        nowUtc: now,
      ),
    );
  }

  String? _stepError(SetupDraft draft) {
    final validation = draft.validate();
    return switch (draft.step) {
      0 => null,
      1 => validation.errorFor('salary') ??
          validation.errorFor('salaryEffectiveDate'),
      2 => validation.errorFor('schedule'),
      3 => validation.errorFor('holdings') ?? validation.errorFor('gold'),
      4 => validation.errorFor('housing') ?? validation.errorFor('car'),
      _ => validation.errors.isEmpty ? null : validation.firstError,
    };
  }

  static String _newSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
