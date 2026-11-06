import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/gps_telemetry.dart';

/// Top floating HUD presenting real-time GPS satellite status, coordinates, and action triggers
class MapTopHud extends StatelessWidget {
  final GpsTelemetry? telemetry;
  final String? areaName;
  final bool isDarkTheme;
  final VoidCallback onSearchPressed;
  final VoidCallback onThemeToggle;

  const MapTopHud({
    super.key,
    required this.telemetry,
    required this.areaName,
    required this.isDarkTheme,
    required this.onSearchPressed,
    required this.onThemeToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasFix = telemetry != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            // Live GPS Status Indicator Badge
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.accentLightGreen,
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentLightGreen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            areaName != null
                                ? areaName!
                                : (telemetry?.sourceDescription ?? 'ACQUIRING GPS FIX...'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (hasFix) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${telemetry!.position.latitude.toStringAsFixed(5)}°, ${telemetry!.position.longitude.toStringAsFixed(5)}° (±${telemetry!.accuracyMeters.toStringAsFixed(0)}m)',
                              style: const TextStyle(
                                color: AppTheme.accentLightGreen,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Search / Pin Location Button
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryDark.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: IconButton(
                tooltip: 'Search City / Pin Location',
                icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                onPressed: onSearchPressed,
              ),
            ),
            const SizedBox(width: 6),

            // Theme Switcher (Dark Rider Mode vs Daylight OSM)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryDark.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: IconButton(
                tooltip: 'Toggle Theme',
                icon: Icon(
                  isDarkTheme ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  color: AppTheme.accentLightGreen,
                  size: 20,
                ),
                onPressed: onThemeToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

