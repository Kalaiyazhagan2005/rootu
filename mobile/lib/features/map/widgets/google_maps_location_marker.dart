import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Iconic Google Maps-style user location marker featuring:
/// 1. A pulsing Google Blue dot (#4285F4) with a solid white bezel and subtle drop shadow.
/// 2. A dynamic translucent directional flashlight / beam cone indicating device orientation.
/// 3. Speed-adaptive beam aperture (narrowing at higher velocities).
/// 4. Compact speed telemetry pill when moving.
class GoogleMapsLocationMarker extends StatefulWidget {
  final double heading;
  final double speedKmh;
  final bool isMoving;

  const GoogleMapsLocationMarker({
    super.key,
    required this.heading,
    required this.speedKmh,
    required this.isMoving,
  });

  @override
  State<GoogleMapsLocationMarker> createState() => _GoogleMapsLocationMarkerState();
}

class _GoogleMapsLocationMarkerState extends State<GoogleMapsLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScaleAnimation;
  late final Animation<double> _pulseAlphaAnimation;

  static const Color googleBlue = Color(0xFF4285F4);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseScaleAnimation = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOutQuad,
      ),
    );

    _pulseAlphaAnimation = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeOutQuad,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic beam cone aperture: narrows from 60° when walking/stationary to 42° at driving speed
    final double coneApertureDeg = widget.speedKmh > 15.0 ? 42.0 : 60.0;

    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Dynamic Directional Flashlight / Beam Cone Painter
          CustomPaint(
            size: const Size(140, 140),
            painter: _DirectionalBeamPainter(
              headingDegrees: widget.heading,
              coneApertureDegrees: coneApertureDeg,
              beamColor: googleBlue,
            ),
          ),

          // 2. Animated Pulsing Halo Ring
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseScaleAnimation.value,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: googleBlue.withValues(alpha: _pulseAlphaAnimation.value),
                  ),
                ),
              );
            },
          ),

          // 3. Crisp Google Blue Core Dot with Solid White Bezel
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: googleBlue,
              border: Border.all(
                color: Colors.white,
                width: 2.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
          ),

          // 4. Floating Speed Pill (displayed when actively moving > 2.0 km/h)
          if (widget.isMoving && widget.speedKmh >= 2.0)
            Positioned(
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2326),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: googleBlue.withValues(alpha: 0.8),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.speed_rounded,
                      size: 10,
                      color: googleBlue,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${widget.speedKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter rendering a smooth radial gradient fan / beam cone pointing along the heading azimuth
class _DirectionalBeamPainter extends CustomPainter {
  final double headingDegrees;
  final double coneApertureDegrees;
  final Color beamColor;

  _DirectionalBeamPainter({
    required this.headingDegrees,
    required this.coneApertureDegrees,
    required this.beamColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    const double beamRadius = 56.0;

    final double coneApertureRad = coneApertureDegrees * (math.pi / 180.0);
    final double headingRad = headingDegrees * (math.pi / 180.0);

    // In canvas trigonometry: 0 rad points right (+X).
    // North is top (-Y), which is -pi/2 rad.
    // Beam start angle sweeps symmetrically around North + heading:
    final double startAngleRad = -math.pi / 2.0 - (coneApertureRad / 2.0) + headingRad;

    final Paint beamPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          beamColor.withValues(alpha: 0.42),
          beamColor.withValues(alpha: 0.20),
          beamColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: beamRadius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: beamRadius),
      startAngleRad,
      coneApertureRad,
      true, // draw pie wedge back to center
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionalBeamPainter oldDelegate) {
    return oldDelegate.headingDegrees != headingDegrees ||
        oldDelegate.coneApertureDegrees != coneApertureDegrees ||
        oldDelegate.beamColor != beamColor;
  }
}

