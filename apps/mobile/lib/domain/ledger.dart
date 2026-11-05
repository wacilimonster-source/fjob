/// App-level domain models layered on top of `finance_core`.
library;

import 'package:finance_core/finance_core.dart';

enum ThemeSetting { system, light, dark }

enum MotionSetting { full, reduced }

enum AppTone { gentle, harsh }

final class AppSettings {
  const AppSettings({
    this.ledgerRevision = 0,
    this.salaryTimezone = 'Asia/Shanghai',
    this.theme = ThemeSetting.system,
    this.motion = MotionSetting.full,
    this.tone = AppTone.gentle,
    this.widgetPrivacy = false,
    this.onboardingCompletedAt,
    this.sampleMode = false,
  });

  final int ledgerRevision;
  final String salaryTimezone;
  final ThemeSetting theme;
  final MotionSetting motion;
  final AppTone tone;
  final bool widgetPrivacy;
  final DateTime? onboardingCompletedAt;

  /// Example mode uses an isolated in-memory ledger and a fixed demo clock.
  final bool sampleMode;

  bool get hasCompletedOnboarding => onboardingCompletedAt != null;

  AppSettings copyWith({
    int? ledgerRevision,
    String? salaryTimezone,
    ThemeSetting? theme,
    MotionSetting? motion,
    AppTone? tone,
    bool? widgetPrivacy,
    DateTime? onboardingCompletedAt,
    bool? sampleMode,
  }) =>
      AppSettings(
        ledgerRevision: ledgerRevision ?? this.ledgerRevision,
        salaryTimezone: salaryTimezone ?? this.salaryTimezone,
        theme: theme ?? this.theme,
        motion: motion ?? this.motion,
        tone: tone ?? this.tone,
        widgetPrivacy: widgetPrivacy ?? this.widgetPrivacy,
        onboardingCompletedAt:
            onboardingCompletedAt ?? this.onboardingCompletedAt,
        sampleMode: sampleMode ?? this.sampleMode,
      );
}

/// The full local ledger: settings plus every versioned configuration row.
final class LedgerState {
  const LedgerState({
    required this.settings,
    required this.salaryVersions,
    required this.schedules,
    required this.overrides,
    required this.holdings,
    required this.housingVersions,
    required this.carVersions,
    required this.bills,
    required this.quotes,
    required this.marketCalendar,
    this.instrumentNames = const <String, String>{},
    this.goldReferenceSessionActive = false,
  });

  factory LedgerState.empty() => const LedgerState(
        settings: AppSettings(),
        salaryVersions: [],
        schedules: {},
        overrides: [],
        holdings: [],
        housingVersions: [],
        carVersions: [],
        bills: [],
        quotes: {},
        marketCalendar: MarketCalendar({}),
      );

  final AppSettings settings;
  final List<SalaryVersion> salaryVersions;
  final Map<String, ScheduleVersion> schedules;
  final List<ScheduleOverride> overrides;
  final List<Holding> holdings;
  final List<HousingVersion> housingVersions;
  final List<CarVersion> carVersions;
  final List<MonthlyBill> bills;
  final Map<String, Quote> quotes;
  final MarketCalendar marketCalendar;

  /// Display names cached from the instrument directory, keyed by id.
  final Map<String, String> instrumentNames;
  final bool goldReferenceSessionActive;

  bool get isConfigured =>
      settings.hasCompletedOnboarding &&
      salaryVersions.isNotEmpty &&
      schedules.isNotEmpty;

  LedgerState copyWith({
    AppSettings? settings,
    List<SalaryVersion>? salaryVersions,
    Map<String, ScheduleVersion>? schedules,
    List<ScheduleOverride>? overrides,
    List<Holding>? holdings,
    List<HousingVersion>? housingVersions,
    List<CarVersion>? carVersions,
    List<MonthlyBill>? bills,
    Map<String, Quote>? quotes,
    MarketCalendar? marketCalendar,
    Map<String, String>? instrumentNames,
    bool? goldReferenceSessionActive,
  }) =>
      LedgerState(
        settings: settings ?? this.settings,
        salaryVersions: salaryVersions ?? this.salaryVersions,
        schedules: schedules ?? this.schedules,
        overrides: overrides ?? this.overrides,
        holdings: holdings ?? this.holdings,
        housingVersions: housingVersions ?? this.housingVersions,
        carVersions: carVersions ?? this.carVersions,
        bills: bills ?? this.bills,
        quotes: quotes ?? this.quotes,
        marketCalendar: marketCalendar ?? this.marketCalendar,
        instrumentNames: instrumentNames ?? this.instrumentNames,
        goldReferenceSessionActive:
            goldReferenceSessionActive ?? this.goldReferenceSessionActive,
      );

  CalculationInput toCalculationInput({
    required BusinessCalendar calendar,
    required DateTime nowUtc,
  }) =>
      CalculationInput(
        nowUtc: nowUtc,
        ledgerRevision: settings.ledgerRevision,
        calendar: calendar,
        salaryVersions: salaryVersions,
        schedules: schedules,
        overrides: overrides,
        holdings: holdings,
        quotes: quotes,
        marketCalendar: marketCalendar,
        housingVersions: housingVersions,
        carVersions: carVersions,
        bills: bills,
        goldReferenceSessionActive: goldReferenceSessionActive,
      );

  /// Currently effective housing mode, or none.
  HousingMode get housingMode {
    HousingVersion? active;
    for (final version in housingVersions) {
      if (version.mode == HousingMode.none) continue;
      active = version;
    }
    return active?.mode ?? HousingMode.none;
  }

  SalaryVersion? get currentSalary {
    SalaryVersion? latest;
    for (final version in salaryVersions) {
      if (latest == null ||
          version.effectiveFromUtc.isAfter(latest.effectiveFromUtc)) {
        latest = version;
      }
    }
    return latest;
  }
}

/// One onboarding draft row, including invalid raw text.
final class OnboardingDraftRow {
  const OnboardingDraftRow({
    required this.setupSessionId,
    required this.draftVersion,
    required this.step,
    required this.payload,
    required this.updatedAt,
  });

  final String setupSessionId;
  final int draftVersion;
  final int step;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
}

/// Serialization helpers shared by the database and the widget snapshot.
abstract final class LedgerJson {
  static String? dateToIso(DateTime? value) =>
      value?.toUtc().toIso8601String();

  static DateTime? dateFromIso(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value).toUtc() : null;

  static String? moneyToJson(Rational? value) => value?.toCanonicalString();

  static Rational? moneyFromJson(Object? value) =>
      value is String && value.isNotEmpty ? Rational.parse(value) : null;

  static int asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool asBool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
  }

  static String asString(Object? value, {String fallback = ''}) =>
      value is String ? value : fallback;

  static List<Map<String, dynamic>> asMapList(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList();
    }
    return const <Map<String, dynamic>>[];
  }
}
