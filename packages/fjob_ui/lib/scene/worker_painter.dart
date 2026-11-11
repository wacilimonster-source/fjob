/// SCN-03: 可分部件变换的打工人绘制。
///
/// 头、躯干、手臂、腿、小包与表情全部由 [WorkerFrame] 参数化，参数由
/// [WorkerFrame.resolve] 从 [ScenePresentation] 确定性推导：同一次进度输入
/// 得到同一帧。坐标沿用场景逻辑系 380×238，头中心约 (178,96)。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:finance_core/finance_core.dart' show DayPhase;

import '../theme.dart';
import 'office_scene.dart' show DebtArtPainter;
import 'scene_interaction_controller.dart';
import 'scene_motion.dart';

/// 一帧内角色的全部姿态参数。
final class WorkerFrame {
  const WorkerFrame({
    required this.present,
    required this.seated,
    required this.typing,
    required this.relief,
    required this.compression,
    required this.handAlpha,
    required this.stand,
    required this.walk,
    required this.actorX,
    required this.localMs,
    required this.showBag,
    required this.showHand,
    required this.mood,
    required this.ambientMs,
    required this.animate,
  });

  /// 是否绘制角色（离场完成或空工位为 false）。
  final bool present;

  /// 坐姿（桌后遮挡）还是起立/行走（前景）。
  final bool seated;

  /// 敲键盘手臂；false 时为放松手臂（午休、拍肩回应、离场）。
  final bool typing;

  /// 拍肩回应程度 0..1：抬眼、眉松、腮红、嘴角。
  final double relief;

  /// 拍肩头部下沉量（逻辑像素）。
  final double compression;

  /// 手掌透明度 0..1。
  final double handAlpha;

  /// 离场起身 0..1（560—860ms）。
  final double stand;

  /// 离场行走 0..1（860—1900ms），1 表示完全离开。
  final double walk;

  /// 行走角色根节点 x（逻辑坐标），181 起步、420 出场。
  final double actorX;

  /// 瞬态本地毫秒，用于步频与起伏。
  final double localMs;

  final bool showBag;
  final bool showHand;

  final SceneMood mood;
  final double ambientMs;
  final bool animate;

  bool get walking => !seated && walk > 0 && walk < 1;

