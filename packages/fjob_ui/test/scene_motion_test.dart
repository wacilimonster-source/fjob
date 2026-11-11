import 'package:finance_core/finance_core.dart';
import 'package:fjob_ui/fjob_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared durations keep mobile values and compatibility aliases', () {
    expect(SceneMotion.pat, const Duration(milliseconds: 3200));
    expect(SceneMotion.patReduced, const Duration(milliseconds: 2400));
    expect(SceneMotion.departure, const Duration(milliseconds: 2200));
    expect(SceneMotion.departureWindow, const Duration(milliseconds: 2000));
    expect(SceneMotion.ambient, const Duration(milliseconds: 8000));
    expect(SceneInteractionController.patDuration, SceneMotion.pat);
    expect(
        SceneInteractionController.patReducedDuration, SceneMotion.patReduced);
    expect(SceneInteractionController.departureDuration, SceneMotion.departure);
    expect(SceneInteractionController.departureWindow,
        SceneMotion.departureWindow);
    expect(SceneInteractionController.responseAtMs, SceneMotion.responseAtMs);
    expect(SceneMotion.patRecoveryAtMs, 2400);
    expect(SceneMotion.departureCoinsFadeAtMs, 180);
    expect(SceneMotion.departureStandAtMs, 560);
    expect(SceneMotion.departureWalkAtMs, 860);
    expect(SceneMotion.departureExitAtMs, 1900);
  });

  testWidgets('office uses the shared ambient clock and pauses when inactive',
      (tester) async {
    final controller = SceneInteractionController(vsync: TestVSync());
    addTearDown(controller.dispose);
    Future<void> pumpScene({bool active = true, bool reduced = false}) =>
        tester.pumpWidget(MaterialApp(
          theme: FjobTheme.light(),
          home: Center(
              child: SizedBox(
                  width: 380,
                  child: OfficeScene(
                    phase: DayPhase.working,
                    completeness: Completeness.complete,
                    total: Rational.fromInt(0),
                    reduceMotion: reduced,
                    active: active,
                    controller: controller,
                  ))),
        ));
    await pumpScene();
    final size = tester.getSize(find.byType(OfficeScene));
    expect(size.width, 380);
    expect(size.height, closeTo(238, 1e-8));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(controller.ambientMs, closeTo(1000, 1));
    expect(controller.ambientAnimating, isTrue);
    await pumpScene(active: false);
    final paused = controller.ambientMs;
    await tester.pump(const Duration(milliseconds: 1000));
    expect(controller.ambientMs, paused);
    expect(controller.ambientAnimating, isFalse);
    await pumpScene(reduced: true);
    await tester.pump(SceneMotion.ambient);
    expect(controller.ambientMs, paused);
    expect(controller.ambientAnimating, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
