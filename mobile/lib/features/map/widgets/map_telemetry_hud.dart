import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/gps_telemetry.dart';

/// Bottom telemetry HUD displaying live Speed, Altitude, Heading, and Map Following Mode
class MapTelemetryHud extends StatelessWidget {
  final GpsTelemetry? telemetry;
  final bool isFollowingUser;

  const MapTelemetryHud({
    super.key,
    required this.telemetry,
    required this.isFollowingUser,
  });

  @override
  Widget build(BuildContext context) {
    final speed = telemetry?.speedKmh ?? 0.0;
    final altitude = telemetry?.altitudeMeters ?? 0.0;
    final heading = telemetry?.heading ?? 0.0;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryDark.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.accentLightGreen.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildItem(
              label: 'SPEED',
              value: '${speed.toStringAsFixed(0)} km/h',
              icon: Icons.speed_rounded,
            ),
            _buildDivider(),
            _buildItem(
              label: 'ALTITUDE',
              value: '${altitude.toStringAsFixed(0)} m',
              icon: Icons.terrain_rounded,
            ),
            _buildDivider(),
            _buildItem(
              label: 'HEADING',
              value: '${heading.toStringAsFixed(0)}°',
              icon: Icons.explore_rounded,
            ),
            _buildDivider(),
            _buildItem(
              label: 'MODE',
              value: isFollowingUser ? 'FOLLOW' : 'FREE',
              icon: Icons.navigation_rounded,
              valueColor: isFollowingUser
                  ? AppTheme.accentLightGreen
                  : Colors.orangeAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 28,
      width: 1,
      color: Colors.white.withValues(alpha: 0.15),
    );
  }

  Widget _buildItem({
    required String label,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11,
              color: AppTheme.accentLightGreen,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

