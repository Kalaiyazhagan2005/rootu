import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/trip_alarm.dart';

/// Production location-based trip alarm engine evaluating proximity and triggering native alarms
class TripAlarmService {
  static const MethodChannel _channel =
      MethodChannel('com.example.rootu_mobile/gps_hardware');
  static const Distance _distanceCalc = Distance();

  static bool _isPlaying = false;

  /// Evaluate if current telemetry position enters the alarm geofence radius
  /// Uses highway speed adaptation so high-speed riders get alerted 1-2 minutes ahead
  static bool shouldTrigger({
    required TripAlarm alarm,
    required LatLng riderPosition,
    required double speedKmh,
  }) {
    if (alarm.isTriggered || alarm.isDismissed) return false;

    final double distanceMeters =
        _distanceCalc.as(LengthUnit.Meter, riderPosition, alarm.location);

    // Highway speed adaptation:
    // If cruising at 90 km/h (25 m/s), 60 seconds of travel is 1500m.
    // Ensure effective radius is at least 60 seconds of highway travel ahead.
    final double speedMetersPerSec = (speedKmh * 1000.0) / 3600.0;
    final double highwayBufferMeters = speedMetersPerSec * 60.0;
    final double effectiveRadius = math.max(alarm.radiusMeters, highwayBufferMeters);

    return distanceMeters <= effectiveRadius;
  }

  /// Trigger native ringtone and haptic vibration pattern
  static Future<void> triggerNativeAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      await _channel.invokeMethod('startAlarmTone');
    } catch (_) {
      // Fallback in case native channel is unavailable
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Stop native alarm ringtone and vibrator
  static Future<void> stopNativeAlarm() async {
    _isPlaying = false;
    try {
      await _channel.invokeMethod('stopAlarmTone');
    } catch (_) {}
  }
}

