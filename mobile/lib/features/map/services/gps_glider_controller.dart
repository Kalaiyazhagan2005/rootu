import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';
import '../models/gps_telemetry.dart';

/// 60 FPS Glider Controller that smoothly interpolates discrete (1Hz) GPS telemetry
/// updates into a continuous, fluid user location marker animation.
class GpsGliderController {
  final TickerProvider vsync;
  final void Function(LatLng position, double heading, double accuracy) onTick;

  Ticker? _ticker;

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

  GpsGliderController({
    required this.vsync,
    required this.onTick,
  }) {
    _ticker = vsync.createTicker(_handleTick);
  }

  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  double get currentAccuracy => _currentAccuracy;
  double get currentSpeedKmh => _currentSpeedKmh;
  bool get hasFix => _currentPosition != null;

  /// Process incoming smoothed telemetry packet and initiate smooth interpolation.
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
      onTick(_currentPosition!, _currentHeading, _currentAccuracy);
      return;
    }

    final int deltaMs = now - _lastTimestampMs;
    _lastTimestampMs = now;

    // If gap between fixes is excessive (> 5000ms), snap immediately
    if (deltaMs > 5000 || deltaMs < 0) {
      _startPosition = telemetry.position;
      _targetPosition = telemetry.position;
      _currentPosition = telemetry.position;

      _startHeading = telemetry.heading;
      _targetHeading = telemetry.heading;
      _currentHeading = telemetry.heading;

      _startAccuracy = telemetry.accuracyMeters;
      _targetAccuracy = telemetry.accuracyMeters;
      _currentAccuracy = telemetry.accuracyMeters;

      _animationProgress = 1.0;
      _ticker?.stop();
      onTick(_currentPosition!, _currentHeading, _currentAccuracy);
      return;
    }

    _transitionDurationMs = deltaMs.clamp(400, 2000);

    // Continuous handoff: start from current interpolated state to prevent snap
    _startPosition = _currentPosition;
    _targetPosition = telemetry.position;

    _startHeading = _currentHeading;
    _targetHeading = telemetry.heading;

    _startAccuracy = _currentAccuracy;
    _targetAccuracy = telemetry.accuracyMeters;

    _animationProgress = 0.0;
    if (_ticker != null && !_ticker!.isActive) {
      _ticker!.start();
    }
  }

  void _handleTick(Duration elapsed) {
    if (_animationProgress >= 1.0) {
      _ticker?.stop();
      return;
    }

    // Advance animation progress based on target transition duration
    // ~16.6ms per frame at 60 FPS
    final double step = 16.667 / _transitionDurationMs;
    _animationProgress = (_animationProgress + step).clamp(0.0, 1.0);

    // Non-linear ease-out curve for natural deceleration into the target fix
    final double curvedT = Curves.easeOutCubic.transform(_animationProgress);

    if (_startPosition != null && _targetPosition != null) {
      _currentPosition = LatLng(
        _startPosition!.latitude +
            (_targetPosition!.latitude - _startPosition!.latitude) * curvedT,
        _startPosition!.longitude +
            (_targetPosition!.longitude - _startPosition!.longitude) * curvedT,
      );
    }

    _currentHeading = slerpHeading(_startHeading, _targetHeading, curvedT);
    _currentAccuracy =
        _startAccuracy + (_targetAccuracy - _startAccuracy) * curvedT;

    if (_currentPosition != null) {
      onTick(_currentPosition!, _currentHeading, _currentAccuracy);
    }
  }

  /// Shortest-arc circular interpolation between two angles in degrees [0, 360)
  static double slerpHeading(double startDeg, double targetDeg, double t) {
    final double s = (startDeg % 360.0 + 360.0) % 360.0;
    final double target = (targetDeg % 360.0 + 360.0) % 360.0;

    // Shortest angular difference in range [-180, 180)
    final double diff = ((target - s + 540.0) % 360.0) - 180.0;

    final double result = s + t * diff;
    return (result % 360.0 + 360.0) % 360.0;
  }

  void dispose() {
    _ticker?.dispose();
    _ticker = null;
  }
}

