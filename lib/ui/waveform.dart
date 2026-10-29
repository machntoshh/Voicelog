import 'package:flutter/material.dart';

import 'theme.dart';

/// Rounded vertical bars; [levels] are 0–1. Bars left of [progress] (0–1)
/// use [activeColor].
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.levels,
    this.progress = 1,
    this.activeColor = VL.text,
    this.inactiveColor = VL.textFaint,
    this.barWidth = 3,
    this.gap = 2,
    this.alignRight = false,
  });

  final List<double> levels;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double gap;

  /// Live mode: newest level at the right edge, older ones scroll left.
  final bool alignRight;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = barWidth + gap;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final List<double> bars;
    if (alignRight) {
      final count = (size.width / slot).floor();
      bars = levels.length > count ? levels.sublist(levels.length - count) : levels;
    } else {
      bars = levels;
    }
    final step = alignRight ? slot : size.width / bars.length;
    final startX = alignRight ? size.width - bars.length * slot : 0.0;
    final mid = size.height / 2;
    for (var i = 0; i < bars.length; i++) {
      final x = startX + i * step + step / 2;
      final h = (bars[i].clamp(0.0, 1.0) * (size.height - barWidth)).clamp(barWidth, size.height);
      paint
        ..color = (i + 0.5) / bars.length <= progress ? activeColor : inactiveColor
        ..strokeWidth = alignRight ? barWidth : (step - gap).clamp(1.0, barWidth);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) => true;
}
