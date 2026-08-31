import 'package:flutter/material.dart';

import '../models/journal_entry.dart';

class SessionScene extends StatelessWidget {
  const SessionScene({
    required this.phase,
    required this.accent,
    this.compact = false,
    super.key,
  });

  final SessionPhase phase;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      height: compact ? 124 : 210,
      decoration: BoxDecoration(
        color: Color.lerp(const Color(0xFF242721), accent, .34),
        borderRadius: BorderRadius.circular(compact ? 20 : 28),
        border: Border.all(color: const Color(0x2AFFFFFF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 19 : 27),
        child: CustomPaint(
          painter: _SessionScenePainter(
            phase: phase,
            accent: accent,
            compact: compact,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _SessionScenePainter extends CustomPainter {
  const _SessionScenePainter({
    required this.phase,
    required this.accent,
    required this.compact,
  });

  final SessionPhase phase;
  final Color accent;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final inkColor = Color.lerp(const Color(0xFFD9DDCF), accent, .16)!;
    final ink = Paint()
      ..color = inkColor.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.5 : 2
      ..strokeCap = StrokeCap.square;
    final fill = Paint()..color = inkColor.withValues(alpha: .68);
    final floorY = size.height * .79;
    canvas.drawLine(Offset(0, floorY), Offset(size.width, floorY), ink);

    final deskLeft = size.width * .46;
    final deskTop = floorY - size.height * .17;
    canvas.drawRect(
      Rect.fromLTWH(deskLeft, deskTop, size.width * .22, compact ? 3 : 4),
      fill,
    );
    canvas.drawLine(
      Offset(deskLeft + size.width * .025, deskTop),
      Offset(deskLeft + size.width * .025, floorY),
      ink,
    );
    canvas.drawLine(
      Offset(deskLeft + size.width * .19, deskTop),
      Offset(deskLeft + size.width * .19, floorY),
      ink,
    );

    final person = Rect.fromLTWH(
      size.width * .54,
      deskTop - size.height * .17,
      compact ? 19 : 27,
      compact ? 20 : 29,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(person, const Radius.circular(4)),
      ink,
    );
    canvas.drawCircle(person.centerLeft + const Offset(6, -1), 1.7, fill);
    canvas.drawCircle(person.centerRight + const Offset(-6, -1), 1.7, fill);

    final lampBase = Offset(size.width * .35, floorY - 2);
    canvas.drawRect(
      Rect.fromCenter(center: lampBase, width: compact ? 24 : 34, height: 4),
      fill,
    );
    final lampTop = Offset(size.width * .34, deskTop - size.height * .16);
    canvas.drawLine(lampBase, Offset(size.width * .32, deskTop), ink);
    canvas.drawLine(Offset(size.width * .32, deskTop), lampTop, ink);
    canvas.drawLine(lampTop, lampTop + const Offset(15, 10), ink);

    if (phase != SessionPhase.arrival) {
      final glowAlpha = phase == SessionPhase.reflection ? .30 : .20;
      final glow = Paint()
        ..shader =
            RadialGradient(
              colors: [
                accent.withValues(alpha: glowAlpha),
                accent.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: lampTop + const Offset(12, 13),
                radius: compact ? 38 : 58,
              ),
            );
      canvas.drawCircle(
        lampTop + const Offset(12, 13),
        compact ? 38 : 58,
        glow,
      );
    }

    if (phase == SessionPhase.reflection) {
      final star = Offset(size.width * .78, size.height * .25);
      canvas.drawCircle(star, compact ? 2 : 3, fill);
      canvas.drawLine(
        star - const Offset(7, 0),
        star + const Offset(7, 0),
        ink,
      );
      canvas.drawLine(
        star - const Offset(0, 7),
        star + const Offset(0, 7),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SessionScenePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.accent != accent ||
      oldDelegate.compact != compact;
}