  static double _smooth(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double _segment(double t, double a, double b) =>
      b == a ? 0 : _smooth((t - a) / (b - a));

  /// PAT/OUT 的关键帧参数，全部由 progress 确定性计算。
  static WorkerFrame resolve({
    required ScenePresentation presentation,
    required double ambientMs,
    required bool animate,
  }) {
    final atDesk = presentation.presence == Presence.atDesk;
    final mood = presentation.mood;
    switch (presentation.transient) {
      case TransientKind.pat:
        final reduced = presentation.reduceMotion;
        final t = presentation.progress *
            (reduced ? SceneMotion.patReduced : SceneMotion.pat).inMilliseconds;
        if (reduced) {
          // MOTION-01：立即静态抬眼、腮红与放松肩膀，无路径移动。
          return WorkerFrame(
            present: true,
            seated: true,
            typing: false,
            relief: 1,
            compression: 0,
            handAlpha: 0,
            stand: 0,
            walk: 0,
            actorX: 181,
            localMs: t,
            showBag: false,
            showHand: false,
            mood: mood,
            ambientMs: ambientMs,
            animate: false,
          );
        }
        final relief = _segment(t, 520, 900) *
            (1 -
                _segment(t, SceneMotion.patRecoveryAtMs,
                    SceneMotion.pat.inMilliseconds.toDouble()));
        final compression = 2.5 * math.exp(-math.pow((t - 210) / 53, 2)) +
            1.7 * math.exp(-math.pow((t - 410) / 53, 2));
        final handAlpha = _segment(t, 0, 120) * (1 - _segment(t, 520, 720));
        return WorkerFrame(
          present: true,
          seated: true,
          // PAT-03：0—2400ms 停手，2400ms 起恢复敲键盘。
          typing: presentation.phase == DayPhase.working &&
              t >= SceneMotion.patRecoveryAtMs &&
              animate,
          relief: relief,
          compression: compression,
          handAlpha: handAlpha,
          stand: 0,
          walk: 0,
          actorX: 181,
          localMs: t,
          showBag: false,
          showHand: handAlpha > 0,
          mood: mood,
          ambientMs: ambientMs,
          animate: animate,
        );
      case TransientKind.departure:
        final t = presentation.progress * SceneMotion.departure.inMilliseconds;
        final stand = _segment(
            t, SceneMotion.departureStandAtMs, SceneMotion.departureWalkAtMs);
        final walk = _segment(
            t, SceneMotion.departureWalkAtMs, SceneMotion.departureExitAtMs);
        return WorkerFrame(
          present: walk < 1,
          seated: t < SceneMotion.departureStandAtMs,
          typing: false,
          relief: 0,
          compression: 0,
          handAlpha: 0,
          stand: stand,
          walk: walk,
          actorX: 181 + 239 * walk,
          localMs: t,
          showBag: t >= SceneMotion.departureStandAtMs,
          showHand: false,
          mood: mood,
          ambientMs: ambientMs,
          animate: animate,
        );
      case TransientKind.idle:
        return WorkerFrame(
          present: atDesk,
          seated: true,
          typing: atDesk && presentation.phase == DayPhase.working && animate,
          relief: 0,
          compression: 0,
          handAlpha: 0,
          stand: 0,
          walk: 0,
          actorX: 181,
          localMs: 0,
          showBag: false,
          showHand: false,
          mood: mood,
          ambientMs: ambientMs,
          animate: animate,
        );
    }
  }
}

/// 角色部件绘制。场景内顺序：坐姿在桌子后，行走时由场景把本绘制放到前景。
final class WorkerPainter {
  WorkerPainter({required this.palette});

  final FjobPalette palette;

  void paint(ui.Canvas canvas, WorkerFrame frame) {
    if (!frame.present) return;
    final ink = palette.ink;
    final paper = palette.panel;
    final rose = palette.rose;
    final muted = palette.muted;

    void line(List<ui.Offset> points, ui.Color color, double width) {
      final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..style = ui.PaintingStyle.stroke,
      );
    }

    void oval(double x, double y, double rx, double ry, ui.Color fill,
        {bool outline = true}) {
      DebtArtPainter.paintOval(
          canvas, x, y, rx, ry, fill, outline ? ink : null, 1.8);
    }

    final walking = frame.walking;
    final step = walking
        ? math.sin(
              ((frame.localMs - SceneMotion.departureWalkAtMs) *
                      math.pi *
                      2 *
                      2.5) /
                  1000,
            ) *
            11
        : 0.0;
    final standY = -16 * frame.stand;
    final bob = walking ? math.sin(frame.localMs * 0.016) * 1.1 : 0.0;

    canvas.save();
    canvas.translate(frame.actorX - 181, standY + bob);

    // 躯干（坐姿与站立共用头部与五官几何）。
    oval(181, 143, 25, 35, paper);

    // 腿：坐姿落在 y≈199，起身随 stand 伸展到 y=228，行走交替摆动。
    final footY = walking ? 228.0 : ui.lerpDouble(199, 228, frame.stand)!;
    line([
      ui.Offset(170, 169),
      ui.Offset(165 + step * 0.6, 197),
      ui.Offset(151 + step, footY),
    ], ink, 5);
    line([
      ui.Offset(187, 171),
      ui.Offset(194 - step * 0.6, 198),
      ui.Offset(211 - step, footY),
    ], ink, 5);

