/// SCN-05: 首页场景的页面级验收——按钮状态、反馈区、生命周期与金额不变性。
///
/// 全部用示例账本（隔离内存态）与可推进的 FixedClock，不等待真实时间，
/// 不触数据库与网络。动画计时遵循测试帧锚定规则：动画启动后的第一帧不
/// 推进时长，因此每个起点后先 pump() 锚定，再按毫秒推进。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todayagain/app/app.dart';
import 'package:todayagain/app/clock.dart';
import 'package:todayagain/app/providers.dart';
import 'package:todayagain/app/theme.dart';
import 'package:todayagain/features/dashboard/dashboard_page.dart';

DateTime _shanghai(int day, int hour, int minute, [int second = 0, int ms = 0]) =>
    DateTime.utc(2026, 11, day, hour - 8, minute, second, ms);

final _wednesday = _shanghai(4, 14, 36);

/// tickProvider 每 250ms 发一次；推 Clock 后至少 pump 这么久才会重算。
const _tick = Duration(milliseconds: 300);

/// reconcile 在 post-frame 生效，标签/按钮更新要再补一帧才能被 finder 看到。
const _settle = Duration(milliseconds: 20);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FixedClock clock,
  double textScale = 1.0,
  bool disableAnimations = false,
  bool fullShell = false,
  Size logicalSize = const Size(380, 640),
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize =
      Size(logicalSize.width * 2, logicalSize.height * 2);
  tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.view.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: disableAnimations);
  addTearDown(() {
    tester.view.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.platformDispatcher.clearAccessibilityFeaturesTestValue();
    tester.view.reset();
  });

  final child = fullShell
      ? const FjobApp()
      : MaterialApp(
          theme: FjobTheme.light(),
          home: Scaffold(
            body: SafeArea(child: DashboardPage()),
          ),
        );
  // UniqueKey 强制每次用例重建容器，避免 ProviderScope 复用旧 overrides。
  await tester.pumpWidget(
    KeyedSubtree(
      key: UniqueKey(),
      child: ProviderScope(
        overrides: [
          sampleModeProvider.overrideWith((ref) => true),
          clockProvider.overrideWithValue(clock),
          deepLinksEnabledProvider.overrideWithValue(false),
          widgetTimelineEnabledProvider.overrideWithValue(false),
        ],
        child: child,
      ),
    ),
  );
  // 首帧 + post-frame reconcile。
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(_settle);
}

Text? _moneyText(WidgetTester tester) {
  final candidates = tester.widgetList<Text>(
    find.byWidgetPredicate(
      (widget) => widget is Text && widget.style?.fontSize == 42,
    ),
  );
  return candidates.isEmpty ? null : candidates.first;
}

Future<void> _finishPat(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 3200));
  await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
  await tester.pump(_settle);
}

/// ensureSemantics 的句柄必须在用例体内释放，统一在此包装。
void sceneTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

