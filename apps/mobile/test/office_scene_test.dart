/// SCN-03/SCN-05: 场景绘制状态、头肩触控门控与空工位语义。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

final DateTime _wednesday = DateTime.utc(2026, 11, 4, 6, 36);

WorkSessionContext _contextAt(DateTime utc) {
  final calendar = BusinessCalendar.shanghai;
  final version = ScheduleVersion(
    id: 'office',
    timezone: calendar.timezoneName,
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: DateTime.utc(2026, 1, 1),
  );
  return ScheduleExpander((_) => calendar)
      .workSessionContext(version: version, overrides: const [], nowUtc: utc);
}

SceneInteractionController _controllerAt(DateTime utc) {
  final controller = SceneInteractionController(vsync: TestVSync());
  controller.reconcile(
    workSession: _contextAt(utc),
    nowUtc: utc,
    visible: true,
    namespace: 'test',
    scheduleStamp: 1,
    mood: SceneMood.loss,
    tone: AppTone.gentle,
    reduceMotion: false,
  );
  return controller;
}

/// 注意：每个用例自行创建并 dispose SemanticsHandle。
Future<void> _pumpScene(
  WidgetTester tester, {
  DayPhase phase = DayPhase.working,
  SceneInteractionController? controller,
  VoidCallback? onRequestPat,
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FjobTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            height: 238,
            child: OfficeScene(
              phase: phase,
              completeness: Completeness.complete,
              total: Rational.fromInt(0),
              reduceMotion: reduceMotion,
              controller: controller,
              onRequestPat: onRequestPat,
              showHousing: false,
              showCar: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  group('空工位稳态（PAT-T12 / OUT-05）', () {
    testWidgets('afterShift 显示已下班空位', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpScene(tester, phase: DayPhase.afterShift);
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
      // 没有头肩触控入口可点。
      expect(find.byType(GestureDetector), findsNothing);
      semantics.dispose();
    });

    testWidgets('beforeShift / restDay / unknown 各自描述状态', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpScene(tester, phase: DayPhase.beforeShift);
      expect(find.bySemanticsLabel('空工位，还没到岗'), findsOneWidget);

      await _pumpScene(tester, phase: DayPhase.restDay);
      expect(find.bySemanticsLabel('空工位，今天休息'), findsOneWidget);

      await _pumpScene(tester, phase: DayPhase.unknown);
      expect(find.bySemanticsLabel('空工位，排班待确认'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('在岗与头肩触控', () {
    testWidgets('working 显示在工位语义并暴露头肩按钮', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _controllerAt(_wednesday);
      addTearDown(controller.dispose);
      await _pumpScene(tester, controller: controller);
      expect(find.bySemanticsLabel('手绘办公室：打工人在工位上'), findsOneWidget);
      expect(find.bySemanticsLabel('拍拍他，给正在工位上的他一点安慰'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('头肩点击触发拍肩，3200ms 后语义恢复（PAT-T01）', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _controllerAt(_wednesday);
      addTearDown(controller.dispose);
      var requests = 0;
      await _pumpScene(
        tester,
        controller: controller,
        onRequestPat: () {
          requests++;
          controller.requestPat(
            workSession: _contextAt(_wednesday),
            nowUtc: _wednesday,
          );
        },
      );

      await tester.tap(find.bySemanticsLabel('拍拍他，给正在工位上的他一点安慰'));
      expect(requests, 1);
      expect(controller.transient, TransientKind.pat);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.bySemanticsLabel('手绘办公室：人物被轻轻拍肩，抬眼回应'),
        findsOneWidget,
      );
      // 播放中头肩入口消失，重复点击无法触发。
      expect(find.bySemanticsLabel('拍拍他，给正在工位上的他一点安慰'), findsNothing);
      await tester.tap(
        find.bySemanticsLabel('手绘办公室：人物被轻轻拍肩，抬眼回应'),
        warnIfMissed: false,
      );
      expect(requests, 1); // PAT-T06：连点不叠加

      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
      expect(find.bySemanticsLabel('手绘办公室：打工人在工位上'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('拍肩中途下班：离场语义替代拍肩并最终空位（OUT-T09）', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = _controllerAt(DateTime.utc(2026, 11, 4, 9, 59, 59, 900));
      addTearDown(controller.dispose);
      await _pumpScene(tester, controller: controller);
      await tester.tap(find.bySemanticsLabel('拍拍他，给正在工位上的他一点安慰'));
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 1500));

      final afterEnd = DateTime.utc(2026, 11, 4, 10, 0, 0, 100);
      controller.reconcile(
        workSession: _contextAt(afterEnd),
        nowUtc: afterEnd,
        visible: true,
        namespace: 'test',
        scheduleStamp: 1,
        mood: SceneMood.loss,
        tone: AppTone.gentle,
        reduceMotion: false,
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        find.bySemanticsLabel('手绘办公室：人物正在提包离开工位'),
        findsOneWidget,
      );

      await tester.pump(); // 锚定离场起始帧
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('绘制定糖性冒烟', () {
    testWidgets('全部阶段与减少动效都能整帧绘制，无异常', (tester) async {
      for (final phase in DayPhase.values) {
        await _pumpScene(tester, phase: phase, reduceMotion: true);
        expect(tester.takeException(), isNull, reason: '$phase');
      }
      await _pumpScene(tester, phase: DayPhase.working);
      await tester.pump(const Duration(seconds: 8));
      expect(tester.takeException(), isNull);
    });
  });
}
