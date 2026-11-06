import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/route_model.dart';

/// Google Maps-style multi-stop directions header card with Origin, Stops, and Destination
class MultiStopPlannerCard extends StatelessWidget {
  final List<RouteWaypoint> waypoints;
  final VoidCallback onAddStop;
  final ValueChanged<int> onRemoveStop;
  final ValueChanged<int> onEditWaypoint;
  final VoidCallback onSwapEndpoints;
  final VoidCallback onClose;

  const MultiStopPlannerCard({
    super.key,
    required this.waypoints,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onEditWaypoint,
    required this.onSwapEndpoints,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final origin = waypoints.first;
    final destination = waypoints.last;
    final intermediateStops = waypoints.sublist(1, waypoints.length - 1);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppTheme.accentLightGreen.withValues(alpha: 0.8),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action Bar: Back, Title, Swap
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                  onPressed: onClose,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Directions & Stops',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Swap start and destination',
                  icon: const Icon(Icons.swap_vert_rounded, color: AppTheme.accentLightGreen, size: 22),
                  onPressed: onSwapEndpoints,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Waypoints List with Dotted Indicator Column
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Visual Track Indicators
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: Column(
                    children: [
                      // Origin Indicator
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accentLightGreen,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 24,
                        color: Colors.white24,
                      ),
                      // Intermediate Stop Indicators
                      for (int i = 0; i < intermediateStops.length; i++) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.orangeAccent,
                          ),
                          child: Center(
                            child: Text(
                              String.fromCharCode(65 + i),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 24,
                          color: Colors.white24,
                        ),
                      ],
                      // Destination Indicator
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.redAccent,
                        size: 16,
                      ),
                    ],
                  ),
                ),

                // Right Input Labels & Delete Triggers
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Origin Field
                      _buildWaypointField(
                        title: origin.name,
                        hint: 'Choose starting point',
                        isOrigin: true,
                        onTap: () => onEditWaypoint(0),
                      ),
                      const SizedBox(height: 8),

                      // 2. Intermediate Stops
                      for (int i = 0; i < intermediateStops.length; i++) ...[
                        _buildWaypointField(
                          title: intermediateStops[i].name,
                          hint: 'Stop ${i + 1}',
                          badgeText: 'Stop ${String.fromCharCode(65 + i)}',
                          onTap: () => onEditWaypoint(i + 1),
                          onDelete: () => onRemoveStop(i + 1),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // 3. Destination Field
                      _buildWaypointField(
                        title: destination.name,
                        hint: 'Choose destination',
                        isDestination: true,
                        onTap: () => onEditWaypoint(waypoints.length - 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // "+ Add stop" Button (allows up to 5 intermediate stops)
            if (intermediateStops.length < 5)
              InkWell(
                onTap: onAddStop,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.accentLightGreen.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: AppTheme.accentLightGreen,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Add stop',
                        style: TextStyle(
                          color: AppTheme.accentLightGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointField({
    required String title,
    required String hint,
    String? badgeText,
    bool isOrigin = false,
    bool isDestination = false,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            if (badgeText != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title.isNotEmpty ? title : hint,
                style: TextStyle(
                  color: title.isNotEmpty ? Colors.white : Colors.white38,
                  fontSize: 13,
                  fontWeight: title.isNotEmpty ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close_rounded, color: Colors.white60, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

