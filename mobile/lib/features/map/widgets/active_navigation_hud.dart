import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/route_model.dart';
import '../models/trip_alarm.dart';

/// Turn-by-turn live navigation HUD displayed when actively driving/riding a route
class ActiveNavigationHud extends StatelessWidget {
  final RouteDetails route;
  final RouteStep? currentStep;
  final TripAlarm? activeAlarm;
  final VoidCallback? onConfigureAlarm;
  final VoidCallback onStopNavigation;

  const ActiveNavigationHud({
    super.key,
    required this.route,
    required this.currentStep,
    this.activeAlarm,
    this.onConfigureAlarm,
    required this.onStopNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final step = currentStep ?? (route.steps.isNotEmpty ? route.steps.first : null);

    return Stack(
      children: [
        // 1. TOP MANEUVER DIRECTION BANNER
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primaryDark,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.accentLightGreen,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Maneuver Icon Box
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.accentLightGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      step?.maneuverIcon ?? Icons.straight_rounded,
                      color: AppTheme.primaryDark,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Distance & Instruction Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          step != null ? 'In ${step.formattedDistance}' : 'Follow Route',
                          style: const TextStyle(
                            color: AppTheme.accentLightGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step?.instruction ?? 'Proceed along highway',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 2. BOTTOM DRIVING CONTROL BAR
        Positioned(
          left: 14,
          right: 14,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryDark,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTheme.accentLightGreen.withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Remaining Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      route.formattedDuration,
                      style: const TextStyle(
                        color: AppTheme.accentLightGreen,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          route.formattedDistance,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'ETA ${route.formattedEta}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (activeAlarm != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white38,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: onConfigureAlarm,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.notifications_active_rounded,
                                  size: 13,
                                  color: AppTheme.accentLightGreen,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  activeAlarm!.formattedRadius,
                                  style: const TextStyle(
                                    color: AppTheme.accentLightGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const Spacer(),

                // Exit / Stop Navigation Button
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.errorRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.5)),
                  ),
                  child: IconButton(
                    tooltip: 'Exit Navigation',
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: onStopNavigation,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

