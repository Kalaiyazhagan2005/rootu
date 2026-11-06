import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// 2D Kinematic Kalman Filter for high-precision GPS coordinate smoothing.
///
/// Implements a 4D state kinematic tracking filter in local planar tangent meters:
/// State vector: x = [pos_x, pos_y, vel_x, vel_y]^T
/// Measurement vector: z = [z_x, z_y]^T
///
/// State transition matrix F:
///   [ 1  0  dt  0 ]
///   [ 0  1  0  dt ]
///   [ 0  0  1   0 ]
///   [ 0  0  0   1 ]
///
/// Measurement matrix H:
///   [ 1  0  0  0 ]
///   [ 0  1  0  0 ]
///
/// Measurement covariance R:
///   R = diag(sigma_acc^2, sigma_acc^2), where sigma_acc = max(accuracyMeters, 3.0)
///
/// Adaptive process noise Q:
///   - Stationary (speed < 0.5 m/s): sigma_a = 0.05 m/s^2 (locks position against GPS wander)
///   - Moving (speed >= 0.5 m/s):    sigma_a = 2.50 m/s^2 (responsive trajectory tracking)
///
/// Teleportation, blackout, and clock anomaly defense:
///   - Resets filter on satellite blackout gaps (dt > 5.0 seconds).
///   - Resets filter on severe clock rollback anomalies (dt < -1.0 second).
///   - Resets filter on anomalous teleportations (> 100 meters without valid motion).
class GpsKalmanFilter {
  /// Approximate meters per degree of latitude on the WGS84 ellipsoid.
  static const double _metersPerLatDegree = 111139.0;

  /// Default baseline accuracy in meters when incoming accuracy is invalid (NaN/Inf/<=0).
  static const double _defaultAccuracyMeters = 25.0;

  /// Lower bound threshold for measurement noise standard deviation in meters.
  static const double _minAccuracyMeters = 3.0;

  /// Velocity threshold distinguishing stationary drift locking from active locomotion.
  static const double _stationarySpeedThresholdMps = 0.5;

  /// Process noise acceleration spectral density when stationary (m/s^2).
  static const double _sigmaStationary = 0.05;

  /// Process noise acceleration spectral density when moving (m/s^2).
  static const double _sigmaMoving = 2.5;

  /// Time gap threshold in seconds triggering a stream interruption / blackout reset.
  static const double _blackoutThresholdSeconds = 5.0;

  /// Distance threshold in meters triggering an anomalous teleportation reset.
  static const double _teleportThresholdMeters = 100.0;

  bool _initialized = false;
  double _refLat = 0.0;
  double _refLng = 0.0;
  int _lastTimestampMs = 0;

  // 4D State vector: [pos_x, pos_y, vel_x, vel_y] in meters and m/s relative to reference origin
  double _x = 0.0;
  double _y = 0.0;
  double _vx = 0.0;
  double _vy = 0.0;

  // Covariance diagonal states (variances)
  double _p00 = 100.0; // pos_x variance (m^2)
  double _p11 = 100.0; // pos_y variance (m^2)
  double _p22 = 25.0;  // vel_x variance ((m/s)^2)
  double _p33 = 25.0;  // vel_y variance ((m/s)^2)

  /// Whether the filter has received at least one valid coordinate fix.
  bool get isInitialized => _initialized;

  /// Current 2D estimated ground speed in meters per second.
  double get velocityMps => math.sqrt(_vx * _vx + _vy * _vy);

  /// Current local planar position X (East) in meters from reference origin.
  double get posX => _x;

  /// Current local planar position Y (North) in meters from reference origin.
  double get posY => _y;

  /// Current local planar velocity Vx (East) in meters per second.
  double get velX => _vx;

  /// Current local planar velocity Vy (North) in meters per second.
  double get velY => _vy;

  /// Reference latitude used for local equirectangular projection origin.
  double get refLat => _refLat;

  /// Reference longitude used for local equirectangular projection origin.
  double get refLng => _refLng;

  /// Reference origin LatLng coordinates, or null if uninitialized.
  LatLng? get referenceOrigin => _initialized ? LatLng(_refLat, _refLng) : null;

  /// Resets all filter states, reference origin, and covariance matrices.
  void reset() {
    _initialized = false;
    _refLat = 0.0;
    _refLng = 0.0;
    _x = 0.0;
    _y = 0.0;
    _vx = 0.0;
    _vy = 0.0;
    _p00 = 100.0;
    _p11 = 100.0;
    _p22 = 25.0;
    _p33 = 25.0;
    _lastTimestampMs = 0;
  }

