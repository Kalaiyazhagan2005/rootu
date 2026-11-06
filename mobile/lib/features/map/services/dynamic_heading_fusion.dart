import 'circular_low_pass_filter.dart';

/// Dynamic Heading Fusion Engine: Combines magnetic compass azimuth with GNSS course bearing.
///
/// Implements a 3-Phase Speed Fusion Model:
/// - Phase 1 (speed <= 3.6 km/h / 1.0 m/s): 100% Compass Azimuth (w_gps = 0.0).
///   Eliminates erratic GNSS Doppler bearing flips while stationary or walking.
/// - Phase 2 (3.6 km/h < speed < 10.8 km/h / 1.0 m/s < v < 3.0 m/s):
///   Linear shortest-arc slerp blend between smoothed compass and GPS bearing.
/// - Phase 3 (speed >= 10.8 km/h / 3.0 m/s): 100% GPS Course Bearing (w_gps = 1.0).
///   Aligns user indicator with vehicle trajectory along road network.
///
/// Handles sensor degradation fallbacks, boundary wraps (0/360 degrees), and non-finite values.
class DynamicHeadingFusion {
  /// Low speed threshold in km/h (1.0 m/s). Below or equal to this speed,
  /// 100% compass heading is used.
  static const double lowSpeedThresholdKmh = 3.6;

  /// High speed threshold in km/h (3.0 m/s). Above or equal to this speed,
  /// 100% GPS course bearing is used.
  static const double highSpeedThresholdKmh = 10.8;

  final CircularLowPassFilter _compassFilter;
  double _lastFusedHeading = 0.0;
  double _lastGpsWeight = 0.0;
  bool _hasInitialHeading = false;

  /// Creates a DynamicHeadingFusion engine with an internal CircularLowPassFilter.
  DynamicHeadingFusion({double compassBeta = 0.20})
      : _compassFilter = CircularLowPassFilter(beta: compassBeta);

  /// Most recent fused heading in degrees [0, 360).
  double get lastFusedHeading => _lastFusedHeading;

  /// Most recent GPS weight in range [0.0, 1.0].
  double get lastGpsWeight => _lastGpsWeight;

  /// Whether at least one valid heading has been calculated.
  bool get hasInitialHeading => _hasInitialHeading;

  /// Access to internal circular low-pass filter for diagnostics or configuration.
  CircularLowPassFilter get compassFilter => _compassFilter;

  /// Resets fusion engine state and internal compass filter.
  void reset() {
    _compassFilter.reset();
    _lastFusedHeading = 0.0;
    _lastGpsWeight = 0.0;
    _hasInitialHeading = false;
  }

  /// Calculates shortest-arc circular interpolation (slerp) between startDeg and targetDeg.
  /// Result is normalized to [0, 360) degrees without snapping across the 0/360 boundary.
  static double shortestArcSlerp(double startDeg, double targetDeg, double t) {
    if (!startDeg.isFinite && !targetDeg.isFinite) return 0.0;
    if (!startDeg.isFinite) return (targetDeg % 360.0 + 360.0) % 360.0;
    if (!targetDeg.isFinite) return (startDeg % 360.0 + 360.0) % 360.0;

    final double s = (startDeg % 360.0 + 360.0) % 360.0;
    final double target = (targetDeg % 360.0 + 360.0) % 360.0;
    final double clampedT = t.clamp(0.0, 1.0);

    // Shortest angular difference in range [-180, 180)
    final double diff = ((target - s + 540.0) % 360.0) - 180.0;

    final double result = s + clampedT * diff;
    return (result % 360.0 + 360.0) % 360.0;
  }

  /// Updates the fused heading using incoming compass heading, GPS bearing, and speed.
  ///
  /// Parameters:
  /// - [compassHeading]: Device magnetic/true azimuth in degrees [0, 360], or null/negative if unavailable.
  /// - [gpsBearing]: GPS course over ground in degrees [0, 360], or negative (-1.0) if stationary/unavailable.
  /// - [speedKmh]: Current vehicle/user speed in km/h.
  ///
  /// Returns fused heading in degrees [0, 360).
  double update(double? compassHeading, double gpsBearing, double speedKmh) {
    final bool hasValidCompass = compassHeading != null &&
        compassHeading.isFinite &&
        compassHeading >= 0.0 &&
        compassHeading <= 360.0;

    final bool hasValidGps = gpsBearing.isFinite &&
        gpsBearing >= 0.0 &&
        gpsBearing <= 360.0;

    final double safeSpeed = (speedKmh.isFinite && speedKmh >= 0.0) ? speedKmh : 0.0;

    // Filter compass reading if present to keep filter state continuously updated
    final double smoothedCompass = hasValidCompass
        ? _compassFilter.filter(compassHeading)
        : _lastFusedHeading;

    final double normalizedGps = hasValidGps
        ? (gpsBearing % 360.0 + 360.0) % 360.0
        : _lastFusedHeading;

    double fused;

    if (!hasValidCompass && !hasValidGps) {
      // Neither sensor available: retain previous heading
      fused = _lastFusedHeading;
      _lastGpsWeight = 0.0;
    } else if (hasValidCompass && !hasValidGps) {
      // Only compass available: 100% compass
      fused = smoothedCompass;
      _lastGpsWeight = 0.0;
    } else if (!hasValidCompass && hasValidGps) {
      // Only GPS bearing available: 100% GPS
      fused = normalizedGps;
      _lastGpsWeight = 1.0;
    } else {
      // Both sensors available: apply 3-phase speed model
      if (safeSpeed <= lowSpeedThresholdKmh) {
        // Phase 1: Stationary / Walk
        fused = smoothedCompass;
        _lastGpsWeight = 0.0;
      } else if (safeSpeed >= highSpeedThresholdKmh) {
        // Phase 3: Moving / Cruising
        fused = normalizedGps;
        _lastGpsWeight = 1.0;
      } else {
        // Phase 2: Dynamic Transition Zone
        final double wGps = (safeSpeed - lowSpeedThresholdKmh) /
            (highSpeedThresholdKmh - lowSpeedThresholdKmh);
        _lastGpsWeight = wGps;

        fused = shortestArcSlerp(smoothedCompass, normalizedGps, wGps);
      }
    }

    _lastFusedHeading = (fused % 360.0 + 360.0) % 360.0;
    _hasInitialHeading = true;
    return _lastFusedHeading;
  }
}

