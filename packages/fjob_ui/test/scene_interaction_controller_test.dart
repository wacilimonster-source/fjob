/// SCN-02/SCN-05: SceneInteractionController 的时序、竞态与生命周期。
///
/// 全部时序用 testWidgets 的假时钟推进；业务时钟是显式传入的 nowUtc，
/// 因此跨夜、边界窗口与冷启动都不依赖真实等待。
library;

import 'package:finance_core/finance_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:ledger_model/ledger_model.dart';

final DateTime _wednesday = DateTime.utc(2026, 11, 4, 6, 36); // 周三 14:36

WorkSessionContext _contextAt(DateTime utc) {
  final calendar = BusinessCalendar.shanghai;
  final version = ScheduleVersion(
    id: 'office',
    timezone: calendar.timezoneName,
    week: WeekTemplate.standardOffice(),
    effectiveFromUtc: DateTime.utc(2026, 1, 1),
  );
  final expander = ScheduleExpander((_) => calendar);
  return expander.workSessionContext(
    version: version,
    overrides: const [],
    nowUtc: utc,
  );
}

/// 上海本地时间 → UTC。([second], [ms]) 用于班次终点附近的时间。
DateTime _shanghai(int day, int hour, int minute,
        [int second = 0, int ms = 0]) =>
    DateTime.utc(2026, 11, day, hour - 8, minute, second, ms);

