import 'package:finance_core/finance_core.dart';
import 'package:fjob_ui/fjob_ui.dart';
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
      canPat: transient == TransientKind.idle,
      reduceMotion: reduced,
      ambientMs: 1000,
      animateAmbient: !reduced,
    );

WorkerFrame _resolve(ScenePresentation p) => WorkerFrame.resolve(
      presentation: p,
      ambientMs: p.ambientMs,
      animate: p.animateAmbient,
    );

List<Object> _parameters(WorkerFrame frame) => [
      frame.present,
      frame.seated,
      frame.typing,
      frame.relief,
      frame.compression,
      frame.handAlpha,
      frame.stand,
      frame.walk,
      frame.actorX,
      frame.localMs,
      frame.showBag,
      frame.showHand,
      frame.mood,
      frame.ambientMs,
      frame.animate,
      frame.walking,
    ];

void main() {
  test('all frame parameters are deterministic across states and keyframes',
      () {
    for (final phase in DayPhase.values) {
      for (final mood in SceneMood.values) {
        for (final transient in TransientKind.values) {
          for (final reduced in [false, true]) {
            for (final progress in [0.0, 0.1, 0.25, 0.5, 0.75, 1.0]) {
              final p = _presentation(
                  phase: phase,
                  mood: mood,
                  transient: transient,
                  progress: progress,
                  reduced: reduced);
              expect(_parameters(_resolve(p)), _parameters(_resolve(p)));
            }
          }
        }
      }
    }
  });

  test('idle frame retains every mobile parameter and phase gating', () {
    expect(_parameters(_resolve(_presentation())), [
      true,
      true,
      true,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      181.0,
      0.0,
      false,
      false,
      SceneMood.loss,
      1000.0,
      true,
      false,
    ]);
    final paused = _resolve(_presentation(phase: DayPhase.breakTime));
    expect(paused.present, isTrue);
    expect(paused.typing, isFalse);
    for (final phase in [
      DayPhase.beforeShift,
      DayPhase.afterShift,
      DayPhase.restDay,
      DayPhase.unknown
    ]) {
      final empty = _resolve(_presentation(phase: phase));
      expect(empty.present, isFalse);
      expect(empty.typing, isFalse);
    }
  });

  test('pat keyframes preserve compression, relief, hand and recovery', () {
    WorkerFrame at(double ms) => _resolve(
        _presentation(transient: TransientKind.pat, progress: ms / 3200));
    final contact = at(210);
    expect(contact.compression, closeTo(2.500001110909794, 0.00001));
    expect(contact.handAlpha, 1);
    expect(contact.showHand, isTrue);
    expect(contact.relief, 0);
    expect(contact.typing, isFalse);
    final response = at(900);
    expect(response.relief, 1);
    expect(response.showHand, isFalse);
    expect(response.actorX, 181);
    expect(at(2399).typing, isFalse);
    expect(at(2400).typing, isTrue);
    expect(at(2800).relief, 0.5);
    expect(at(3200).relief, 0);
  });

  test('reduced pat is a static response, without a hand or compression', () {
    final frame = _resolve(_presentation(
        transient: TransientKind.pat, progress: 0.5, reduced: true));
    expect(_parameters(frame), [
      true,
      true,
      false,
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
      181.0,
      1200.0,
      false,
      false,
      SceneMood.loss,
      1000.0,
      false,
      false,
    ]);
  });

  test('departure keyframes retain seated, stand, walk and offstage positions',
      () {
    WorkerFrame at(double ms) => _resolve(_presentation(
        phase: DayPhase.afterShift,
        transient: TransientKind.departure,
        progress: ms / 2200));
    expect(at(0).present, isTrue);
    expect(at(559).seated, isTrue);
    // ms / duration * duration may round just below the exact boundary.
    // Keep the production interpolation unchanged; assert on either side.
    expect(at(561).seated, isFalse);
    expect(at(561).showBag, isTrue);
    expect(at(710).stand, closeTo(0.5, 1e-12));
    expect(at(860).stand, 1);
    expect(at(860).walk, 0);
    expect(at(1380).walk, closeTo(0.5, 1e-12));
    expect(at(1380).actorX, closeTo(300.5, 1e-12));
    expect(at(1380).walking, isTrue);
    expect(at(1900).present, isFalse);
    expect(at(1900).actorX, 420);
    expect(at(2200).present, isFalse);
  });
}
