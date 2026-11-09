/// Builds the versioned widget payload shared with Kotlin and Swift.
///
/// The JSON shape is fixed by `contracts/widget-snapshot.schema.json`; native
/// code only renders these pre-computed entries and never re-implements a
/// domain calculation.
library;

import 'package:finance_core/finance_core.dart';

import '../domain/ledger.dart';

abstract final class WidgetCaps {
  /// Dart emits v2; the native side still accepts and renders v1 snapshots.
  static const int schemaVersion = 2;
  static const int maxEntries = 289;
  static const int stepMinutes = 5;
  static const int horizonHours = 24;
}

abstract final class WidgetSnapshotBuilder {
  static Map<String, dynamic> entry({
    required DashboardSnapshot snapshot,
    required bool privacy,
    required String timezone,
    required AppTone tone,
    DateTime? createdAt,
  }) {
    final fundDates = snapshot.assets.positions
        .where((position) => position.kind == InstrumentKind.fund)
        .map((position) => position.fundNav?.navDate)
        .whereType<LocalDate>()
        .map((date) => date.toIsoString())
        .toSet();
    final fundNavDate = fundDates.length == 1 ? fundDates.single : null;
    final amounts = <String, String?>{
      'total': _amount(snapshot.total, privacy),
      'wage': _amount(snapshot.wage, privacy),
      'stockDaily': _amount(snapshot.stockDaily, privacy),
      'goldDaily': _amount(snapshot.goldDaily, privacy),
      'stockFundDaily': _amount(snapshot.stockFundDaily, privacy),
      'housing': _amount(snapshot.housing, privacy),
      'car': _amount(snapshot.car, privacy),
      'principal': _amount(snapshot.principal, privacy),
      'interest': _amount(snapshot.interest, privacy),
      'rent': _amount(snapshot.rent, privacy),
    };
    return <String, dynamic>{
      'schemaVersion': WidgetCaps.schemaVersion,
      'ledgerRevision': snapshot.ledgerRevision,
      'createdAt': (createdAt ?? snapshot.computedAtUtc).toUtc().toIso8601String(),
      'computedAt': snapshot.computedAtUtc.toUtc().toIso8601String(),
      'quotesAsOf': snapshot.quotesAsOf?.toUtc().toIso8601String(),
      'validUntil': snapshot.computedAtUtc
          .add(const Duration(minutes: 30))
          .toUtc()
          .toIso8601String(),
      'timezone': timezone,
      'privacy': privacy,
      'tombstone': false,
      'completeness': snapshot.completeness.name,
      'quoteQuality': snapshot.quoteQuality.name,
      'amounts': amounts,
      'fundNavDate': fundNavDate,
      'housingMode': snapshot.housingDetail.housingMode?.name ?? 'none',
      'scene': sceneFor(snapshot),
      // WSC-01：房/车可见性跟随配置状态，原生据此选择静态图；
      // 金额为0与未配置是两种状态，不通过金额正负推断。
      'showHousing': snapshot.housingDetail.configured,
      'showCar': snapshot.carDetail.configured,
      'caption': captionFor(snapshot, privacy: privacy, tone: tone),
      'deepLink': 'fjob://dashboard',
    };
  }

  static String sceneFor(DashboardSnapshot snapshot) {
    if (snapshot.completeness == Completeness.unavailable) return 'unknown';
    return switch (snapshot.phase) {
      DayPhase.working => 'working',
      DayPhase.breakTime => 'break',
      DayPhase.restDay => 'restDay',
      DayPhase.beforeShift || DayPhase.afterShift => 'offDuty',
      DayPhase.unknown => 'unknown',
    };
  }

  static String captionFor(
    DashboardSnapshot snapshot, {
    required bool privacy,
    required AppTone tone,
  }) {
    if (privacy) return '金额已隐藏，只让表情替你说话。';
    if (snapshot.completeness == Completeness.unavailable) {
      return '账本还没配好，打开 App 看一眼。';
    }
    if (snapshot.completeness == Completeness.partial) {
      return '投资待更新，当前合计不完整。';
    }
    final total = snapshot.total;
    final harsh = tone == AppTone.harsh;
    if (snapshot.phase == DayPhase.restDay) {
      return harsh ? '你休息了，账单觉得你想多了。' : '今天不上班，生活照常扣费。';
    }
    if (total == null) return '数字还在路上，先喘口气。';
    if (total.isNegative) {
      return harsh ? '辛苦一天，成功把亏损补小了一点。' : '工资正在努力追赶上午的亏损。';
    }
    return harsh ? '难得赢一局，房贷已经在候场。' : '今天暂时领先，先小声开心一下。';
  }

  static Map<String, dynamic> timeline({
    required LedgerState ledger,
    required BusinessCalendar calendar,
    required DashboardCalculator calculator,
    required DateTime nowUtc,
    required bool privacy,
    required AppTone tone,
    int stepMinutes = WidgetCaps.stepMinutes,
    int horizonHours = WidgetCaps.horizonHours,
  }) {
    final entries = <Map<String, dynamic>>[];
    final totalMinutes = horizonHours * 60;
    for (var offset = 0; offset <= totalMinutes; offset += stepMinutes) {
      if (entries.length >= WidgetCaps.maxEntries) break;
      final instant = nowUtc.toUtc().add(Duration(minutes: offset));
      final snapshot = calculator.calculate(
        ledger.toCalculationInput(calendar: calendar, nowUtc: instant),
      );
      entries.add(
        entry(
          snapshot: snapshot,
          privacy: privacy,
          timezone: calendar.timezoneName,
          tone: tone,
          createdAt: nowUtc,
        ),
      );
    }
    return <String, dynamic>{
      'timelineVersion': 1,
      'ledgerRevision': ledger.settings.ledgerRevision,
      'entries': entries,
    };
  }

  static Map<String, dynamic> tombstone({
    required int ledgerRevision,
    required DateTime nowUtc,
    required String timezone,
  }) {
    final stamp = nowUtc.toUtc().toIso8601String();
    return <String, dynamic>{
      'timelineVersion': 1,
      'ledgerRevision': ledgerRevision,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'schemaVersion': WidgetCaps.schemaVersion,
          'ledgerRevision': ledgerRevision,
          'createdAt': stamp,
          'computedAt': stamp,
          'quotesAsOf': null,
          'validUntil': nowUtc
              .toUtc()
              .add(const Duration(hours: 24))
              .toIso8601String(),
          'timezone': timezone,
          'privacy': true,
          'tombstone': true,
          'completeness': 'unavailable',
          'quoteQuality': 'unavailable',
          'amounts': <String, String?>{
            'total': null,
            'wage': null,
            'stockDaily': null,
            'goldDaily': null,
            'stockFundDaily': null,
            'housing': null,
            'car': null,
            'principal': null,
            'interest': null,
            'rent': null,
          },
          'fundNavDate': null,
          'housingMode': 'none',
          'scene': 'unknown',
          'caption': '账本已清空，打开 App 重新登记。',
          'deepLink': 'fjob://dashboard',
        },
      ],
    };
  }

  static String? _amount(Rational? value, bool privacy) =>
      privacy || value == null ? null : value.toFixed(2);
}
