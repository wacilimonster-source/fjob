/// The dashboard's hand-drawn icons, shared without changing their geometry.
library;

import 'package:flutter/material.dart';

class HandDrawnClockIcon extends StatelessWidget {
  const HandDrawnClockIcon({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
        size: Size.square(17),
        painter: _ClockIconPainter(),
      );
}

class _ClockIconPainter extends CustomPainter {
  const _ClockIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF586152)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.06);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.02,
        height: radius * 1.96,
      ),
      paint,
    );
    canvas.drawLine(Offset.zero, Offset(0, -radius * 0.55), paint);
    canvas.drawLine(
      Offset.zero,
      Offset(radius * 0.38, radius * 0.22),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ClockIconPainter oldDelegate) => false;
}

class HandDrawnBillIcon extends StatelessWidget {
  const HandDrawnBillIcon({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
        size: Size.square(17),
        painter: _BillIconPainter(),
      );
}

class _BillIconPainter extends CustomPainter {
  const _BillIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF586152)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = size.width * 0.22;
    final right = size.width * 0.78;
    final top = size.height * 0.16;
    final bottom = size.height * 0.84;
    final path = Path()
      ..moveTo(left, top)
      ..lineTo(right, top + 0.4)
      ..lineTo(right - 0.4, bottom - 2.2)
      ..lineTo((left + right) / 2, bottom)
      ..lineTo(left + 0.4, bottom - 2.2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.36),
      Offset(right - 2.6, size.height * 0.36),
      paint,
    );
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.52),
      Offset(right - 2.6, size.height * 0.52),
      paint,
    );
    canvas.drawLine(
      Offset(left + 2.6, size.height * 0.68),
      Offset((left + right) / 2, size.height * 0.68),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BillIconPainter oldDelegate) => false;
}
