/// HOME-DUAL-10: dashboard metric choice with ordered, local-only writes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/home_metrics_preference_store.dart';
import '../../domain/home_metrics.dart';

final homeMetricsPreferenceStoreProvider =
    FutureProvider<HomeMetricsPreferenceStore>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  return SqliteHomeMetricsPreferenceStore(database);
});

final homeMetricsModeProvider =
    AsyncNotifierProvider<HomeMetricsController, HomeMetricsMode>(
  HomeMetricsController.new,
);

/// Keeps the selected layout in memory while a local write completes.
///
/// The example mode uses an isolated in-memory choice that always starts at
/// [HomeMetricsMode.both] and never touches the real preference. In real mode
/// writes are serialized so the database observes the user's last selection,
/// and a late failure can never overwrite a newer choice.
final class HomeMetricsController extends AsyncNotifier<HomeMetricsMode> {
  HomeMetricsMode _lastSaved = HomeMetricsMode.both;
  int _sequence = 0;
  Future<void> _writeChain = Future<void>.value();

  @override
  Future<HomeMetricsMode> build() async {
    _sequence++;
    if (ref.watch(sampleModeProvider)) {
      _lastSaved = HomeMetricsMode.both;
      return HomeMetricsMode.both;
    }
    try {
      final store = await ref.watch(homeMetricsPreferenceStoreProvider.future);
      final mode = await store.read();
      _lastSaved = mode;
      return mode;
    } on Object {
      // A missing or unreadable preference must not block the dashboard.
      _lastSaved = HomeMetricsMode.both;
      return HomeMetricsMode.both;
    }
  }

  /// Applies [mode] immediately, then persists it.
  ///
  /// Returns false only when this was still the newest selection and its write
  /// failed; the visible mode has then been rolled back to the last value that
  /// actually saved.
  Future<bool> select(HomeMetricsMode mode) async {
    if (state.value == null) return false;
    if (state.value == mode) return true;

    final sample = ref.read(sampleModeProvider);
    final sequence = ++_sequence;
    state = AsyncData(mode);

    if (sample) {
      _lastSaved = mode;
      return true;
    }

    try {
      final store = await ref.read(homeMetricsPreferenceStoreProvider.future);
      final write = _writeChain.then<void>((_) => store.write(mode));
      _writeChain = write.then<void>((_) {}, onError: (Object _) {});
      await write;
      if (sequence != _sequence) return true;
      _lastSaved = mode;
      return true;
    } on Object {
      // A later selection owns the outcome; its own write decides the state.
      if (sequence != _sequence) return true;
      state = AsyncData(_lastSaved);
      return false;
    }
  }
}
