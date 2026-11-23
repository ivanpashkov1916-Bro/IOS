/// Похвала по центру экрана: хлопушка с разлетающимися звёздочками
/// и крупный текст. Показывается поверх всего на ~2,5 секунды
/// (вместо маленького снэкбара внизу).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class PraiseOverlay {
  PraiseOverlay._();

  static void show(BuildContext context, String text) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PraiseFireworks(
        text: text,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _PraiseFireworks extends StatefulWidget {
  final String text;
  final VoidCallback onDone;
  const _PraiseFireworks({required this.text, required this.onDone});

  @override
  State<_PraiseFireworks> createState() => _PraiseFireworksState();
}

class _PraiseFireworksState extends State<_PraiseFireworks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )
      ..forward()
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // Текст появляется с лёгким «пружинным» масштабом в первые 40%.
          final textT = (t / 0.4).clamp(0.0, 1.0).toDouble();
          final scale = Curves.elasticOut.transform(textT);
          // В конце всё плавно гаснет.
          final fade =
              t > 0.8 ? (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0).toDouble() : 1.0;
          return Opacity(
            opacity: fade,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: CustomPaint(
                        painter: _FireworksPainter(t),
                        child: const Center(
                          child: Icon(Icons.celebration,
                              color: AppTheme.warn, size: 72),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.6)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: Text(
                          widget.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Разлетающиеся звёздочки-хлопушка: 14 звёзд по кругу от центра.
class _FireworksPainter extends CustomPainter {
  final double t; // 0..1
  _FireworksPainter(this.t);

  static const _colors = [
    AppTheme.accent,
    AppTheme.warn,
    AppTheme.done,
    AppTheme.daily,
    AppTheme.danger,
  ];

  Path _star(Offset c, double r, double rot) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = rot - math.pi / 2 + i * math.pi / 5;
      final o = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Стартовая вспышка.
    if (t < 0.25) {
      final flash = Paint()
        ..color = AppTheme.warn.withOpacity((0.5 * (1 - t / 0.25)))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, 40 + t * 200, flash);
    }
    final burst = Curves.easeOut.transform(t);
    for (var i = 0; i < 14; i++) {
      final angle = i * 2 * math.pi / 14 + (i.isEven ? 0.0 : 0.22);
      final dist = 30 + burst * 95;
      final pos = Offset(
        center.dx + dist * math.cos(angle),
        center.dy + dist * math.sin(angle),
      );
      final paint = Paint()
        ..color = _colors[i % _colors.length]
            .withOpacity((1 - t).clamp(0.0, 1.0).toDouble());
      final r = 9 * (1 - t * 0.4);
      canvas.drawPath(_star(pos, r, t * 3 + i), paint);
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) => old.t != t;
}