  /// Processes a raw GPS fix and returns the optimal smoothed WGS84 coordinates.
  ///
  /// - [rawPos]: Incoming raw geodetic position (latitude, longitude).
  /// - [accuracyMeters]: Reported horizontal GPS accuracy radius (68% confidence).
  /// - [speedMps]: Instantaneous ground speed in meters per second.
  /// - [timestampMs]: Epoch timestamp in milliseconds.
  LatLng filter(LatLng rawPos, double accuracyMeters, double speedMps, int timestampMs) {
    // Coordinate sanity check: reject NaN or infinite geodetic inputs immediately.
    if (!rawPos.latitude.isFinite || !rawPos.longitude.isFinite) {
      if (_initialized) {
        final double cosLat = math.cos(_refLat * math.pi / 180.0).abs();
        final double metersPerLngDegree = _metersPerLatDegree * (cosLat < 1e-6 ? 1e-6 : cosLat);
        return LatLng(
          _refLat + (_y / _metersPerLatDegree),
          _refLng + (_x / metersPerLngDegree),
        );
      }
      return const LatLng(0.0, 0.0);
    }

    // Sanitize accuracy input: clamp NaN, infinite, or non-positive values to safe default.
    final double safeAccuracy = (accuracyMeters.isNaN || accuracyMeters.isInfinite || accuracyMeters <= 0.0)
        ? _defaultAccuracyMeters
        : math.max(accuracyMeters, _minAccuracyMeters);

    // Sanitize speed input.
    final double safeSpeed = (speedMps.isNaN || speedMps.isInfinite || speedMps < 0.0)
        ? 0.0
        : speedMps;

    // Initialization on the first valid GPS coordinate fix.
    if (!_initialized) {
      _initializeOrigin(rawPos, safeAccuracy, timestampMs);
      return rawPos;
    }

    // Compute raw delta time in seconds.
    final double rawDt = (timestampMs - _lastTimestampMs) / 1000.0;

    // Check for satellite blackout gap (> 5 seconds) or negative clock anomaly (< -1.0 second).
    final bool isBlackoutGap = rawDt > _blackoutThresholdSeconds || rawDt < -1.0;

    // Clamp non-positive clock jitter (<= 0.0s) to nominal 20 Hz step (0.05s).
    final double dt = rawDt <= 0.0 ? 0.05 : rawDt;

    // Projected measurement in local planar tangent meters relative to reference origin.
    final double cosLat = math.cos(_refLat * math.pi / 180.0).abs();
    final double metersPerLngDegree = _metersPerLatDegree * (cosLat < 1e-6 ? 1e-6 : cosLat);
    final double zX = (rawPos.longitude - _refLng) * metersPerLngDegree;
    final double zY = (rawPos.latitude - _refLat) * _metersPerLatDegree;

    // Predicted state vector: x_pred = x + vx * dt, y_pred = y + vy * dt
    final double xPred = _x + _vx * dt;
    final double yPred = _y + _vy * dt;

    // Innovation displacement from predicted position to incoming measurement.
    final double dx = zX - xPred;
    final double dy = zY - yPred;
    final double innovationDistance = math.sqrt(dx * dx + dy * dy);

    // Maximum physically plausible displacement in meters across dt.
    final double currentSpeed = math.max(safeSpeed, velocityMps);
    final double maxPlausibleDisplacement = currentSpeed * dt + 50.0;

    // Teleportation defense: jump exceeds 100 meters without plausible motion.
    final bool isTeleportation = innovationDistance > _teleportThresholdMeters &&
        innovationDistance > maxPlausibleDisplacement;

    // Handle stream interruption or large teleportation via clean re-anchoring.
    if (isBlackoutGap || isTeleportation) {
      _initializeOrigin(rawPos, safeAccuracy, timestampMs);
      return rawPos;
    }

    _lastTimestampMs = timestampMs;

    // 1. State Prediction: x_pred = F * x
    _x = xPred;
    _y = yPred;

    // 2. Covariance Prediction: P_pred = F * P * F^T + Q
    // Adaptive process noise Q:
    // When stationary (speed < 0.5 m/s), sigmaA = 0.05 m/s^2 locks marker position against GPS drift.
    // When moving (speed >= 0.5 m/s), sigmaA = 2.50 m/s^2 allows responsive kinematic tracking.
    final double sigmaA = safeSpeed < _stationarySpeedThresholdMps ? _sigmaStationary : _sigmaMoving;
    final double dt2 = dt * dt;
    final double qPos = 0.5 * sigmaA * dt2;
    final double qVel = sigmaA * dt;

    _p00 += qPos * qPos;
    _p11 += qPos * qPos;
    _p22 += qVel * qVel;
    _p33 += qVel * qVel;

    // 3. Measurement Covariance R
    final double r = safeAccuracy * safeAccuracy;

    // 4. Kalman Gain K
    final double kPosX = _p00 / (_p00 + r);
    final double kPosY = _p11 / (_p11 + r);
    final double kVelX = _p22 / (_p22 + r * 2.0);
    final double kVelY = _p33 / (_p33 + r * 2.0);

    // 5. Innovation (Measurement Residual): y = z - H * x_pred
    final double innovX = zX - _x;
    final double innovY = zY - _y;

    // 6. State Update: x_updated = x_pred + K * y
    // Clamp denominator to nominal 20 Hz step (0.05s) to eliminate transient velocity
    // surges during sub-millisecond platform event bursts (e.g. dt < 50ms).
    final double dtVel = math.max(dt, 0.05);
    _x += kPosX * innovX;
    _y += kPosY * innovY;
    _vx += kVelX * innovX / dtVel;
    _vy += kVelY * innovY / dtVel;

    // 7. Covariance Update: P_updated = (I - K * H) * P_pred
    _p00 = (1.0 - kPosX) * _p00;
    _p11 = (1.0 - kPosY) * _p11;
    _p22 = (1.0 - kVelX) * _p22;
    _p33 = (1.0 - kVelY) * _p33;

    // 8. Convert smoothed planar meters back to WGS84 Geodetic coordinates
    final double smoothedLat = _refLat + (_y / _metersPerLatDegree);
    final double smoothedLng = _refLng + (_x / metersPerLngDegree);

    return LatLng(smoothedLat, smoothedLng);
  }

  /// Internal helper to anchor reference origin and initialize state covariance.
  void _initializeOrigin(LatLng origin, double safeAccuracy, int timestampMs) {
    _refLat = origin.latitude;
    _refLng = origin.longitude;
    _x = 0.0;
    _y = 0.0;
    _vx = 0.0;
    _vy = 0.0;
    _p00 = safeAccuracy * safeAccuracy;
    _p11 = safeAccuracy * safeAccuracy;
    _p22 = 4.0;
    _p33 = 4.0;
    _lastTimestampMs = timestampMs;
    _initialized = true;
  }
}

