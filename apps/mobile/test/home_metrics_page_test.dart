/// M8-HOME page-level acceptance: first-screen visibility, the three display
/// modes, hidden-card semantics, large text and write-failure rollback.
library;

import 'dart:ui' show CheckedState;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/clock.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/app/theme.dart';
import 'package:todayagain/data/home_metrics_preference_store.dart';
import 'package:todayagain/domain/demo_ledger.dart';
import 'package:todayagain/domain/home_metrics.dart';
import 'package:todayagain/domain/ledger.dart';
import 'package:todayagain/features/dashboard/dashboard_page.dart';
import 'package:todayagain/features/dashboard/home_metrics_controller.dart';

DateTime _shanghai(int day, int hour, int minute, [int second = 0]) =>
    DateTime.utc(2026, 11, day, hour - 8, minute, second);

final _wednesday = _shanghai(4, 14, 36);

final class _FailingStore implements HomeMetricsPreferenceStore {
  HomeMetricsMode value = HomeMetricsMode.both;

  @override
  Future<HomeMetricsMode> read() async => value;

  @override
  Future<void> write(HomeMetricsMode mode) async {
    throw StateError('disk full');
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FixedClock clock,
  double textScale = 1.0,
  Size logicalSize = const Size(380, 640),
  bool sample = true,
  LedgerState? ledger,
  HomeMetricsPreferenceStore? store,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize =
      Size(logicalSize.width * 2, logicalSize.height * 2);
  tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.reset();
  });

  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: ProviderScope(
        overrides: [
          sampleModeProvider.overrideWith((ref) => sample),
          clockProvider.overrideWithValue(clock),
          widgetTimelineEnabledProvider.overrideWithValue(false),
          deepLinksEnabledProvider.overrideWithValue(false),
          if (ledger != null)
            effectiveLedgerProvider.overrideWith((ref) => AsyncData(ledger)),
          if (store != null)
            homeMetricsPreferenceStoreProvider
                .overrideWith((ref) async => store),
        ],
        child: MaterialApp(
          theme: FjobTheme.light(),
          home: const Scaffold(
            body: SafeArea(child: DashboardPage()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 20));
}

Finder get _countdown => find.byKey(const Key('home-countdown'));
Finder get _balance => find.byKey(const Key('home-balance-amount'));

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('首页显示'));
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 40));
}

