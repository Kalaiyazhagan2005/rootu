import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Google Maps-style compass rose widget.
///
/// - Rotates so that the red North arrow always points to true North,
///   regardless of map rotation (passes `-mapBearing` radians to the transform).
/// - Fades out smoothly when the map is already aligned to North (bearing ≈ 0°).
/// - Tapping snaps the map bearing back to North (via [onNorthTap]).
/// - No emojis, no mock data.
class MapCompassWidget extends StatelessWidget {
  /// Current map rotation in degrees (clockwise = positive).
  /// Obtained from [MapCamera.rotation].
  final double mapBearingDegrees;

  /// Called when the user taps the compass to reset bearing to North.
  final VoidCallback onNorthTap;

  const MapCompassWidget({
    super.key,
    required this.mapBearingDegrees,
    required this.onNorthTap,
  });

  /// Normalize degrees into [0, 360).
  static double _normDeg(double deg) => ((deg % 360) + 360) % 360;

  @override
  Widget build(BuildContext context) {
    final double normalized = _normDeg(mapBearingDegrees);

    // Fade out when map is already north-facing (within ±3°).
    // Fully opaque at 15°+, fully transparent at 0–3°.
    final double opacity = normalized <= 3.0
        ? 0.0
        : normalized <= 15.0
            ? (normalized - 3.0) / 12.0
            : 1.0;

    if (opacity == 0.0) return const SizedBox.shrink();

    // Rotate so the red North arm points to geographic North.
    // Map bearing is clockwise, so we counter-rotate by -bearing.
    final double rotationRadians = -normalized * math.pi / 180.0;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: onNorthTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Transform.rotate(
              angle: rotationRadians,
              child: const _CompassRosePainter(),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pure CustomPaint compass rose — red North arm, grey South arm,
/// hairline cardinal ticks, and a bold 'N' label above the needle tip.
class _CompassRosePainter extends StatelessWidget {
  const _CompassRosePainter();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 32),
      painter: _CompassPainter(),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2;

    // --- Needle arms ---
    final double arrowHalfW = r * 0.22;
    final double arrowLen = r * 0.72;

    // North arm — red
    final northPath = Path()
      ..moveTo(center.dx, center.dy - arrowLen)      // tip
      ..lineTo(center.dx - arrowHalfW, center.dy)    // left base
      ..lineTo(center.dx + arrowHalfW, center.dy)    // right base
      ..close();
    canvas.drawPath(northPath, Paint()..color = const Color(0xFFE53935));

    // South arm — grey
    final southPath = Path()
      ..moveTo(center.dx, center.dy + arrowLen)      // tip
      ..lineTo(center.dx - arrowHalfW, center.dy)    // left base
      ..lineTo(center.dx + arrowHalfW, center.dy)    // right base
      ..close();
    canvas.drawPath(southPath, Paint()..color = const Color(0xFF9E9E9E));

    // --- Center dot ---
    canvas.drawCircle(
      center,
      r * 0.14,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      r * 0.09,
      Paint()..color = const Color(0xFF424242),
    );

    // --- 'N' label just above the North tip ---
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(
          color: Color(0xFFE53935),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - arrowLen - textPainter.height - 1,
    );
    textPainter.paint(canvas, labelOffset);
  }

  @override
  bool shouldRepaint(_CompassPainter oldDelegate) => false;
}

