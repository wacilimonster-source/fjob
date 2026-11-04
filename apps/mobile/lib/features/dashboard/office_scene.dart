/// 粗线条、扁平奶油色的办公室小剧场。
///
/// 场景只消费展示状态（工作阶段、盈亏心情、金额是否完整），从不读取数据库
/// 或行情接口。动画时间由本地控制器驱动，不参与任何账本金额计算。
library;

import 'dart:math' as math;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum SceneMood { gain, loss, unknown }

enum DebtArtType { house, car }

class OfficeScene extends StatefulWidget {
  const OfficeScene({
    super.key,
    required this.phase,
    required this.completeness,
    required this.total,
    required this.reduceMotion,
    this.comfort = false,
    this.onComfort,
    this.housingLabel = '房贷',
    this.carLabel = '车贷',
  });

  final DayPhase phase;
  final Completeness completeness;
  final Rational? total;
  final bool reduceMotion;
  final bool comfort;
  final VoidCallback? onComfort;
  final String housingLabel;
  final String carLabel;

  @override
  State<OfficeScene> createState() => _OfficeSceneState();
}

class _OfficeSceneState extends State<OfficeScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant OfficeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SceneMood get _mood {
    if (widget.completeness != Completeness.complete) return SceneMood.unknown;
    final total = widget.total;
    if (total == null) return SceneMood.unknown;
    return total.isNegative ? SceneMood.loss : SceneMood.gain;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: '手绘办公室：疲惫的打工人在工位前，硬币流向房子和车',
      button: widget.onComfort != null,
      child: AspectRatio(
        aspectRatio: 380 / 238,
        child: GestureDetector(
          onTap: widget.onComfort,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _OfficePainter(
                palette: palette,
                phase: widget.phase,
                mood: _mood,
                comfort: widget.comfort,
                timeMs: _controller.value * 8000,
                animate: !widget.reduceMotion,
                housingLabel: widget.housingLabel,
                carLabel: widget.carLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfficePainter extends CustomPainter {
  _OfficePainter({
    required this.palette,
    required this.phase,
    required this.mood,
    required this.comfort,
    required this.timeMs,
    required this.animate,
    required this.housingLabel,
    required this.carLabel,
  });

  final FjobPalette palette;
  final DayPhase phase;
  final SceneMood mood;
  final bool comfort;
  final double timeMs;
  final bool animate;
  final String housingLabel;
  final String carLabel;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 380, size.height / 238);
    final ink = palette.ink;
    final paper = palette.panel;
    final soft = palette.soft;
    final yellow = palette.yellow;
    final rose = palette.rose;
    final muted = palette.muted;

    final paint = Paint()..style = PaintingStyle.fill;
    void line(List<Offset> points, Color color, double width) {
      final stroke = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, stroke);
    }

    void box(Rect rect, Color fill, double radius) {
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      paint.color = fill;
      canvas.drawPath(path, paint);
      final stroke = Paint()
        ..color = ink
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, stroke);
    }

    void ellipse(double x, double y, double rx, double ry, Color fill,
        {bool outline = true}) {
      paint.color = fill;
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2), paint);
      if (outline) {
        final stroke = Paint()
          ..color = ink
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
          stroke,
        );
      }
    }

    void text(String value, double x, double y, double size,
        {Color? color}) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color ?? ink,
            fontSize: size,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, y));
    }

    // Room.
    paint.color = soft;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 380, 238), paint);
    paint.color = paper;
    canvas.drawRect(const Rect.fromLTWH(0, 187, 380, 51), paint);
    line(const [Offset(0, 187), Offset(380, 187)], muted, 1);

    // Window with weather.
    box(const Rect.fromLTWH(250, 17, 108, 91), paper, 7);
    line(const [Offset(304, 18), Offset(304, 108)], muted, 1);
    line(const [Offset(250, 64), Offset(358, 64)], muted, 1);
    switch (mood) {
      case SceneMood.gain:
        ellipse(329, 40, 13, 13, yellow);
        for (var index = 0; index < 8; index++) {
          final angle = index * math.pi / 4;
          line([
            Offset(329 + math.cos(angle) * 18, 40 + math.sin(angle) * 18),
            Offset(329 + math.cos(angle) * 22, 40 + math.sin(angle) * 22),
          ], muted, 1);
        }
      case SceneMood.loss:
        ellipse(280, 42, 17, 10, soft);
        ellipse(294, 37, 16, 13, soft);
        ellipse(307, 44, 18, 9, soft);
        for (var index = 0; index < 7; index++) {
          final offset = animate ? (timeMs * 0.025 + index * 8) % 45 : index * 6.0;
          line([
            Offset(263 + index * 12, 54 + offset),
            Offset(259 + index * 12, 62 + offset),
          ], muted, 1);
        }
      case SceneMood.unknown:
        ellipse(280, 44, 17, 11, paper);
        ellipse(294, 38, 16, 14, paper);
        ellipse(308, 46, 18, 10, paper);
        text('?', 288, 34, 14, color: muted);
    }

    // Sticky note and calendar.
    box(const Rect.fromLTWH(30, 21, 81, 66), yellow, 2);
    line(const [Offset(48, 22), Offset(89, 22)], rose, 5);
    text('上班致富', 41, 38, 14);
    text('暂无进展', 41, 60, 12, color: muted);
    box(const Rect.fromLTWH(124, 19, 36, 32), paper, 3);
    text('0001', 130, 34, 10);

    // House and car, using the shared bill illustrations.
    canvas.save();
    canvas.translate(-12, 109);
    canvas.scale(0.34, 0.58);
    DebtArtPainter(type: DebtArtType.house, palette: palette).paint(
      canvas,
      const Size(320, 165),
    );
    canvas.restore();
    canvas.save();
    canvas.translate(283, 158);
    canvas.scale(0.33, 0.33);
    DebtArtPainter(type: DebtArtType.car, palette: palette).paint(
      canvas,
      const Size(320, 165),
    );
    canvas.restore();
    text(housingLabel, 22, 214, 11);
    text(carLabel, 320, 214, 11);

    final resting = phase == DayPhase.restDay;
    final working = phase == DayPhase.working;
    final onBreak = phase == DayPhase.breakTime;

    ellipse(186, 206, 75, 8, soft, outline: false);

    if (resting) {
      box(const Rect.fromLTWH(162, 146, 43, 47), rose, 8);
      line(const [Offset(182, 190), Offset(182, 212)], ink, 4);
      line(const [Offset(162, 213), Offset(205, 213)], ink, 3);
      text('人呢？', 157, 112, 17, color: muted);
      text('今天轮到工位休息', 133, 132, 11, color: muted);
    } else {
      // Chair.
      box(const Rect.fromLTWH(162, 146, 43, 47), rose, 8);
      final bob = working && animate ? math.sin(timeMs * 0.004) * 1.6 : 3.0;
      canvas.save();
      canvas.translate(0, bob);
      // Body.
      ellipse(181, 143, 25, 35, paper);
      line(const [Offset(170, 169), Offset(160, 198), Offset(148, 199)], ink, 5);
      line(const [Offset(187, 171), Offset(202, 196), Offset(217, 196)], ink, 5);
      // Head.
      ellipse(178, 96, 30, 35, paper);
      final hair = Path()
        ..moveTo(149, 85)
        ..cubicTo(147, 56, 199, 48, 208, 85)
        ..lineTo(194, 75)
        ..lineTo(192, 86)
        ..lineTo(180, 76)
        ..lineTo(170, 85)
        ..lineTo(162, 78)
        ..close();
      paint.color = ink;
      canvas.drawPath(hair, paint);
      line(const [Offset(155, 69), Offset(152, 58), Offset(166, 65)], ink, 2);
      line(const [Offset(173, 61), Offset(182, 51), Offset(186, 61)], ink, 2);

      final happy = comfort || mood == SceneMood.gain;
      if (happy) {
        line(const [Offset(159, 98), Offset(164, 95), Offset(169, 98)], ink, 2);
        line(const [Offset(182, 98), Offset(187, 95), Offset(192, 98)], ink, 2);
      } else {
        line(const [Offset(157, 95), Offset(169, 96)], ink, 2);
        line(const [Offset(183, 96), Offset(195, 95)], ink, 2);
        ellipse(165, 101, 2, 3, ink, outline: false);
        ellipse(187, 101, 2, 3, ink, outline: false);
        line(const [Offset(158, 107), Offset(169, 108)], muted, 1);
        line(const [Offset(183, 108), Offset(194, 107)], muted, 1);
      }
      line(const [Offset(171, 117), Offset(182, 117)], ink, 1.5);
      line(const [Offset(171, 130), Offset(179, 138), Offset(186, 129)], muted, 1);
      line(
        const [Offset(179, 138), Offset(176, 157), Offset(183, 154), Offset(179, 138)],
        ink,
        2,
      );
      final tap = working && animate ? math.sin(timeMs * 0.025) * 2 : 0.0;
      if (working) {
        line([const Offset(158, 137), const Offset(146, 151), Offset(169, 157 + tap)], ink, 4);
        line([const Offset(199, 136), const Offset(214, 150), Offset(201, 157 - tap)], ink, 4);
      } else if (onBreak) {
        line(const [Offset(158, 137), Offset(146, 155), Offset(160, 166)], ink, 4);
        line(const [Offset(199, 136), Offset(214, 155), Offset(200, 166)], ink, 4);
      } else {
        line(const [Offset(158, 137), Offset(147, 165), Offset(160, 171)], ink, 4);
        line(const [Offset(199, 136), Offset(213, 165), Offset(200, 171)], ink, 4);
      }
      canvas.restore();
    }

    // Desk and monitor.
    box(const Rect.fromLTWH(91, 163, 209, 10), yellow, 2);
    line(const [Offset(102, 174), Offset(99, 215)], ink, 4);
    line(const [Offset(287, 174), Offset(291, 215)], ink, 4);
    box(const Rect.fromLTWH(220, 113, 63, 43), paper, 4);
    line(const [Offset(250, 157), Offset(250, 162)], ink, 3);
    line(const [Offset(232, 163), Offset(269, 163)], ink, 2);
    final rising = mood == SceneMood.gain;
    final trace = rising
        ? const [Offset(227, 144), Offset(237, 143), Offset(244, 135), Offset(253, 138), Offset(263, 125), Offset(277, 121)]
        : const [Offset(227, 123), Offset(238, 125), Offset(246, 132), Offset(254, 130), Offset(264, 144), Offset(277, 148)];
    line(trace, rising ? palette.positive : palette.negative, 2);

    // Mug with steam on breaks.
    box(const Rect.fromLTWH(120, 147, 15, 15), paper, 3);
    line(const [Offset(136, 149), Offset(141, 150), Offset(141, 157), Offset(136, 158)], ink, 1.5);
    if (!resting && (onBreak || !working)) {
      final drift = animate ? (timeMs * 0.02) % 6 : 0.0;
      line([Offset(124, 140 - drift), const Offset(122, 134), const Offset(125, 128)], muted, 1);
      line([Offset(131, 140 - drift), const Offset(133, 135), const Offset(131, 130)], muted, 1);
    }

    // Salary coins travelling to the house and the car.
    if (working && animate) {
      for (var index = 0; index < 5; index++) {
        final phaseValue = (timeMs * 0.00014 + index / 5) % 1;
        final fromLeft = index.isEven;
        final x = fromLeft ? 210 - phaseValue * 165 : 210 + phaseValue * 132;
        final y = 153 -
            math.sin(phaseValue * math.pi) * 38 +
            phaseValue * (fromLeft ? -4 : 39);
        ellipse(x, y, 6, 7, yellow);
        text('¥', x - 3, y - 5, 9);
      }
    }

    text(
      resting
          ? '贷款全勤奖'
          : working
              ? '收入运输中…'
              : onBreak
                  ? '午休暂停计薪'
                  : '月供夜班中',
      143,
      226,
      11,
      color: muted,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OfficePainter oldDelegate) =>
      oldDelegate.timeMs != timeMs ||
      oldDelegate.phase != phase ||
      oldDelegate.mood != mood ||
      oldDelegate.comfort != comfort ||
      oldDelegate.palette != palette ||
      oldDelegate.housingLabel != housingLabel ||
      oldDelegate.carLabel != carLabel;
}

