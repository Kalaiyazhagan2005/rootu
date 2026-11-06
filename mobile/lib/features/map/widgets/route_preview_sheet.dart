import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/route_model.dart';
import '../models/trip_alarm.dart';

enum TravelMode {
  motorcycle,
  car,
}

/// Google Maps-style bottom route summary card showing distance, ETA, and Start trigger
class RoutePreviewSheet extends StatefulWidget {
  final RouteDetails route;
  final TripAlarm? activeAlarm;
  final VoidCallback onConfigureAlarm;
  final VoidCallback onStartNavigation;
  final VoidCallback onClose;

  const RoutePreviewSheet({
    super.key,
    required this.route,
    this.activeAlarm,
    required this.onConfigureAlarm,
    required this.onStartNavigation,
    required this.onClose,
  });

  @override
  State<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends State<RoutePreviewSheet> {
  TravelMode _selectedMode = TravelMode.motorcycle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.primaryDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.accentLightGreen.withValues(alpha: 0.8),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Destination Name & Close Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentLightGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.directions_rounded,
                    color: AppTheme.accentLightGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.route.destinationName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.route.intermediateStopsCount > 0
                            ? 'Via ${widget.route.waypoints.where((w) => w.isStop).map((w) => w.name).join(', ')} (${widget.route.intermediateStopsCount} ${widget.route.intermediateStopsCount == 1 ? "stop" : "stops"})'
                            : 'Fastest route via highways and main roads',
                        style: TextStyle(
                          color: widget.route.intermediateStopsCount > 0
                              ? AppTheme.accentLightGreen
                              : Colors.white.withValues(alpha: 0.65),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Mode Selector: Motorcycle vs Car
            Row(
              children: [
                _buildModeTab(
                  mode: TravelMode.motorcycle,
                  label: 'Rider / Bike',
                  icon: Icons.two_wheeler_rounded,
                ),
                const SizedBox(width: 8),
                _buildModeTab(
                  mode: TravelMode.car,
                  label: 'Car',
                  icon: Icons.directions_car_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metrics Summary Bar (Duration, Distance, ETA)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TRAVEL TIME',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.route.formattedDuration,
                        style: const TextStyle(
                          color: AppTheme.accentLightGreen,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: Colors.white12,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISTANCE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.route.formattedDistance,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 28,
                    width: 1,
                    color: Colors.white12,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ARRIVAL',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.route.formattedEta,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Location Proximity Alarm Setup Pill
            GestureDetector(
              onTap: widget.onConfigureAlarm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.activeAlarm != null
                      ? AppTheme.accentLightGreen.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.activeAlarm != null
                        ? AppTheme.accentLightGreen
                        : Colors.white.withValues(alpha: 0.12),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.activeAlarm != null
                          ? Icons.notifications_active_rounded
                          : Icons.alarm_add_rounded,
                      color: widget.activeAlarm != null
                          ? AppTheme.accentLightGreen
                          : Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.activeAlarm != null
                            ? 'Alarm Active: ${widget.activeAlarm!.formattedRadius} before arrival'
                            : 'Set Proximity / Arrival Alarm for this trip',
                        style: TextStyle(
                          color: widget.activeAlarm != null ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: widget.activeAlarm != null ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: widget.activeAlarm != null ? AppTheme.accentLightGreen : Colors.white38,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Large Action Button: START NAVIGATION
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentLightGreen,
                  foregroundColor: AppTheme.primaryDark,
                  elevation: 4,
                  shadowColor: AppTheme.accentLightGreen.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: widget.onStartNavigation,
                icon: const Icon(
                  Icons.navigation_rounded,
                  size: 22,
                  color: AppTheme.primaryDark,
                ),
                label: const Text(
                  'START NAVIGATION',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required TravelMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentLightGreen.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.accentLightGreen
                  : Colors.white.withValues(alpha: 0.12),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.accentLightGreen : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

