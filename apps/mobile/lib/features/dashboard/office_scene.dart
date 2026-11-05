/// 粗线条、扁平奶油色的办公室小剧场。
///
/// 场景只消费展示状态（工作上下文、盈亏心情、瞬态控制器给出的
/// [ScenePresentation]），从不读取数据库或行情接口。动画时间由本地 8 秒
/// 环境控制器与外部瞬态控制器驱动，不参与任何账本金额计算。
library;

import 'dart:math' as math;

import 'package:finance_core/finance_core.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'scene_interaction_controller.dart';
import 'worker_painter.dart';

enum DebtArtType { house, car }

/// PAT-04 头肩触控区（场景逻辑坐标 380×238）。
final Rect headShoulderRect = Rect.fromLTWH(138, 44, 83, 125);

class OfficeScene extends StatefulWidget {
  const OfficeScene({
    super.key,
    required this.phase,
    required this.completeness,
    required this.total,
    required this.reduceMotion,
    this.controller,
    this.active = true,
    this.interactive = true,
    this.onRequestPat,
    this.showHousing = true,
    this.showCar = true,
    this.housingLabel = '房贷',
    this.carLabel = '车贷',
  });

  /// 稳态工作阶段；有 [controller] 时以其展示状态为准。
  final DayPhase phase;
  final Completeness completeness;
  final Rational? total;
  final bool reduceMotion;

  /// 瞬态控制器；预览与欢迎页传 null，仅绘制稳态。
  final SceneInteractionController? controller;

  /// 场景是否对用户可见；不可见时停止环境 ticker。
  final bool active;

  /// 是否启用头肩触控（欢迎页插画模式为 false）。
  final bool interactive;
  final VoidCallback? onRequestPat;