    // 头部：拍肩下沉 + 以颈部为轴的小旋转与 Y 压缩。
    canvas.save();
    canvas.translate(178, 129);
    canvas.rotate((frame.compression / 2.5) * 0.0436);
    canvas.scale(1, 1 - (frame.compression / 2.5) * 0.035);
    canvas.translate(-178, -129 + frame.compression);
    oval(178, 96, 30, 35, paper);
    final hair = ui.Path()
      ..moveTo(149, 85)
      ..cubicTo(147, 56, 199, 48, 208, 85)
      ..lineTo(194, 75)
      ..lineTo(192, 86)
      ..lineTo(180, 76)
      ..lineTo(170, 85)
      ..lineTo(162, 78)
      ..close();
    canvas.drawPath(hair, ui.Paint()..color = ink);
    line(const [ui.Offset(155, 69), ui.Offset(152, 58), ui.Offset(166, 65)],
        ink, 2);
    line(const [ui.Offset(173, 61), ui.Offset(182, 51), ui.Offset(186, 61)],
        ink, 2);

    final relieved = frame.relief;
    if (relieved > 0.15) {
      // 抬眼、眉松、嘴角上扬、腮红两笔。
      line(const [ui.Offset(157, 91), ui.Offset(164, 89), ui.Offset(170, 91)],
          ink, 1.8);
      line(const [ui.Offset(182, 91), ui.Offset(188, 89), ui.Offset(195, 91)],
          ink, 1.8);
      line(const [ui.Offset(158, 99), ui.Offset(164, 96), ui.Offset(170, 99)],
          ink, 2);
      line(const [ui.Offset(182, 99), ui.Offset(188, 96), ui.Offset(194, 99)],
          ink, 2);
      final blush = ui.Paint()
        ..color = rose.withValues(alpha: relieved.clamp(0.0, 1.0))
        ..strokeWidth = 2.7
        ..strokeCap = ui.StrokeCap.round;
      void blushLine(double x1, double y1, double x2, double y2) {
        canvas.drawLine(ui.Offset(x1, y1), ui.Offset(x2, y2), blush);
      }

      blushLine(153, 110, 156, 107);
      blushLine(158, 111, 161, 108);
      blushLine(195, 110, 198, 107);
      blushLine(190, 111, 193, 108);
      final smile = ui.Path()
        ..moveTo(172, 116)
        ..quadraticBezierTo(178, 121, 184, 115);
      canvas.drawPath(
        smile,
        ui.Paint()
          ..color = ink
          ..strokeWidth = 1.5
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round,
      );
    } else if (frame.mood == SceneMood.gain) {
      line(const [ui.Offset(158, 98), ui.Offset(164, 95), ui.Offset(170, 98)],
          ink, 2);
      line(const [ui.Offset(182, 98), ui.Offset(188, 95), ui.Offset(194, 98)],
          ink, 2);
      line(const [ui.Offset(172, 117), ui.Offset(182, 117)], ink, 1.5);
    } else {
      line(const [ui.Offset(157, 95), ui.Offset(169, 96)], ink, 2);
      line(const [ui.Offset(183, 96), ui.Offset(195, 95)], ink, 2);
      oval(165, 101, 2, 3, ink, outline: false);
      oval(187, 101, 2, 3, ink, outline: false);
      line(const [ui.Offset(158, 107), ui.Offset(169, 108)], muted, 1);
      line(const [ui.Offset(183, 108), ui.Offset(194, 107)], muted, 1);
      line(const [ui.Offset(171, 117), ui.Offset(182, 117)], ink, 1.5);
    }
    canvas.restore();

    // 领口与歪领带。
    line(const [ui.Offset(171, 130), ui.Offset(179, 138), ui.Offset(186, 129)],
        muted, 1);
    final tie = ui.Path()
      ..moveTo(179, 138)
      ..lineTo(176, 157)
      ..lineTo(183, 154)
      ..close();
    canvas.drawPath(tie, ui.Paint()..color = ink);
    canvas.drawPath(
      tie,
      ui.Paint()
        ..color = ink
        ..strokeWidth = 1
        ..style = ui.PaintingStyle.stroke,
    );

