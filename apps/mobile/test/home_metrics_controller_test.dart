/// HOME-DUAL-10: optimistic selection, ordered writes, rollback and the
/// example-mode isolation of the local dashboard preference.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/data/home_metrics_preference_store.dart';
import 'package:todayagain/domain/home_metrics.dart';
import 'package:todayagain/features/dashboard/home_metrics_controller.dart';

final class _FakeStore implements HomeMetricsPreferenceStore {
  _FakeStore({this.value = HomeMetricsMode.both});

  HomeMetricsMode value;
  Object? readError;

  /// When true every write waits for the test to complete its [pending] entry.
  bool manualWrites = false;

  final List<HomeMetricsMode> written = [];
  final List<Completer<void>> pending = [];

  @override
  Future<HomeMetricsMode> read() async {
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<void> write(HomeMetricsMode mode) async {
    written.add(mode);
    if (manualWrites) {
      final completer = Completer<void>();
      pending.add(completer);
      await completer.future;
    }
    value = mode;
  }
}

ProviderContainer _container(_FakeStore store, {bool sample = false}) {
  final container = ProviderContainer(
    overrides: [
      homeMetricsPreferenceStoreProvider.overrideWith((ref) async => store),
      sampleModeProvider.overrideWith((ref) => sample),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('loads the saved mode', () async {
    final store = _FakeStore(value: HomeMetricsMode.time);
    final container = _container(store);
    expect(
      await container.read(homeMetricsModeProvider.future),
      HomeMetricsMode.time,
    );
  });

  test('an unreadable preference falls back to both without blocking', () async {
    final store = _FakeStore()..readError = StateError('broken');
    final container = _container(store);
    expect(
      await container.read(homeMetricsModeProvider.future),
      HomeMetricsMode.both,
    );
  });

  test('selection applies immediately, then persists', () async {
    final store = _FakeStore();
    final container = _container(store);
    await container.read(homeMetricsModeProvider.future);
    final notifier = container.read(homeMetricsModeProvider.notifier);

    final result = notifier.select(HomeMetricsMode.balance);
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.balance,
    );
    expect(await result, isTrue);
    expect(store.value, HomeMetricsMode.balance);
  });

  test('a failed write rolls back to the last saved mode', () async {
    final store = _FakeStore()..manualWrites = true;
    final container = _container(store);
    await container.read(homeMetricsModeProvider.future);
    final notifier = container.read(homeMetricsModeProvider.notifier);

    final result = notifier.select(HomeMetricsMode.time);
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.time,
    );
    await _settle();
    expect(store.pending, hasLength(1));
    store.pending[0].completeError(StateError('disk full'));

    expect(await result, isFalse);
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.both,
    );
    expect(store.value, HomeMetricsMode.both);
  });

  test('a late failure cannot overwrite a newer selection', () async {
    final store = _FakeStore()..manualWrites = true;
    final container = _container(store);
    await container.read(homeMetricsModeProvider.future);
    final notifier = container.read(homeMetricsModeProvider.notifier);

    final first = notifier.select(HomeMetricsMode.time);
    await _settle();
    final second = notifier.select(HomeMetricsMode.balance);
    await _settle();
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.balance,
    );
    expect(store.pending, hasLength(1));

    store.pending[0].completeError(StateError('first failed'));
    await _settle();
    expect(store.pending, hasLength(2));
    store.pending[1].complete();

    expect(await first, isTrue); // superseded, its failure is irrelevant
    expect(await second, isTrue);
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.balance,
    );
    expect(store.value, HomeMetricsMode.balance);
  });

  test('consecutive choices persist in the order the user made them', () async {
    final store = _FakeStore();
    final container = _container(store);
    await container.read(homeMetricsModeProvider.future);
    final notifier = container.read(homeMetricsModeProvider.notifier);

    expect(await notifier.select(HomeMetricsMode.time), isTrue);
    expect(await notifier.select(HomeMetricsMode.balance), isTrue);
    expect(await notifier.select(HomeMetricsMode.time), isTrue);
    expect(store.written, [
      HomeMetricsMode.time,
      HomeMetricsMode.balance,
      HomeMetricsMode.time,
    ]);
    expect(store.value, HomeMetricsMode.time);
  });

  test('example mode starts at both, keeps an in-memory choice and never writes',
      () async {
    final store = _FakeStore(value: HomeMetricsMode.time);
    final container = _container(store, sample: true);
    expect(
      await container.read(homeMetricsModeProvider.future),
      HomeMetricsMode.both,
    );

    final notifier = container.read(homeMetricsModeProvider.notifier);
    expect(await notifier.select(HomeMetricsMode.balance), isTrue);
    expect(
      container.read(homeMetricsModeProvider).value,
      HomeMetricsMode.balance,
    );
    expect(store.written, isEmpty);
    expect(store.value, HomeMetricsMode.time);

    // Leaving example mode restores the real preference; re-entering starts
    // from both again.
    container.read(sampleModeProvider.notifier).state = false;
    expect(
      await container.read(homeMetricsModeProvider.future),
      HomeMetricsMode.time,
    );
    container.read(sampleModeProvider.notifier).state = true;
    expect(
      await container.read(homeMetricsModeProvider.future),
      HomeMetricsMode.both,
    );
  });

  test('selection before the preference finishes loading is ignored', () async {
    final store = _FakeStore();
    final container = _container(store);
    final notifier = container.read(homeMetricsModeProvider.notifier);
    expect(await notifier.select(HomeMetricsMode.balance), isFalse);
    expect(store.written, isEmpty);
  });
}