void main() {
  group('拍拍按钮状态矩阵（3.1）', () {
    sceneTest('working：按钮可用并完成一次 3.2 秒回应', (tester) async {
      final clock = FixedClock(_wednesday);
      await _pumpDashboard(tester, clock: clock);

      final button = find.widgetWithText(TextButton, '拍拍他');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('收到啦'), findsOneWidget);
      expect(find.text('他抬头看了你一眼。'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('他缓过来一点了'), findsOneWidget);
      // PAT-05：语气温柔、工作第一条。
      expect(find.text('辛苦了。你又不是打印机。'), findsOneWidget);

      await _finishPat(tester);
      expect(find.text('拍拍他'), findsOneWidget);
    });

    sceneTest('20 次连点只接受一次，结束后可再拍并取下一句（PAT-T05/T06）',
        (tester) async {
      final clock = FixedClock(_wednesday);
      await _pumpDashboard(tester, clock: clock);

      final button = find.widgetWithText(TextButton, '拍拍他');
      final center = tester.getCenter(button);
      await tester.tap(button);
      for (var index = 0; index < 19; index++) {
        // 连点同一位置；按钮禁用后 finder 已不再匹配，位置点击才符合真实连点。
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('辛苦了。你又不是打印机。'), findsOneWidget);

      await _finishPat(tester);
      await tester.tap(button);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('收到，肩膀先放下来一点。'), findsOneWidget);
      await _finishPat(tester);
    });

    sceneTest('afterShift 冷启动：第一帧即空工位，按钮禁用（OUT-T03）', (tester) async {
      final clock = FixedClock(_shanghai(4, 18, 30));
      await _pumpDashboard(tester, clock: clock);

      expect(find.text('他已下班'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '他已下班'),
      );
      expect(button.onPressed, isNull);
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
      expect(find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'), findsNothing);
    });

    sceneTest('beforeShift / restDay 按钮给出原因（PAT-T12）', (tester) async {
      Future<void> expectDisabled(DateTime now, String label) async {
        final clock = FixedClock(now);
        await _pumpDashboard(tester, clock: clock);
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, label),
        );
        expect(button.onPressed, isNull, reason: label);
      }

      await expectDisabled(_shanghai(4, 8, 0), '还没到工位');
      await expectDisabled(_shanghai(7, 12, 0), '今天不在岗');
    });
  });

  group('离场播放与生命周期', () {
    sceneTest('可见时跨过 18:00 播放离场并落到空位（OUT-T01）', (tester) async {
      final clock = FixedClock(_shanghai(4, 17, 59, 59, 800));
      await _pumpDashboard(tester, clock: clock);
      expect(find.text('拍拍他'), findsOneWidget);

      clock.advance(const Duration(milliseconds: 400));
      await tester.pump(_tick);
      await tester.pump(_settle);
      expect(
        find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'),
        findsOneWidget,
      );

      await tester.pump(); // 锚定离场起始帧
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(_settle);
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
      expect(find.text('他已下班'), findsOneWidget);
    });

    sceneTest('拍拍中途下班：先离场后空位，无残留（OUT-T09）', (tester) async {
      final clock = FixedClock(_shanghai(4, 17, 59, 59, 0));
      await _pumpDashboard(tester, clock: clock);
      await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 1000));

      clock.advance(const Duration(milliseconds: 1100));
      await tester.pump(_tick);
      await tester.pump(_settle);
      expect(
        find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'),
        findsOneWidget,
      );
      expect(find.text('辛苦了。你又不是打印机。'), findsNothing);

      await tester.pump(); // 锚定离场起始帧
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(_settle);
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
    });

    sceneTest('切到资产页再回来：不补播、显示稳态（OUT-T11/LIFE-T01）', (tester) async {
      final clock = FixedClock(_shanghai(4, 17, 59, 59, 800));
      await _pumpDashboard(tester, clock: clock, fullShell: true);

      clock.advance(const Duration(milliseconds: 400));
      await tester.pump(_tick);
      await tester.pump(_settle);
      expect(
        find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'),
        findsOneWidget,
      );

      // 切到资产页（IndexedStack 保留首页状态）。
      await tester.tap(find.text('资产风浪'));
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(_tick);
      await tester.pump(_settle);
      expect(
        find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'),
        findsNothing,
      );

      await tester.tap(find.text('求生现场'));
      await tester.pump(_tick);
      await tester.pump(_settle);
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
    });
  });

  group('MOTION-01 与 A11Y', () {
    sceneTest('减少动效：立即静态回应，2400ms 后结束（PAT-T10）', (tester) async {
      final clock = FixedClock(_wednesday);
      await _pumpDashboard(tester, clock: clock, disableAnimations: true);

      await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 30));
      // 没有“抬头看一眼”的中间态，直接完整回应。
      expect(find.text('辛苦了。你又不是打印机。'), findsOneWidget);
      expect(find.text('他抬头看了你一眼。'), findsNothing);

      await tester.pump(const Duration(milliseconds: 2400));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(_settle);
      expect(find.text('拍拍他'), findsOneWidget);
    });

    sceneTest('320dp 宽 + 200% 字体：反馈区可读、按钮不溢出（A11Y-T01）',
        (tester) async {
      final clock = FixedClock(_wednesday);
      // 320dp 宽、加高视口让场景与按钮同屏：滚动到按钮会使场景不可见，
      // 可见性门控会正确拒绝拍肩，这里验收的是布局与对话本身。
      await _pumpDashboard(
        tester,
        clock: clock,
        textScale: 2.0,
        logicalSize: const Size(320, 1200),
      );

      final button = find.widgetWithText(TextButton, '拍拍他');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('辛苦了。你又不是打印机。'), findsOneWidget);
      expect(find.text('他缓过来一点了'), findsOneWidget); // 600ms 已过 520ms
      expect(tester.takeException(), isNull);
      await _finishPat(tester);
    });

    sceneTest('接受一次拍肩后反馈区作为 live region 播报（A11Y-T02）', (tester) async {
      final clock = FixedClock(_wednesday);
      await _pumpDashboard(tester, clock: clock);
      await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(_settle);

      final semantics = tester.getSemantics(
        find.bySemanticsLabel('辛苦了。你又不是打印机。'),
      );
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
      await _finishPat(tester);
    });
  });

  group('PAT-T08 动画不影响财务显示', () {
    sceneTest('同帧时钟下拍肩前后金额一致，金额只随时钟增长', (tester) async {
      final clock = FixedClock(_wednesday);
      await _pumpDashboard(tester, clock: clock);

      final before = _moneyText(tester)!.data;
      expect(before, isNotNull);

      await tester.tap(find.widgetWithText(TextButton, '拍拍他'));
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 800));
      final during = _moneyText(tester)!.data;
      expect(during, before); // 拍肩动画不改账本金额

      await _finishPat(tester);
      clock.advance(const Duration(minutes: 1));
      await tester.pump(_tick);
      await tester.pump(_settle);
      final after = _moneyText(tester)!.data;
      expect(after, isNot(before)); // 金额随时钟按计薪增长
    });
  });
}