/// Shared house/car doodle used by bills, cards and the office scene.
class DebtArtPainter extends CustomPainter {
  DebtArtPainter({required this.type, required this.palette});

  final DebtArtType type;
  final FjobPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 165);
    final ink = palette.ink;
    final panel = palette.panel;
    final soft = palette.soft;
    final yellow = palette.yellow;
    final rose = palette.rose;
    final muted = palette.muted;
    const weight = 2.8;

    void polygon(List<Offset> points, Color fill) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = ink
          ..strokeWidth = weight
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    void line(List<Offset> points, Color color, double width) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    void ellipse(double x, double y, double rx, double ry, Color fill,
        {bool outline = true}) {
      paintOval(canvas, x, y, rx, ry, fill, outline ? ink : null, weight);
    }

    paintOval(canvas, 160, 149, 99, 7, soft, null, weight);

    if (type == DebtArtType.house) {
      polygon(const [Offset(94, 61), Offset(222, 62), Offset(220, 145), Offset(96, 147)], panel);
      polygon(const [Offset(190, 41), Offset(189, 20), Offset(205, 21), Offset(207, 51)], yellow);
      polygon(const [Offset(78, 67), Offset(152, 18), Offset(237, 68), Offset(221, 74), Offset(152, 36), Offset(96, 75)], rose);
      polygon(const [Offset(111, 82), Offset(137, 81), Offset(138, 105), Offset(112, 106)], soft);
      polygon(const [Offset(175, 81), Offset(202, 82), Offset(200, 106), Offset(175, 105)], yellow);
      line(const [Offset(124, 82), Offset(124, 105)], ink, weight * 0.7);
      line(const [Offset(112, 94), Offset(137, 93)], ink, weight * 0.7);
      line(const [Offset(188, 82), Offset(188, 105)], ink, weight * 0.7);
      line(const [Offset(176, 94), Offset(201, 94)], ink, weight * 0.7);
      polygon(const [Offset(145, 113), Offset(169, 112), Offset(171, 146), Offset(145, 146)], yellow);
      ellipse(163, 131, 1.7, 1.7, ink, outline: false);
      line(const [Offset(88, 149), Offset(229, 149)], ink, weight * 0.7);
      line(const [Offset(77, 146), Offset(77, 128), Offset(69, 122)], muted, weight * 0.7);
      line(const [Offset(77, 138), Offset(87, 130)], muted, weight * 0.7);
    } else {
      final body = Path()
        ..moveTo(48, 101)
        ..quadraticBezierTo(48, 92, 76, 89)
        ..lineTo(101, 57)
        ..quadraticBezierTo(107, 50, 122, 51)
        ..lineTo(185, 53)
        ..quadraticBezierTo(198, 53, 217, 88)
        ..lineTo(249, 95)
        ..quadraticBezierTo(270, 98, 270, 114)
        ..lineTo(267, 130)
        ..quadraticBezierTo(175, 135, 55, 131)
        ..quadraticBezierTo(45, 130, 48, 101)
        ..close();
      canvas.drawPath(body, Paint()..color = rose);
      canvas.drawPath(
        body,
        Paint()
          ..color = ink
          ..strokeWidth = weight
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      polygon(const [Offset(87, 88), Offset(110, 62), Offset(145, 63), Offset(145, 89)], panel);
      polygon(const [Offset(155, 63), Offset(184, 64), Offset(204, 90), Offset(155, 89)], soft);
      line(const [Offset(151, 96), Offset(151, 125)], ink, weight * 0.7);
      line(const [Offset(163, 101), Offset(177, 101)], ink, weight * 0.8);
      line(const [Offset(63, 111), Offset(70, 111)], ink, weight);
      polygon(const [Offset(252, 100), Offset(268, 103), Offset(268, 114), Offset(254, 113)], yellow);
      line(const [Offset(263, 123), Offset(275, 123)], ink, weight);
      ellipse(94, 131, 19, 19, ink);
      ellipse(94, 131, 9, 9, panel);
      ellipse(227, 131, 19, 19, ink);
      ellipse(227, 131, 9, 9, panel);
      line(const [Offset(55, 150), Offset(270, 150)], muted, weight * 0.6);
    }
    canvas.restore();
  }

  static void paintOval(
    Canvas canvas,
    double x,
    double y,
    double rx,
    double ry,
    Color fill,
    Color? outline,
    double weight,
  ) {
    final rect = Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2);
    canvas.drawOval(rect, Paint()..color = fill);
    if (outline != null) {
      canvas.drawOval(
        rect,
        Paint()
          ..color = outline
          ..strokeWidth = weight
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DebtArtPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.palette != palette;
}

/// Small inline illustration for the housing/car bill cards.
class DebtArt extends StatelessWidget {
  const DebtArt({
    super.key,
    required this.type,
    this.height = 88,
  });

  final DebtArtType type;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      label: type == DebtArtType.house
          ? '粗线条手绘房子，歪歪的屋顶和亮着灯的窗户'
          : '粗线条手绘小车，圆润车身和两个圆轮',
      image: true,
      child: SizedBox(
        height: height,
        width: height * 320 / 165,
        child: CustomPaint(
          painter: DebtArtPainter(type: type, palette: palette),
        ),
      ),
    );
  }
}
