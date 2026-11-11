import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

import 'package:todayagain_desktop/widgets/fixed_card_view.dart';
import 'package:todayagain_desktop/widgets/metric_cards.dart';

DashboardSnapshot _demoSnapshot() {
  final calendar = BusinessCalendar.shanghai;
  final now = DateTime.utc(2026, 11, 4, 6, 36);
  final ledger = buildDemoLedger(calendar, now);
  return DashboardCalculator(calendar)
      .calculate(ledger.toCalculationInput(calendar: calendar, nowUtc: now));
}

Widget _wrap(Widget child) => MaterialApp(
      theme: FjobTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('privacy masks the amount on every density', (tester) async {
    final snapshot = _demoSnapshot();
    for (final density in CardDensity.values) {
      await tester.pumpWidget(_wrap(FixedCardView(
        snapshot: snapshot,
        calendar: BusinessCalendar.shanghai,
        tone: AppTone.gentle,
        privacy: true,
        density: density,
      )));
      await tester.pump();
      expect(find.text(privacyMask), findsWidgets,
          reason: 'density $density should mask');
      expect(find.text('−¥55.26'), findsNothing,
          reason: 'density $density must not leak the amount');
    }
  });

  testWidgets('without privacy the real amount is shown', (tester) async {
    await tester.pumpWidget(_wrap(FixedCardView(
      snapshot: _demoSnapshot(),
      calendar: BusinessCalendar.shanghai,
      tone: AppTone.gentle,
      privacy: false,
    )));
    await tester.pump();
    expect(find.text('−¥55.26'), findsOneWidget);
    expect(find.text(privacyMask), findsNothing);
  });

  testWidgets('metrics mode hides the other card', (tester) async {
    await tester.pumpWidget(_wrap(FixedCardView(
      snapshot: _demoSnapshot(),
      calendar: BusinessCalendar.shanghai,
      tone: AppTone.gentle,
      privacy: false,
      metricsMode: 'time',
    )));
    await tester.pump();
    expect(find.text('今日生存结余'), findsNothing);
    expect(find.text('03:24:00'), findsOneWidget);
  });

  testWidgets('time stays the primary core, balance secondary (docs/14)',
      (tester) async {
    final snapshot = _demoSnapshot();
    final calendar = BusinessCalendar.shanghai;
    final time = buildHomeTimeDisplay(snapshot: snapshot, calendar: calendar);
    final balance = buildHomeBalanceDisplay(
        snapshot: snapshot, calendar: calendar, tone: AppTone.gentle);
    Widget card(CardDensity density) => _wrap(FixedCardView(
          snapshot: snapshot,
          calendar: calendar,
          tone: AppTone.gentle,
          privacy: false,
          density: density,
        ));

    // M 便签卡：倒计时 + 迷你计薪进度可见，结余语气句收起、金额保留。
    await tester.pumpWidget(card(CardDensity.m));
    await tester.pump();
    expect(find.text(time.mainValue), findsOneWidget);
    expect(find.textContaining('今日计薪'), findsOneWidget,
        reason: 'M 档恢复迷你计薪进度，强化下班时间主核心');
    expect(find.text(balance.flavorLine), findsNothing,
        reason: '固定窗结余为次核心：语气句只在主窗显示');
    if (balance.completenessNote != null) {
      expect(find.text(balance.completenessNote!), findsNothing,
          reason: 'M 档收起长说明，部分状态由「部分小计」chip 表达');
    }
    expect(find.text(balance.amountText), findsOneWidget);

    // L 工位窗：分项行必须在一屏内可见（无需滚动），语气句收起。
    await tester.pumpWidget(card(CardDensity.l));
    await tester.pump();
    expect(find.text(balance.flavorLine), findsNothing);
    expect(find.text('投资').hitTestable(), findsOneWidget,
        reason: 'L 档工资/投资/支出分项不应被挤出可视区');
  });
}
