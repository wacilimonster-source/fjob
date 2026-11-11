import 'package:flutter/material.dart';

import 'theme.dart';

/// Small paper-note brand mark, drawn in code rather than from concept art.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: '今日又白干',
        child: SizedBox.square(
          dimension: size,
          child:
              CustomPaint(painter: BrandMarkPainter(palette: context.palette)),
        ),
      );
}

/// Can also be painted into a 16/32 px image by the host's icon exporter.
/// File encoding and platform icon registration belong to the host, not UI.
class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({required this.palette});

  final FjobPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 32;
    canvas.save();
    canvas.translate(
        (size.width - 32 * scale) / 2, (size.height - 32 * scale) / 2);
    canvas.scale(scale);
    final note = Path()
      ..moveTo(4, 3)
      ..lineTo(28, 4)
      ..lineTo(27, 28)
      ..lineTo(3, 27)
      ..close();
    final stroke = Paint()
      ..color = palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(note, Paint()..color = palette.yellow);
    canvas.drawPath(note, stroke);
    canvas.drawLine(const Offset(8, 13), const Offset(13, 13.5), stroke);
    canvas.drawLine(const Offset(19, 13.5), const Offset(24, 13), stroke);
    canvas.drawLine(const Offset(13, 21), const Offset(19, 21), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BrandMarkPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
