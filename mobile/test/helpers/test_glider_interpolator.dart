import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';

/// Helper class providing pure mathematical interpolation functions for 60 FPS gliding
class GpsGliderInterpolator {
  /// Shortest-arc circular interpolation between two angles in degrees [0, 360)
  static double slerpHeading(double startDeg, double targetDeg, double t) {
    final double s = (startDeg % 360.0 + 360.0) % 360.0;
    final double target = (targetDeg % 360.0 + 360.0) % 360.0;

    // Shortest angular difference in range [-180, 180)
    final double diff = ((target - s + 540.0) % 360.0) - 180.0;

    final double result = s + t * diff;
    return (result % 360.0 + 360.0) % 360.0;
  }

  /// Linear coordinate interpolation in planar WGS84 space
  static LatLng lerpLatLng(LatLng start, LatLng target, double t) {
    final double lat = start.latitude + (target.latitude - start.latitude) * t;
    final double lng = start.longitude + (target.longitude - start.longitude) * t;
    return LatLng(lat, lng);
  }

  /// Flashlight beam cone aperture angle based on velocity
  static double calculateConeAperture(double speedKmh) {
    return speedKmh > 15.0 ? 42.0 : 60.0;
  }

  /// Flashlight beam start and sweep angles in radians (0 deg points North / -pi/2)
  static Map<String, double> calculateBeamAngles(double headingDeg, double coneAngleDeg) {
    final double coneRad = coneAngleDeg * (math.pi / 180.0);
    final double headingRad = headingDeg * (math.pi / 180.0);
    // Heading 0 points North (upwards, -pi/2)
    final double startAngle = -math.pi / 2.0 - (coneRad / 2.0) + headingRad;
    return {
      'startAngleRad': startAngle,
      'sweepAngleRad': coneRad,
    };
  }

  /// Physical accuracy radius clamping in meters
  static double clampAccuracyRadius(double accuracyMeters) {
    if (accuracyMeters.isNaN || accuracyMeters.isInfinite) {
      return 25.0;
    }
    return accuracyMeters.clamp(3.0, 500.0);
  }
}

/// Simulated Glider Controller for offline test verification of 60 FPS state transitions
class SimulatedGpsGlider {
  LatLng? _startPosition;
  LatLng? _targetPosition;
  LatLng? _currentPosition;

  double _startHeading = 0.0;
  double _targetHeading = 0.0;
  double _currentHeading = 0.0;

  double _startAccuracy = 15.0;
  double _targetAccuracy = 15.0;
  double _currentAccuracy = 15.0;

  double _currentSpeedKmh = 0.0;
  int _lastTimestampMs = 0;
  int _transitionDurationMs = 1000;
  double _animationProgress = 1.0;

  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  double get currentAccuracy => _currentAccuracy;
  double get currentSpeedKmh => _currentSpeedKmh;
  bool get hasFix => _currentPosition != null;
  double get animationProgress => _animationProgress;
  int get transitionDurationMs => _transitionDurationMs;

  void onNewTelemetry(GpsTelemetry telemetry, {int? timestampMs}) {
    final int now = timestampMs ?? telemetry.timestamp.millisecondsSinceEpoch;
    _currentSpeedKmh = telemetry.speedKmh;

    if (_currentPosition == null) {
      _startPosition = telemetry.position;
      _targetPosition = telemetry.position;
      _currentPosition = telemetry.position;
      _startHeading = telemetry.heading;
      _targetHeading = telemetry.heading;
      _currentHeading = telemetry.heading;
      _startAccuracy = telemetry.accuracyMeters;
      _targetAccuracy = telemetry.accuracyMeters;
      _currentAccuracy = telemetry.accuracyMeters;
      _lastTimestampMs = now;
      _animationProgress = 1.0;
      return;
    }

    final int deltaMs = now - _lastTimestampMs;
    _lastTimestampMs = now;
    _transitionDurationMs = deltaMs.clamp(400, 2000);

    // Continuous starting position: start from current interpolated position (no jump)
    _startPosition = _currentPosition;
    _targetPosition = telemetry.position;

    _startHeading = _currentHeading;
    _targetHeading = telemetry.heading;

    _startAccuracy = _currentAccuracy;
    _targetAccuracy = telemetry.accuracyMeters;

    _animationProgress = 0.0;
  }

  /// Advance animation progress by t (0.0 to 1.0)
  void tick(double progress) {
    _animationProgress = progress.clamp(0.0, 1.0);

    if (_startPosition != null && _targetPosition != null) {
      _currentPosition = GpsGliderInterpolator.lerpLatLng(
        _startPosition!,
        _targetPosition!,
        _animationProgress,
      );
    }

    _currentHeading = GpsGliderInterpolator.slerpHeading(
      _startHeading,
      _targetHeading,
      _animationProgress,
    );

    final double rawAcc = _startAccuracy + (_targetAccuracy - _startAccuracy) * _animationProgress;
    _currentAccuracy = GpsGliderInterpolator.clampAccuracyRadius(rawAcc);
  }
}
