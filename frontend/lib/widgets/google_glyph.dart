import 'package:flutter/material.dart';

/// Original four-colour "G" mark drawn with a painter.
///
/// Drawn locally instead of shipping a brand asset: the button is not wired to
/// Google Sign-In yet (it needs OAuth client IDs), so nothing here should look
/// like a finished integration.
class GoogleGlyph extends StatelessWidget {
  final double size;
  const GoogleGlyph({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Invalidate runtime palette when Light/Dark changes.
    return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GoogleGlyphPainter()));
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final Offset center = Offset(w / 2, w / 2);
    final Rect rect = Rect.fromCircle(center: center, radius: w * 0.40);
    final double stroke = w * 0.21;

    Paint arc(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..color = color;

    canvas.drawArc(
        rect, -3.20, 2.65, false, arc(const Color(0xFFEA4335))); // red - top
    canvas.drawArc(
        rect, 1.78, 1.32, false, arc(const Color(0xFFFBBC05))); // yellow - left
    canvas.drawArc(rect, 0.42, 0.95, false,
        arc(const Color(0xFF34A853))); // green - bottom
    canvas.drawArc(
        rect, -0.95, 0.70, false, arc(const Color(0xFF4285F4))); // blue - right

    // Blue horizontal bar (the "mouth" of the G).
    canvas.drawRect(
      Rect.fromLTWH(w * 0.50, w * 0.44, w * 0.34, stroke * 0.82),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
