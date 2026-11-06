import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/trip_alarm.dart';
import '../services/trip_alarm_service.dart';

/// Fullscreen high-priority alert dialog shown when a trip alarm boundary is crossed
class AlarmTriggeredDialog extends StatefulWidget {
  final TripAlarm alarm;
  final VoidCallback onDismiss;

  const AlarmTriggeredDialog({
    super.key,
    required this.alarm,
    required this.onDismiss,
  });

  static Future<void> show({
    required BuildContext context,
    required TripAlarm alarm,
    required VoidCallback onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlarmTriggeredDialog(
        alarm: alarm,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<AlarmTriggeredDialog> createState() => _AlarmTriggeredDialogState();
}

class _AlarmTriggeredDialogState extends State<AlarmTriggeredDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _dismiss() {
    TripAlarmService.stopNativeAlarm();
    widget.onDismiss();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.primaryDark,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.accentLightGreen,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing Alarm Icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: AppTheme.accentLightGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentLightGreen.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppTheme.primaryDark,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentLightGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ARRIVAL PROXIMITY ALERT',
                  style: TextStyle(
                    color: AppTheme.accentLightGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Target Name
              Text(
                widget.alarm.placeName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Distance Subtitle
              Text(
                'You have entered the ${widget.alarm.formattedRadius} arrival zone. Prepare for your stop or exit.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 24),

              // Big Dismiss Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentLightGreen,
                    foregroundColor: AppTheme.primaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  onPressed: _dismiss,
                  icon: const Icon(Icons.alarm_off_rounded, size: 22),
                  label: const Text(
                    'DISMISS ALARM',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