void main() {
  late SceneInteractionController controller;

  setUp(() {
    controller = SceneInteractionController(vsync: TestVSync());
  });

  tearDown(() => controller.dispose());

  void reconcileAt(
    DateTime nowUtc, {
    bool visible = true,
    String namespace = 'test',
    int stamp = 1,
    SceneMood mood = SceneMood.loss,
    AppTone tone = AppTone.gentle,
    bool reduceMotion = false,
  }) {
    controller.reconcile(
      workSession: _contextAt(nowUtc),
      nowUtc: nowUtc,
      visible: visible,
      namespace: namespace,
      scheduleStamp: stamp,
      mood: mood,
      tone: tone,
      reduceMotion: reduceMotion,
    );
  }

  group('PAT 拍肩时序', () {
    testWidgets('接受后 120ms 内进入 pat，3200ms 结束恢复', (tester) async {
      reconcileAt(_wednesday);
      expect(controller.canPat, isTrue);

      final result = controller.requestPat(
        workSession: _contextAt(_wednesday),
        nowUtc: _wednesday,
      );
      expect(result, PatRequestResult.accepted);
      expect(controller.transient, TransientKind.pat);
      expect(controller.presentation.canPat, isFalse);

      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.transient, TransientKind.pat);
      // PAT-T01：120ms 时已是第二拍前夜，压缩量存在但尚未进入回应段。
      expect(controller.feedbackLine, '他抬头看了你一眼。');

      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.feedbackLine, '辛苦了。你又不是打印机。');

      await tester.pump(const Duration(milliseconds: 2580));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
      expect(controller.canPat, isTrue);
      expect(controller.feedbackLine, isNull);
    });

    testWidgets('1 秒内连点 20 次只接受一次，不延长时长', (tester) async {
      reconcileAt(_wednesday);
      var accepted = 0;
      for (var index = 0; index < 20; index++) {
        final result = controller.requestPat(
          workSession: _contextAt(_wednesday),
          nowUtc: _wednesday.add(Duration(milliseconds: index * 50)),
        );
        if (result == PatRequestResult.accepted) accepted++;
      }
      expect(accepted, 1); // PAT-T05
      expect(controller.acceptedPatCount, 1);

      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('3200ms 后可再次拍，文案按池推进，语气中途切换不打断当前句', (tester) async {
      reconcileAt(_wednesday, tone: AppTone.gentle);
      controller.requestPat(
        workSession: _contextAt(_wednesday),
        nowUtc: _wednesday,
      );
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.feedbackLine, '辛苦了。你又不是打印机。');

      // PAT-T11：拍肩期间切换语气，当前句保留。
      reconcileAt(_wednesday.add(const Duration(milliseconds: 500)),
          tone: AppTone.harsh);
      expect(controller.feedbackLine, '辛苦了。你又不是打印机。');

      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);

      // PAT-T06：第二次点击按池取下一句，且采用新语气。
      reconcileAt(_wednesday.add(const Duration(milliseconds: 3300)),
          tone: AppTone.harsh);
      final second = controller.requestPat(
        workSession: _contextAt(_wednesday),
        nowUtc: _wednesday,
      );
      expect(second, PatRequestResult.accepted);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.feedbackLine, '老板没看见，先松口气。');

      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      controller.requestPat(
        workSession: _contextAt(_wednesday),
        nowUtc: _wednesday,
      );
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.feedbackLine, '牛马收到一点人类关怀。');

      // 让动画完整收尾，避免测试结束时残留 ticker。
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('午休拍肩保持休息姿态语境并使用午休文案池', (tester) async {
      final noon = _shanghai(4, 12, 30); // 午休
      reconcileAt(noon);
      expect(controller.presence, Presence.atDesk);
      expect(controller.phase, DayPhase.breakTime);

      controller.requestPat(workSession: _contextAt(noon), nowUtc: noon);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.feedbackLine, '先歇会儿，下午再慢慢来。');

      // 让动画完整收尾，避免测试结束时残留 ticker。
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('空位状态一律拒绝拍肩', (tester) async {
      final cases = <DateTime, DayPhase>{
        _shanghai(4, 19, 0): DayPhase.afterShift,
        _shanghai(4, 8, 0): DayPhase.beforeShift,
        _shanghai(7, 4, 0): DayPhase.restDay, // 周六
      };
      cases.forEach((nowUtc, phase) {
        reconcileAt(nowUtc);
        expect(controller.phase, phase);
        final result = controller.requestPat(
          workSession: _contextAt(nowUtc),
          nowUtc: nowUtc,
        );
        expect(result, PatRequestResult.rejected, reason: '$phase 应拒绝');
        expect(controller.transient, TransientKind.idle);
        expect(controller.acceptedPatCount, 0);
      });
    });

    testWidgets('拍肩期间报价刷新不重置进度（PAT-T09）', (tester) async {
      reconcileAt(_wednesday, mood: SceneMood.loss);
      controller.requestPat(
          workSession: _contextAt(_wednesday), nowUtc: _wednesday);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 1000));
      expect(controller.progress, greaterThan(0.2));

      reconcileAt(_wednesday.add(const Duration(milliseconds: 250)),
          mood: SceneMood.gain);
      expect(controller.transient, TransientKind.pat);
      expect(controller.progress, greaterThan(0.3)); // 进度持续
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
    });
  });

  group('MOTION-01 减少动效', () {
    testWidgets('开启时立即静态回应，2400ms 后结束', (tester) async {
      reconcileAt(_wednesday, reduceMotion: true);
      controller.requestPat(
          workSession: _contextAt(_wednesday), nowUtc: _wednesday);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 2400));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('拍肩中途开启：以接受时刻为起点保留至 2400ms', (tester) async {
      reconcileAt(_wednesday);
      controller.requestPat(
          workSession: _contextAt(_wednesday), nowUtc: _wednesday);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 1200));
      expect(controller.patElapsedMs, closeTo(1200, 40));

      reconcileAt(_wednesday.add(const Duration(milliseconds: 1200)),
          reduceMotion: true);
      expect(controller.transient, TransientKind.pat);
      await tester.pump(); // 锚定保留段起始帧
      await tester.pump(const Duration(milliseconds: 1150));
      expect(controller.transient, TransientKind.pat);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle); // 1200+1200=2400
    });

    testWidgets('离场中途开启减少动效：立即空位', (tester) async {
      final beforeEnd = _shanghai(4, 17, 59, 59, 900);
      reconcileAt(beforeEnd);
      controller.requestPat(
          workSession: _contextAt(beforeEnd), nowUtc: beforeEnd);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 1500));
      // OUT-T09：拍肩第 1500ms 遇下班 → 取消拍肩，开始离场。
      reconcileAt(_shanghai(4, 18, 0, 0, 100));
      expect(controller.transient, TransientKind.departure);
      expect(controller.feedbackLine, '他把手从键盘上拿开了。'); // 拍肩文案立即让位

      reconcileAt(_shanghai(4, 18, 0, 0, 300), reduceMotion: true);
      expect(controller.transient, TransientKind.idle);
      expect(controller.presence, Presence.emptyDesk);
      expect(controller.announcement, '他已下班，工位已空');
    });
  });

  group('OUT 下班离场', () {
    testWidgets('可见时跨越 18:00 播放一次离场（OUT-T01）', (tester) async {
      reconcileAt(_shanghai(4, 17, 59, 59, 900));
      reconcileAt(_shanghai(4, 18, 0, 0, 100));
      expect(controller.transient, TransientKind.departure);

      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 16)); // 完成状态落帧
      expect(controller.transient, TransientKind.idle);
      expect(controller.presence, Presence.emptyDesk);

      // 同一结束快照继续刷新不再重播（OUT-T13 的核心）。
      for (var index = 0; index < 100; index++) {
        reconcileAt(_shanghai(4, 18, 0, 0, 200 + index));
      }
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('迟到 2.5s 才观察结束：直接空位不重演（OUT-T02）', (tester) async {
      reconcileAt(_shanghai(4, 17, 59, 59, 900));
      reconcileAt(_shanghai(4, 18, 0, 2, 500));
      expect(controller.transient, TransientKind.idle);
      expect(controller.presence, Presence.emptyDesk);
    });

    testWidgets('冷启动即下班：第一帧就是空位（OUT-T03）', (tester) async {
      reconcileAt(_shanghai(4, 18, 30));
      expect(controller.transient, TransientKind.idle);
      expect(controller.presence, Presence.emptyDesk);
      expect(controller.canPat, isFalse);
    });

    testWidgets('午夜仍在跨夜班内：保持在岗，不触发离场（OUT-T05）', (tester) async {
      final version = ScheduleVersion(
        id: 'night',
        timezone: 'Asia/Shanghai',
        week: WeekTemplate(<List<ShiftTemplate>>[
          for (var index = 0; index < 7; index++)
            const <ShiftTemplate>[
              ShiftTemplate(startMinute: 22 * 60, endMinute: 26 * 60),
            ],
        ]),
        effectiveFromUtc: DateTime.utc(2026, 1, 1),
      );
      final expander = ScheduleExpander((_) => BusinessCalendar.shanghai);

      WorkSessionContext nightContext(DateTime utc) =>
          expander.workSessionContext(
            version: version,
            overrides: const [],
            nowUtc: utc,
          );

      // 23:59:50 与 00:00:10 同属一个班次。
      controller.reconcile(
        workSession: nightContext(_shanghai(4, 23, 59, 59, 500)),
        nowUtc: _shanghai(4, 23, 59, 59, 500),
        visible: true,
        namespace: 'test',
        scheduleStamp: 1,
        mood: SceneMood.loss,
        tone: AppTone.gentle,
        reduceMotion: false,
      );
      expect(controller.presence, Presence.atDesk);

      final afterMidnight = DateTime.utc(2026, 11, 4, 16, 0, 0, 100);
      controller.reconcile(
        workSession: nightContext(afterMidnight),
        nowUtc: afterMidnight,
        visible: true,
        namespace: 'test',
        scheduleStamp: 1,
        mood: SceneMood.loss,
        tone: AppTone.gentle,
        reduceMotion: false,
      );
      expect(controller.presence, Presence.atDesk);
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('离场中修改排班延长工作：取消离场回在岗帧（OUT-T10）', (tester) async {
      reconcileAt(_shanghai(4, 17, 59, 59, 900));
      reconcileAt(_shanghai(4, 18, 0, 0, 100));
      expect(controller.transient, TransientKind.departure);
      await tester.pump(const Duration(milliseconds: 600));

      reconcileAt(_shanghai(4, 18, 0, 0, 300), stamp: 2);
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('切页隐藏后瞬态取消且不补播（LIFE-T01/OUT-T04）', (tester) async {
      reconcileAt(_shanghai(4, 17, 59, 59, 900));
      controller.requestPat(
        workSession: _contextAt(_shanghai(4, 17, 59, 59, 900)),
        nowUtc: _shanghai(4, 17, 59, 59, 900),
      );
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.transient, TransientKind.pat);

      reconcileAt(_shanghai(4, 18, 0, 0), visible: false);
      expect(controller.transient, TransientKind.idle);

      // 隐藏期间已下班，恢复后直接空位。
      reconcileAt(_shanghai(4, 18, 1, 0));
      expect(controller.presence, Presence.emptyDesk);
      expect(controller.transient, TransientKind.idle);
    });

    testWidgets('系统时钟跳变：取消瞬态重新取稳态（LIFE-T05）', (tester) async {
      reconcileAt(_wednesday);
      controller.requestPat(
          workSession: _contextAt(_wednesday), nowUtc: _wednesday);
      await tester.pump(); // 锚定起始帧
      await tester.pump(const Duration(milliseconds: 300));

      reconcileAt(_wednesday.subtract(const Duration(minutes: 30)));
      expect(controller.transient, TransientKind.idle);
    });
  });
}
