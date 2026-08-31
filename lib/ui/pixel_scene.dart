import 'package:flutter/material.dart';

class PixelScene extends StatelessWidget {
  const PixelScene({
    required this.wordCount,
    required this.targetWordCount,
    required this.isThinking,
    super.key,
  });
  final int wordCount;
  final int targetWordCount;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    final percent = targetWordCount == 0
        ? 0
        : ((wordCount / targetWordCount) * 100).clamp(0, 100).round();
    return AspectRatio(
      aspectRatio: 1.04,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFB7C1B6),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF7D887B)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x25000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _PixelRoomPainter(
                    progress: percent / 100,
                    isThinking: isThinking,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFF353A32),
                    fontFamily: 'Georgia',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sotto', style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 8),
                      Text(
                        '$wordCount / $targetWordCount words',
                        style: const TextStyle(
                          fontSize: 22,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('$percent%', style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF687266),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.menu,
                    size: 18,
                    color: Color(0xFF394037),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelRoomPainter extends CustomPainter {
  const _PixelRoomPainter({required this.progress, required this.isThinking});
  final double progress;
  final bool isThinking;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF3B4138)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.square;
    final fill = Paint()..color = const Color(0xFF3B4138);
    final floorY = size.height * .86;
    canvas.drawLine(Offset(0, floorY), Offset(size.width, floorY), ink);
    canvas.drawRect(Rect.fromLTWH(0, floorY + 3, size.width, 2), fill);

    final window = Rect.fromLTWH(
      size.width * .61,
      size.height * .55,
      size.width * .12,
      size.height * .17,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(size.width * .06)),
      ink,
    );
    canvas.drawRect(
      window.deflate(5),
      Paint()..color = const Color(0x22FFF6CA),
    );
    canvas.drawLine(window.centerLeft, window.centerRight, ink);
    canvas.drawLine(window.topCenter, window.bottomCenter, ink);

    final shelfX = size.width * .82;
    final shelfTop = size.height * .58;
    canvas.drawRect(
      Rect.fromLTWH(shelfX, shelfTop, size.width * .18, size.height * .23),
      ink,
    );
    for (var row = 1; row < 3; row++) {
      final y = shelfTop + row * size.height * .075;
      canvas.drawLine(Offset(shelfX, y), Offset(size.width, y), ink);
    }
    for (var book = 1; book < 6; book++) {
      final x = shelfX + book * size.width * .029;
      canvas.drawLine(
        Offset(x, shelfTop + 4),
        Offset(x, shelfTop + size.height * .07),
        ink,
      );
    }

    final deskY = floorY - size.height * .08;
    canvas.drawRect(
      Rect.fromLTWH(size.width * .43, deskY, size.width * .17, 5),
      fill,
    );
    canvas.drawLine(
      Offset(size.width * .46, deskY),
      Offset(size.width * .46, floorY),
      ink,
    );
    canvas.drawLine(
      Offset(size.width * .57, deskY),
      Offset(size.width * .57, floorY),
      ink,
    );

    final botX = size.width * .49;
    final botY = deskY - size.height * .075;
    canvas.drawRect(
      Rect.fromLTWH(botX, botY, size.width * .065, size.height * .065),
      ink,
    );
    canvas.drawCircle(Offset(botX + 7, botY + 9), 1.8, fill);
    canvas.drawCircle(Offset(botX + 18, botY + 9), 1.8, fill);
    canvas.drawLine(
      Offset(botX + 3, botY + size.height * .07),
      Offset(botX - 6, deskY),
      ink,
    );
    canvas.drawLine(
      Offset(botX + size.width * .06, botY + size.height * .07),
      Offset(botX + size.width * .08, deskY),
      ink,
    );

    final lampBase = Offset(size.width * .36, floorY - 3);
    canvas.drawRect(
      Rect.fromCenter(center: lampBase, width: 34, height: 5),
      fill,
    );
    final lampTop = Offset(size.width * .34, size.height * .66);
    canvas.drawLine(lampBase, Offset(size.width * .33, size.height * .73), ink);
    canvas.drawLine(Offset(size.width * .33, size.height * .73), lampTop, ink);
    canvas.drawLine(lampTop, Offset(lampTop.dx + 16, lampTop.dy + 12), ink);
    if (progress > .25) {
      canvas.drawCircle(
        Offset(lampTop.dx + 13, lampTop.dy + 15),
        28,
        Paint()
          ..color = Color.fromARGB((32 + progress * 40).round(), 255, 245, 187),
      );
    }
    if (isThinking) {
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(
          Rect.fromLTWH(botX + 8 + i * 6, botY - 12 - (i.isEven ? 2 : 0), 3, 3),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelRoomPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isThinking != isThinking;
}
