import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class RiderMarker extends StatelessWidget {
  final double heading;
  final double speedKmh;
  final bool isMoving;

  const RiderMarker({
    super.key,
    required this.heading,
    required this.speedKmh,
    required this.isMoving,
  });

  @override
  Widget build(BuildContext context) {
    final double headingRadians = (heading * (math.pi / 180));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live Speed Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.accentLightGreen,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMoving ? Icons.speed_rounded : Icons.pause_circle_filled_rounded,
                size: 10,
                color: AppTheme.accentLightGreen,
              ),
              const SizedBox(width: 3),
              Text(
                '${speedKmh.toStringAsFixed(0)} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Rotating Rider Icon & Pulsing Halo
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer semi-transparent ripple
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentLightGreen.withValues(alpha: 0.25),
              ),
            ),

            // Inner dark circle with neon ring
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryDark,
                border: Border.all(
                  color: AppTheme.accentLightGreen,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentLightGreen.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Transform.rotate(
                angle: headingRadians,
                child: const Icon(
                  Icons.navigation_rounded,
                  size: 18,
                  color: AppTheme.accentLightGreen,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
