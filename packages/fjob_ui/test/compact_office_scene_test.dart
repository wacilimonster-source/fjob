import 'package:finance_core/finance_core.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScenePresentation _presentation({
  DayPhase phase = DayPhase.working,
  SceneMood mood = SceneMood.loss,
  TransientKind transient = TransientKind.idle,
  double progress = 0,
  bool reduced = false,
}) =>
    ScenePresentation(
      phase: phase,
      presence: phase == DayPhase.working || phase == DayPhase.breakTime
          ? Presence.atDesk
          : Presence.emptyDesk,
      mood: mood,
      transient: transient,
      progress: progress,
      canPat: false,
      reduceMotion: reduced,
      ambientMs: 1500,
      animateAmbient: !reduced,
    );

Future<void> _pump(
  WidgetTester tester,
  ScenePresentation presentation, {
  double width = 380,
  bool housing = true,
  bool car = true,
}) =>
    tester.pumpWidget(MaterialApp(
      theme: FjobTheme.light(),
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: width,
        child: CompactOfficeScene(
          presentation: presentation,
          showHousing: housing,
          showCar: car,
          housingLabel: '房租',
        ),
      ))),
    ));

void main() {
  testWidgets('380x112 composition renders every phase/mood and reduced frame',
      (tester) async {
    for (final phase in DayPhase.values) {
      for (final mood in SceneMood.values) {
        for (final reduced in [false, true]) {
          await _pump(tester,
              _presentation(phase: phase, mood: mood, reduced: reduced));
          expect(tester.getSize(find.byType(CompactOfficeScene)),
              const Size(380, 112));
          expect(tester.takeException(), isNull,
              reason: '$phase/$mood/$reduced');
        }
      }
    }
  });

  testWidgets('pat and walk-out render the shared presentation without tickers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final transient in [TransientKind.pat, TransientKind.departure]) {
        for (final progress in [0.0, 0.2, 0.5, 0.8, 1.0]) {
          await _pump(
              tester, _presentation(transient: transient, progress: progress));
          expect(tester.takeException(), isNull);
          expect(
              find.bySemanticsLabel(transient == TransientKind.pat
                  ? '手绘办公室：人物被轻轻拍肩，抬眼回应'
                  : '手绘办公室：人物正在提包离开工位'),
              findsOneWidget);
          // MaterialApp's theme interpolation may schedule a transient frame.
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 2),
          );
          expect(tester.binding.transientCallbackCount, 0);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'debt visibility, shared empty-desk wording and proportional size',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final (housing, car, suffix) in [
        (true, true, '，硬币流向房租和车贷'),
        (true, false, '，硬币流向房租'),
        (false, true, '，硬币流向车贷'),
        (false, false, ''),
      ]) {
        await _pump(tester, _presentation(), housing: housing, car: car);
        expect(find.bySemanticsLabel('手绘办公室：打工人在工位上$suffix'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (final width in [220.0, 320.0, 420.0]) {
        await _pump(tester, _presentation(phase: DayPhase.afterShift),
            width: width);
        final size = tester.getSize(find.byType(CompactOfficeScene));
        expect(size.width, width);
        expect(size.height, closeTo(width * 112 / 380, 1e-8));
        expect(find.bySemanticsLabel('空工位，人物已下班'), findsOneWidget);
      }
    } finally {
      semantics.dispose();
    }
  });
}