  /// 住房/车贷未配置时不画对应元素，硬币也不往那边飞。
  final bool showHousing;
  final bool showCar;
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
    _syncAmbient();
  }

  @override
  void didUpdateWidget(covariant OfficeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAmbient();
  }

  void _syncAmbient() {
    final shouldRun = widget.active && !widget.reduceMotion;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SceneMood get _localMood => sceneMoodOf(widget.completeness, widget.total);

  DayPhase get _phase => widget.controller?.phase ?? widget.phase;

  Presence get _presence =>
      _phase == DayPhase.working || _phase == DayPhase.breakTime
          ? Presence.atDesk
          : Presence.emptyDesk;

  bool get _departing =>
      widget.controller?.transient == TransientKind.departure;

  String get _semanticsLabel {
    final destinations = [
      if (widget.showHousing) widget.housingLabel,
      if (widget.showCar) widget.carLabel,
    ];
    if (widget.controller?.transient == TransientKind.pat) {
      return '手绘办公室：人物被轻轻拍肩，抬眼回应';
    }
    if (_departing) return '手绘办公室：人物正在提包离开工位';
    return switch (_presence) {
      Presence.atDesk when _phase == DayPhase.breakTime =>
        '手绘办公室：人物在午休中',
      Presence.atDesk => destinations.isEmpty
          ? '手绘办公室：打工人在工位上'
          : '手绘办公室：打工人在工位上，硬币流向${destinations.join('和')}',
      Presence.emptyDesk => switch (_phase) {
          DayPhase.afterShift => '空工位，人物已下班',
          DayPhase.beforeShift => '空工位，还没到岗',
          DayPhase.restDay => '空工位，今天休息',
          _ => '空工位，排班待确认',
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final controller = widget.controller;
    // 瞬态与环境循环都通过同一 Listenable 驱动重建，语义标签随状态更新。
    return AnimatedBuilder(
      animation: controller == null
          ? _controller
          : Listenable.merge([_controller, controller]),
      builder: (context, _) {
        controller?.reportAmbient(
          timeMs: _controller.value * 8000,
          animating: _controller.isAnimating,
        );
        final presentation =
            controller?.presentation ?? _steadyPresentation();
        return Semantics(
          label: _semanticsLabel,
          container: true,
          // 头肩按钮保持独立语义节点，不并入场景描述（A11Y-01）。
          explicitChildNodes: true,
          child: AspectRatio(
            aspectRatio: 380 / 238,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = width * 238 / 380;
                final canPat =
                    widget.interactive && presentation.canPat;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _OfficePainter(
                          palette: palette,
                          presentation: presentation,
                          showHousing: widget.showHousing,
                          showCar: widget.showCar,
                          housingLabel: widget.housingLabel,
                          carLabel: widget.carLabel,
                        ),
                      ),
                    ),
                    if (canPat)
                      Positioned(
                        left: headShoulderRect.left / 380 * width,
                        top: headShoulderRect.top / 238 * height,
                        width: headShoulderRect.width / 380 * width,
                        height: headShoulderRect.height / 238 * height,
                        child: Semantics(
                          button: true,
                          label: '拍拍他，给正在工位上的他一点安慰',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onRequestPat,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  ScenePresentation _steadyPresentation() {
    final animate = widget.active && !widget.reduceMotion;
    return ScenePresentation(
      phase: widget.phase,
      presence: _presence,
      mood: _localMood,
      transient: TransientKind.idle,
      progress: 0,
      canPat: false,
      reduceMotion: widget.reduceMotion,
      ambientMs: animate ? _controller.value * 8000 : 0,
      animateAmbient: animate,
    );
  }
}

class _OfficePainter extends CustomPainter {
  _OfficePainter({
    required this.palette,
    required this.presentation,
    required this.showHousing,
    required this.showCar,
    required this.housingLabel,
    required this.carLabel,
  });

  final FjobPalette palette;
  final ScenePresentation presentation;
  final bool showHousing;
  final bool showCar;
  final String housingLabel;
  final String carLabel;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 380, size.height / 238);
    // OUT-03：图层外使用场景边界裁剪，出场后不残留。
    canvas.clipRect(const Rect.fromLTWH(0, 0, 380, 238));
    final ink = palette.ink;
    final paper = palette.panel;
    final soft = palette.soft;
    final yellow = palette.yellow;
    final rose = palette.rose;
    final muted = palette.muted;
    final mood = presentation.mood;
    final phase = presentation.phase;
    final frame = WorkerFrame.resolve(
      presentation: presentation,
      ambientMs: presentation.ambientMs,
      animate: presentation.animateAmbient,
    );
    final timeMs = presentation.ambientMs;
    final animate = presentation.animateAmbient;

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
      DebtArtPainter.paintOval(canvas, x, y, rx, ry, fill,
          outline ? ink : null, 1.8);
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

    final empty = !frame.present;
    final monitorAsleep = empty ||
        (presentation.transient == TransientKind.departure &&
            presentation.progress * 2200 >= 560);

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

    // Sticky note: working copy, or the empty-desk status per phase.
    box(const Rect.fromLTWH(30, 21, 81, 66), yellow, 2);
    line(const [Offset(48, 22), Offset(89, 22)], rose, 5);
    if (empty) {
      final note = switch (phase) {
        DayPhase.afterShift => '已下班',
        DayPhase.beforeShift => '还没到岗',
        DayPhase.restDay => '今日休息',
        _ => '排班待确认',
      };
      text(note, 40, 46, note.length > 4 ? 11 : 14);
      text('工位暂停营业', 40, 68, 11, color: muted);
    } else {
      text('上班致富', 41, 38, 14);
      text('暂无进展', 41, 60, 12, color: muted);
    }
    box(const Rect.fromLTWH(124, 19, 36, 32), paper, 3);
    text('0001', 130, 34, 10);

    // House and car, using the shared bill illustrations.
    if (showHousing) {
      canvas.save();
      canvas.translate(-12, 109);
      canvas.scale(0.34, 0.58);
      DebtArtPainter(type: DebtArtType.house, palette: palette).paint(
        canvas,
        const Size(320, 165),
      );
      canvas.restore();
      text(housingLabel, 22, 214, 11);
    }
    if (showCar) {
      canvas.save();
      canvas.translate(283, 158);
      canvas.scale(0.33, 0.33);
      DebtArtPainter(type: DebtArtType.car, palette: palette).paint(
        canvas,
        const Size(320, 165),
      );
      canvas.restore();
      text(carLabel, 320, 214, 11);
    }

    ellipse(186, 206, 75, 8, soft, outline: false);

    // Chair; it leans back on the empty desk and settles after the walk-out.
    final chairTilted = empty ||
        (presentation.transient == TransientKind.departure &&
            presentation.progress * 2200 > 1900);
    canvas.save();
    canvas.translate(182, 190);
    if (chairTilted) canvas.rotate(0.105);
    box(const Rect.fromLTWH(-20, -44, 43, 47), rose, 8);
    line(const [Offset(0, 0), Offset(0, 22)], ink, 4);
    line(const [Offset(-20, 23), Offset(23, 23)], ink, 3);
    canvas.restore();

    final worker = WorkerPainter(palette: palette);
    // Seated (and mid-stand) stay behind the desk; the walk-out is foreground.
    final behindDesk = frame.present && (frame.seated || frame.walk <= 0);
    if (behindDesk) worker.paint(canvas, frame);

    // Desk and monitor.
    box(const Rect.fromLTWH(91, 163, 209, 10), yellow, 2);
    line(const [Offset(102, 174), Offset(99, 215)], ink, 4);
    line(const [Offset(287, 174), Offset(291, 215)], ink, 4);
    box(const Rect.fromLTWH(220, 113, 63, 43), monitorAsleep ? soft : paper, 4);
    line(const [Offset(250, 157), Offset(250, 162)], ink, 3);
    line(const [Offset(232, 163), Offset(269, 163)], ink, 2);
    if (monitorAsleep) {
      // 待机：一条短线。
      line(const [Offset(243, 137), Offset(258, 137)], muted, 2);
    } else {
      final rising = mood == SceneMood.gain;
      final trace = rising
          ? const [Offset(227, 144), Offset(237, 143), Offset(244, 135), Offset(253, 138), Offset(263, 125), Offset(277, 121)]
          : const [Offset(227, 123), Offset(238, 125), Offset(246, 132), Offset(254, 130), Offset(264, 144), Offset(277, 148)];
      line(trace, rising ? palette.positive : palette.negative, 2);
    }

    // Mug, with steam while the worker is around.
    box(const Rect.fromLTWH(120, 147, 15, 15), paper, 3);
    line(const [Offset(136, 149), Offset(141, 150), Offset(141, 157), Offset(136, 158)], ink, 1.5);
    if (frame.present && presentation.transient != TransientKind.departure) {
      final drift = animate ? (timeMs * 0.02) % 6 : 0.0;
      line([Offset(124, 140 - drift), const Offset(122, 134), const Offset(125, 128)], muted, 1);
      line([Offset(131, 140 - drift), const Offset(133, 135), const Offset(131, 130)], muted, 1);
    }

    // Salary coins travelling to the visible destinations.
    final departureMs = presentation.transient == TransientKind.departure
        ? presentation.progress * 2200
        : null;
    final coinsActive = departureMs != null
        ? departureMs < 180
        : phase == DayPhase.working && frame.present;
    if (coinsActive && (showHousing || showCar)) {
      final destinations = <List<double>>[
        if (showHousing) const [45, 149],
        if (showCar) const [342, 192],
      ];
      for (var index = 0; index < 4; index++) {
        final a = ((animate ? timeMs * 0.00014 : 0) + index / 4) % 1;
        final target = destinations[index % destinations.length];
        final x = 210 + (target[0] - 210) * a;
        final y = 153 +
            (target[1] - 153) * a -
            math.sin(a * math.pi) * 38;
        final alpha = departureMs == null ? 1.0 : (1 - departureMs / 180).clamp(0.0, 1.0);
        canvas.save();
        canvas.scale(1);
        DebtArtPainter.paintOval(
          canvas,
          x,
          y,
          6,
          7,
          yellow,
          alpha < 1 ? ink.withValues(alpha: alpha) : ink,
          1.8,
        );
        text('¥', x - 3, y - 5, 9, color: ink.withValues(alpha: alpha));
        canvas.restore();
      }
    }

    // Walk-out in front of desk, house, car and coins.
    if (frame.present && !behindDesk) {
      worker.paint(canvas, frame);
      if (frame.walking) {
        // 离场速度线，最多两笔。
        final speedAlpha = (1 - frame.walk).clamp(0.0, 1.0);
        final speed = Paint()
          ..color = muted.withValues(alpha: speedAlpha * 0.8)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(frame.actorX - 30, 186),
          Offset(frame.actorX - 16, 186),
          speed,
        );
        canvas.drawLine(
          Offset(frame.actorX - 36, 198),
          Offset(frame.actorX - 19, 198),
          speed,
        );
      }
    }

    final hasDebt = showHousing || showCar;
    text(
      switch (presentation.transient) {
        TransientKind.departure => '工位正在交还给空气',
        _ => switch (phase) {
            DayPhase.working => hasDebt ? '收入运输中…' : '计薪中',
            DayPhase.breakTime => '午休暂停计薪',
            DayPhase.afterShift => '今日工位，暂停营业。',
            DayPhase.beforeShift => '工位就绪，等人来',
            DayPhase.restDay => '今天工位休息',
            DayPhase.unknown => '排班待确认',
          },
      },
      143,
      226,
      11,
      color: muted,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OfficePainter oldDelegate) =>
      oldDelegate.presentation != presentation ||
      oldDelegate.palette != palette ||
      oldDelegate.showHousing != showHousing ||
      oldDelegate.showCar != showCar ||
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
