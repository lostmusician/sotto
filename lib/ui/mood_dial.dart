import 'dart:math' as math;

import 'package:flutter/material.dart';

class MoodPalette {
  const MoodPalette._();

  static Color colorFor(double angle, double intensity) {
    final hue = ((18 + angle.clamp(0, 1) * 312) % 360).toDouble();
    final saturation = .24 + intensity.clamp(0, 1) * .32;
    final value = .88 - intensity.clamp(0, 1) * .16;
    return HSVColor.fromAHSV(1, hue, saturation, value).toColor();
  }

  static String toneLabel(double angle) {
    const labels = [
      'warm',
      'bright',
      'open',
      'quiet',
      'blue',
      'tender',
      'restless',
      'grounded',
    ];
    return labels[(angle.clamp(0, .999) * labels.length).floor()];
  }
}

class MoodDial extends StatelessWidget {
  const MoodDial({
    required this.angle,
    required this.intensity,
    required this.onChanged,
    super.key,
  });

  final double angle;
  final double intensity;
  final void Function(double angle, double intensity) onChanged;

  void _updateFromPosition(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    final delta = localPosition - center;
    final maxRadius = size.shortestSide / 2;
    final nextIntensity = (delta.distance / maxRadius).clamp(0.08, 1.0);
    final radians = math.atan2(delta.dy, delta.dx);
    final nextAngle = ((radians / (2 * math.pi)) + 1) % 1;
    onChanged(nextAngle, nextIntensity);
  }

  @override
  Widget build(BuildContext context) {
    final color = MoodPalette.colorFor(angle, intensity);
    return Semantics(
      container: true,
      label:
          'Mood dial. ${MoodPalette.toneLabel(angle)} tone, ${(intensity * 100).round()} percent intensity.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330, maxHeight: 330),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    key: const Key('mood-dial'),
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (details) =>
                        _updateFromPosition(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _updateFromPosition(details.localPosition, size),
                    child: CustomPaint(
                      painter: _MoodDialPainter(
                        angle: angle,
                        intensity: intensity,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '${MoodPalette.toneLabel(angle)} · ${(intensity * 100).round()}%',
            style: TextStyle(
              color: color.withValues(alpha: .95),
              fontSize: 14,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Semantics(
                  label: 'Emotional tone',
                  child: Slider(
                    key: const Key('mood-tone-slider'),
                    value: angle,
                    onChanged: (value) => onChanged(value, intensity),
                  ),
                ),
                Semantics(
                  label: 'Emotional intensity',
                  child: Slider(
                    key: const Key('mood-intensity-slider'),
                    value: intensity,
                    onChanged: (value) => onChanged(angle, value),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodDialPainter extends CustomPainter {
  const _MoodDialPainter({required this.angle, required this.intensity});

  final double angle;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const stops = [0.0, .125, .25, .375, .5, .625, .75, .875, 1.0];
    final colors = [
      for (final stop in stops) MoodPalette.colorFor(stop % 1, .72),
    ];
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..shader = SweepGradient(colors: colors, stops: stops).createShader(rect);
    canvas.drawCircle(center, radius - 12, ring);

    final inner = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF8F5EE),
          MoodPalette.colorFor(angle, intensity).withValues(alpha: .34),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius - 26));
    canvas.drawCircle(center, radius - 26, inner);

    final theta = angle * 2 * math.pi;
    final markerRadius = (radius - 30) * intensity;
    final marker =
        center + Offset(math.cos(theta), math.sin(theta)) * markerRadius;
    canvas.drawCircle(
      marker,
      14,
      Paint()
        ..color = const Color(0xFFFAF7EF)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      marker,
      14,
      Paint()
        ..color = const Color(0xFF34372F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      marker,
      5,
      Paint()..color = MoodPalette.colorFor(angle, 1),
    );
  }

  @override
  bool shouldRepaint(covariant _MoodDialPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.intensity != intensity;
}