void main() {
  testWidgets('320 × 640 shows both labels and main values without scrolling',
      (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_wednesday),
      logicalSize: const Size(320, 640),
    );

    expect(find.text('距离下班还有'), findsOneWidget);
    expect(find.text('今日生存结余'), findsOneWidget);
    expect(_countdown, findsOneWidget);
    expect(_balance, findsOneWidget);

    final viewport = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    expect(tester.getRect(find.text('距离下班还有')).bottom,
        lessThanOrEqualTo(viewport));
    expect(tester.getRect(_countdown).bottom, lessThanOrEqualTo(viewport));
    expect(tester.getRect(find.text('今日生存结余')).bottom,
        lessThanOrEqualTo(viewport));
    expect(tester.getRect(_balance).bottom, lessThanOrEqualTo(viewport));
    // Time first, balance second.
    expect(
      tester.getTopLeft(_countdown).dy,
      lessThan(tester.getTopLeft(_balance).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页显示 offers three exclusive options and switches the cards',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pumpDashboard(tester, clock: FixedClock(_wednesday));
      expect(_countdown, findsOneWidget);
      expect(_balance, findsOneWidget);

      await _openSettings(tester);
      expect(find.text('首页想看什么？'), findsOneWidget);
      expect(find.text('都显示'), findsOneWidget);
      expect(find.text('只看下班'), findsOneWidget);
      expect(find.text('只看结余'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('都显示')).flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );

      await _select(tester, '只看下班');
      expect(find.text('首页想看什么？'), findsOneWidget); // panel stays open
      expect(find.text('首页显示'), findsOneWidget);
      expect(_countdown, findsOneWidget);
      expect(_balance, findsNothing);
      expect(find.text('今日生存结余'), findsNothing);
      expect(find.textContaining('今日计薪'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('只看下班')).flagsCollection
            .isChecked,
        CheckedState.isTrue,
      );

      await _select(tester, '只看结余');
      expect(_countdown, findsNothing);
      expect(find.text('距离下班还有'), findsNothing);
      expect(find.textContaining('今日计薪'), findsNothing);
      expect(_balance, findsOneWidget);
      expect(find.text('今日生存结余'), findsOneWidget);

      await _select(tester, '都显示');
      expect(_countdown, findsOneWidget);
      expect(_balance, findsOneWidget);

      await tester.tap(find.text('首页显示'));
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('首页想看什么？'), findsNothing);
      expect(_countdown, findsOneWidget);
      expect(_balance, findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('a hidden metric is removed from the semantics tree',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _pumpDashboard(tester, clock: FixedClock(_wednesday));
      await _openSettings(tester);
      await _select(tester, '只看下班');

      expect(find.bySemanticsLabel(RegExp(r'^距离下班还有')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^今日生存结余')), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('320 dp + 200% font has no overflow and stays scrollable',
      (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_wednesday),
      textScale: 2,
      logicalSize: const Size(320, 640),
    );

    expect(_countdown, findsOneWidget);
    expect(_balance, findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);

    await _openSettings(tester);
    expect(find.text('首页想看什么？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('before shift and lunch states are wired to the time card',
      (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_shanghai(4, 8, 45)),
    );
    expect(find.text('00:15:00'), findsOneWidget);
    expect(find.text('09:00 上班 · 预计 18:00 下班'), findsOneWidget);
    expect(find.text('未开始'), findsOneWidget);

    await _pumpDashboard(
      tester,
      clock: FixedClock(_shanghai(4, 12, 30)),
    );
    expect(find.text('05:30:00'), findsOneWidget);
    expect(find.textContaining('休息中，工资暂停'), findsOneWidget);
    expect(find.text('今日计薪 3.0 / 8.0 小时'), findsOneWidget);
  });

  testWidgets('18:00 exactly is 已下班, never 00:00:00', (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_shanghai(4, 18, 0)),
    );
    expect(find.text('已下班'), findsWidgets);
    expect(find.text('00:00:00'), findsNothing);
    expect(find.textContaining('18:00 已下班'), findsOneWidget);
  });

  testWidgets('a rest day hides the progress bar', (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_shanghai(7, 12, 0)),
    );
    expect(find.text('今日休息'), findsOneWidget);
    expect(find.text('休息日'), findsOneWidget);
    expect(find.textContaining('今日计薪'), findsNothing);
  });

  testWidgets('an unconfigured schedule is 排班待确认', (tester) async {
    await _pumpDashboard(
      tester,
      clock: FixedClock(_wednesday),
      ledger: LedgerState.empty(),
    );
    expect(
      tester.widget<Text>(_countdown).data,
      '排班待确认',
    );
    expect(find.text('排班待确认'), findsWidgets); // card value and pat button
    expect(find.textContaining('工资与排班'), findsOneWidget);
    expect(find.textContaining('今日计薪'), findsNothing);
  });

  testWidgets('a failed preference write rolls back and shows the retry hint',
      (tester) async {
    final ledger = buildDemoLedger(BusinessCalendar.shanghai, _wednesday);
    await _pumpDashboard(
      tester,
      clock: FixedClock(_wednesday),
      sample: false,
      ledger: ledger,
      store: _FailingStore(),
    );

    await _openSettings(tester);
    await _select(tester, '只看下班');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('显示设置没存上，请重试'), findsOneWidget);
    // Rolled back to the last saved mode (both).
    expect(_countdown, findsOneWidget);
    expect(_balance, findsOneWidget);
    expect(find.text('首页想看什么？'), findsOneWidget);
  });
}