    // 手臂：敲键盘或放松（回应时随 relief 下沉）。
    final tap = frame.typing && frame.animate
        ? math.sin(frame.ambientMs * 0.025) * 2
        : 0.0;
    if (frame.typing) {
      line([
        const ui.Offset(158, 137),
        const ui.Offset(146, 151),
        ui.Offset(169, 157 + tap),
      ], ink, 4);
      line([
        const ui.Offset(199, 136),
        const ui.Offset(214, 150),
        ui.Offset(201, 157 - tap),
      ], ink, 4);
    } else {
      final relax = 2 * frame.relief;
      line([
        ui.Offset(158, 137 + relax),
        ui.Offset(147, 157 + relax),
        ui.Offset(160, 167 + relax),
      ], ink, 4);
      line([
        ui.Offset(199, 136 + relax),
        ui.Offset(213, 157 + relax),
        ui.Offset(200, 167 + relax),
      ], ink, 4);
    }

    // 离场小包：rose 色块 + 短背带，约 14×18 逻辑像素。
    if (frame.showBag) {
      line(const [
        ui.Offset(184, 132),
        ui.Offset(202, 147),
        ui.Offset(205, 162),
      ], ink, 1.5);
      final bag = ui.Path()
        ..addRRect(
          ui.RRect.fromRectAndRadius(
            const ui.Rect.fromLTWH(198, 147, 14, 18),
            const ui.Radius.circular(3),
          ),
        );
      canvas.drawPath(bag, ui.Paint()..color = rose);
      canvas.drawPath(
        bag,
        ui.Paint()
          ..color = ink
          ..strokeWidth = 1.8
          ..style = ui.PaintingStyle.stroke,
      );
    }

    canvas.restore();

    // 拍肩手掌与接触短线（最上层）。
    if (frame.showHand && frame.handAlpha > 0) {
      _paintHand(canvas, frame);
    }
  }

  void _paintHand(ui.Canvas canvas, WorkerFrame frame) {
    final t = frame.localMs;
    double segment(double a, double b) {
      final x = ((t - a) / (b - a)).clamp(0.0, 1.0);
      return x * x * (3 - 2 * x);
    }

    final enter = segment(0, 160);
    final leave = segment(520, 720);
    final x = ui.lerpDouble(235, 210, enter)! + 25 * leave;
    final y = ui.lerpDouble(106, 132, enter)! - 26 * leave + frame.compression;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.35);
    final path = ui.Path()
      ..moveTo(-9, 10)
      ..lineTo(-11, -1)
      ..quadraticBezierTo(-12, -5, -8, -5)
      ..lineTo(-4, 0)
      ..lineTo(-5, -13)
      ..quadraticBezierTo(-5, -17, -1, -16)
      ..lineTo(1, -4)
      ..lineTo(2, -16)
      ..quadraticBezierTo(3, -20, 6, -17)
      ..lineTo(8, -5)
      ..lineTo(9, -13)
      ..quadraticBezierTo(11, -16, 13, -12)
      ..lineTo(15, 4)
      ..quadraticBezierTo(13, 13, 5, 15)
      ..lineTo(-1, 17)
      ..close();
    canvas.drawPath(path, ui.Paint()..color = palette.panel);
    canvas.drawPath(
      path,
      ui.Paint()
        ..color = palette.ink
        ..strokeWidth = 1.8
        ..style = ui.PaintingStyle.stroke,
    );
    canvas.restore();

    // 接触点外侧短线，每次最多两笔。
    if (frame.compression > 1) {
      final tick = ui.Paint()
        ..color = palette.muted
        ..strokeWidth = 1.5
        ..strokeCap = ui.StrokeCap.round;
      canvas.drawLine(
          const ui.Offset(210, 132), const ui.Offset(215, 128), tick);
      canvas.drawLine(
          const ui.Offset(211, 140), const ui.Offset(217, 140), tick);
    }
  }
}
