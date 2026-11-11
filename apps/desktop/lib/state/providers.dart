import 'dart:async';
import 'dart:io';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_model/ledger_model.dart';
import 'package:ledger_store/ledger_store.dart';
import 'package:market_data/market_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../desktop_preferences.dart';
import 'ledger_controller.dart';

const String desktopAppVersion = '0.1.0';

abstract interface class Clock {
  DateTime nowUtc();
}

final class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

final class FixedClock implements Clock {
  FixedClock(this.instantUtc);
  DateTime instantUtc;
  @override
  DateTime nowUtc() => instantUtc;
  void advance(Duration d) => instantUtc = instantUtc.add(d);
}

final sampleModeProvider = StateProvider<bool>((ref) => false);

final clockProvider = Provider<Clock>((ref) {
  if (ref.watch(sampleModeProvider)) {
    return FixedClock(DateTime.utc(2026, 11, 4, 6, 36));
  }
  return const SystemClock();
});

final calendarProvider = Provider<BusinessCalendar>((ref) {
  FinanceTimeZones.ensureInitialized();
  return BusinessCalendar.forZone(BusinessCalendar.defaultTimezone);
});

final sampleLedgerProvider = Provider<LedgerState>((ref) => buildDemoLedger(
    ref.watch(calendarProvider), DateTime.utc(2026, 11, 4, 6, 36)));

final effectiveLedgerProvider = Provider<AsyncValue<LedgerState>>((ref) {
  if (ref.watch(sampleModeProvider)) {
    return AsyncData<LedgerState>(ref.watch(sampleLedgerProvider));
  }
  return ref.watch(ledgerControllerProvider);
});

/// Local data directory shared by the ledger database and display preferences.
final dataDirectoryProvider = Provider<String>((ref) {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    throw StateError('APPDATA unavailable');
  }
  return '$appData${Platform.pathSeparator}FJOB';
});

final databaseFactoryProvider =
    Provider<DatabaseFactory>((ref) => databaseFactoryFfi);

final databasePathProvider = FutureProvider<String>((ref) async {
  final dir = ref.watch(dataDirectoryProvider);
  await Directory(dir).create(recursive: true);
  return '$dir${Platform.pathSeparator}fjob_ledger.db';
});

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await AppDatabase.open(
    factory: ref.watch(databaseFactoryProvider),
    path: await ref.watch(databasePathProvider.future),
    calendar: ref.watch(calendarProvider),
  );
  ref.onDispose(database.close);
  return database;
});

final ledgerRepositoryProvider = FutureProvider<LedgerRepository>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  return LedgerRepository(database, ref.watch(calendarProvider));
});

final marketClientProvider = Provider<MarketClient>((ref) {
  final calendar = ref.watch(calendarProvider);
  if (AppConfig.gatewayBaseUrl.isEmpty) {
    return EastmoneyMarketClient(calendar: calendar);
  }
  return GatewayMarketClient(
      baseUrl: AppConfig.gatewayBaseUrl, calendar: calendar);
});

final quoteRepositoryProvider = FutureProvider<QuoteRepository>((ref) async {
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return QuoteRepository(
    client: ref.watch(marketClientProvider),
    ledger: ledger,
    calendar: ref.watch(calendarProvider),
  );
});

final dashboardCalculatorProvider =
    Provider<DashboardCalculator>((ref) => DashboardCalculator(ref.watch(calendarProvider)));

final preferencesStoreProvider = Provider<DesktopPreferencesStore>((ref) {
  final store = DesktopPreferencesStore(ref.watch(dataDirectoryProvider));
  ref.onDispose(() => store.flush());
  return store;
});

final preferencesProvider =
    StateProvider<DesktopPreferences>((ref) => DesktopPreferences.defaults());

/// Desktop refreshes once per second; the countdown ceils to whole seconds and
/// amounts are recomputed from the clock, never accumulated per tick.
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final clock = ref.read(clockProvider);
  final controller = StreamController<DateTime>();
  controller.add(clock.nowUtc());
  final timer =
      Timer.periodic(const Duration(seconds: 1), (_) => controller.add(clock.nowUtc()));
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

final dashboardProvider =
    Provider.autoDispose<AsyncValue<DashboardSnapshot>>((ref) {
  final ledgerAsync = ref.watch(effectiveLedgerProvider);
  final calendar = ref.watch(calendarProvider);
  final calculator = ref.watch(dashboardCalculatorProvider);
  final now = ref.watch(tickProvider).value ?? ref.read(clockProvider).nowUtc();
  return switch (ledgerAsync) {
    AsyncData(:final value) => AsyncData(calculator.calculate(value
        .copyWith(quotes: applyQuoteFreshness(value.quotes, now))
        .toCalculationInput(calendar: calendar, nowUtc: now))),
    AsyncError(:final error, :final stackTrace) =>
      AsyncError<DashboardSnapshot>(error, stackTrace),
    _ => const AsyncLoading<DashboardSnapshot>(),
  };
});

enum QuoteStatus { idle, refreshing, ok, failed }

final class QuoteRefreshState {
  const QuoteRefreshState({this.status = QuoteStatus.idle, this.message, this.lastSuccessAt});
  final QuoteStatus status;
  final String? message;
  final DateTime? lastSuccessAt;
}

final quoteStatusProvider =
    StateProvider<QuoteRefreshState>((ref) => const QuoteRefreshState());
