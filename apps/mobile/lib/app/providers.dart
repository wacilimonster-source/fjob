/// Application dependency graph.
library;

import 'dart:async';

import 'package:finance_core/finance_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/ledger_repository.dart';
import '../data/market_client.dart';
import '../data/quote_repository.dart';
import '../data/widget_bridge.dart';
import '../domain/demo_ledger.dart';
import '../domain/ledger.dart';
import '../features/ledger/ledger_controller.dart';
import 'clock.dart';

/// The example mode uses an isolated in-memory ledger and a fixed clock; it
/// never writes to the real ledger.
final sampleModeProvider = StateProvider<bool>((ref) => false);

final clockProvider = Provider<Clock>((ref) {
  if (ref.watch(sampleModeProvider)) {
    return FixedClock(DateTime.utc(2026, 11, 4, 6, 36));
  }
  return const SystemClock();
});

final sampleLedgerProvider = Provider<LedgerState>((ref) {
  return buildDemoLedger(
    ref.watch(calendarProvider),
    DateTime.utc(2026, 11, 4, 6, 36),
  );
});

/// Ledger consumed by every read-only view.
final effectiveLedgerProvider = Provider<AsyncValue<LedgerState>>((ref) {
  if (ref.watch(sampleModeProvider)) {
    return AsyncData<LedgerState>(ref.watch(sampleLedgerProvider));
  }
  return ref.watch(ledgerControllerProvider);
});

final calendarProvider = Provider<BusinessCalendar>((ref) {
  FinanceTimeZones.ensureInitialized();
  return BusinessCalendar.forZone(BusinessCalendar.defaultTimezone);
});

/// Mobile uses the sqflite platform implementation; tests override the factory.
final databaseFactoryProvider = Provider<DatabaseFactory>((ref) => databaseFactory);

final databasePathProvider = FutureProvider<String>((ref) async {
  final directory = await getApplicationSupportDirectory();
  return '${directory.path}/fjob_ledger.db';
});

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final factory = ref.watch(databaseFactoryProvider);
  final path = await ref.watch(databasePathProvider.future);
  final database = await AppDatabase.open(
    factory: factory,
    path: path,
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
    return FixtureMarketClient(calendar);
  }
  return GatewayMarketClient(
    baseUrl: AppConfig.gatewayBaseUrl,
    calendar: calendar,
  );
});

final quoteRepositoryProvider = FutureProvider<QuoteRepository>((ref) async {
  final ledger = await ref.watch(ledgerRepositoryProvider.future);
  return QuoteRepository(
    client: ref.watch(marketClientProvider),
    ledger: ledger,
    calendar: ref.watch(calendarProvider),
  );
});

final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => const MethodChannelWidgetBridge(),
);

/// Tests and previews turn this off to skip the 289-entry timeline build.
final widgetTimelineEnabledProvider = Provider<bool>((ref) => true);

/// Test hosts have no platform channel for incoming deep links.
final deepLinksEnabledProvider = Provider<bool>((ref) => true);

final dashboardCalculatorProvider = Provider<DashboardCalculator>((ref) {
  return DashboardCalculator(ref.watch(calendarProvider));
});

final widgetPublisherProvider = FutureProvider<WidgetPublisher>((ref) async {
  final repository = await ref.watch(ledgerRepositoryProvider.future);
  return WidgetPublisher(
    ledgerRepository: repository,
    calendar: ref.watch(calendarProvider),
    calculator: ref.watch(dashboardCalculatorProvider),
    bridge: ref.watch(widgetBridgeProvider),
    timelineEnabled: ref.watch(widgetTimelineEnabledProvider),
  );
});

/// False while the app is in the background; suspends the 250ms UI tick.
final appVisibleProvider = StateProvider<bool>((ref) => true);

/// UI clock: about four recomputations per second while visible.
final tickProvider = StreamProvider.autoDispose<DateTime>((ref) {
  final visible = ref.watch(appVisibleProvider);
  final clock = ref.read(clockProvider);
  if (!visible) return Stream<DateTime>.value(clock.nowUtc());
  final controller = StreamController<DateTime>();
  void emit() => controller.add(clock.nowUtc());
  emit();
  final timer = Timer.periodic(const Duration(milliseconds: 250), (_) => emit());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

final dashboardProvider = Provider.autoDispose<AsyncValue<DashboardSnapshot>>((ref) {
  final ledgerAsync = ref.watch(effectiveLedgerProvider);
  final calendar = ref.watch(calendarProvider);
  final calculator = ref.watch(dashboardCalculatorProvider);
  final tick = ref.watch(tickProvider);
  final now = tick.value ?? ref.read(clockProvider).nowUtc();

  return switch (ledgerAsync) {
    AsyncData(:final value) => AsyncData(
        calculator.calculate(
          value
              .copyWith(
                quotes: applyQuoteFreshness(value.quotes, now),
              )
              .toCalculationInput(calendar: calendar, nowUtc: now),
        ),
      ),
    AsyncError(:final error, :final stackTrace) =>
      AsyncError<DashboardSnapshot>(error, stackTrace),
    _ => const AsyncLoading<DashboardSnapshot>(),
  };
});

/// Quote refresh status, kept separate so the dashboard never blanks out.
enum QuoteStatus { idle, refreshing, ok, failed }

final class QuoteRefreshState {
  const QuoteRefreshState({
    this.status = QuoteStatus.idle,
    this.message,
    this.lastSuccessAt,
  });

  final QuoteStatus status;
  final String? message;
  final DateTime? lastSuccessAt;

  QuoteRefreshState copyWith({
    QuoteStatus? status,
    String? message,
    DateTime? lastSuccessAt,
  }) =>
      QuoteRefreshState(
        status: status ?? this.status,
        message: message ?? this.message,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      );
}

final quoteStatusProvider =
    StateProvider<QuoteRefreshState>((ref) => const QuoteRefreshState());
