import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/trip_alarm.dart';

/// Modal sheet allowing the rider to configure a proximity/wake-up location alarm
class AlarmSetupSheet extends StatefulWidget {
  final String defaultPlaceName;
  final LatLng targetLocation;
  final TripAlarm? existingAlarm;
  final ValueChanged<TripAlarm?> onAlarmConfigured;

  const AlarmSetupSheet({
    super.key,
    required this.defaultPlaceName,
    required this.targetLocation,
    this.existingAlarm,
    required this.onAlarmConfigured,
  });

  static Future<void> show({
    required BuildContext context,
    required String defaultPlaceName,
    required LatLng targetLocation,
    TripAlarm? existingAlarm,
    required ValueChanged<TripAlarm?> onAlarmConfigured,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AlarmSetupSheet(
        defaultPlaceName: defaultPlaceName,
        targetLocation: targetLocation,
        existingAlarm: existingAlarm,
        onAlarmConfigured: onAlarmConfigured,
      ),
    );
  }

  @override
  State<AlarmSetupSheet> createState() => _AlarmSetupSheetState();
}

class _AlarmSetupSheetState extends State<AlarmSetupSheet> {
  late double _selectedRadius;

  final List<double> _radiusOptions = [
    500.0,
    1000.0,
    2000.0,
    5000.0,
  ];

  @override
  void initState() {
    super.initState();
    _selectedRadius = widget.existingAlarm?.radiusMeters ?? 1000.0;
  }

  String _formatOption(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toInt()} km';
    }
    return '${meters.toInt()} m';
  }

  void _saveAlarm() {
    final alarm = TripAlarm(
      id: widget.existingAlarm?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      placeName: widget.defaultPlaceName,
      location: widget.targetLocation,
      radiusMeters: _selectedRadius,
      createdAt: DateTime.now(),
    );
    widget.onAlarmConfigured(alarm);
    Navigator.pop(context);
  }

  void _removeAlarm() {
    widget.onAlarmConfigured(null);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentLightGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.accentLightGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Location Alarm',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Sound alert when approaching your stop',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Target Location Summary Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.accentLightGreen,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ALARM TARGET',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.defaultPlaceName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Alert Radius Selection Title
          const Text(
            'ALERT DISTANCE BEFORE ARRIVAL',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          // Preset Chips Row
          Row(
            children: _radiusOptions.map((radius) {
              final isSelected = _selectedRadius == radius;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRadius = radius),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.accentLightGreen.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.accentLightGreen
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1.4,
                        ),
                      ),
                      child: Text(
                        _formatOption(radius),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Speed-Adaptive Note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.accentLightGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accentLightGreen, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Speed Adaptive: Alerts at least 1-2 minutes ahead when cruising at highway speeds.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              if (widget.existingAlarm != null) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorRed,
                    side: BorderSide(color: AppTheme.errorRed.withValues(alpha: 0.6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _removeAlarm,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('REMOVE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentLightGreen,
                      foregroundColor: AppTheme.primaryDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _saveAlarm,
                    icon: const Icon(Icons.alarm_on_rounded, size: 20),
                    label: Text(
                      widget.existingAlarm != null ? 'UPDATE ALARM' : 'SET ALARM',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

