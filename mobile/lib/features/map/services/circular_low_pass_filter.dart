import 'dart:math' as math;

/// Circular Low-Pass Filter using 2D unit vector exponential moving average.
/// Dampens magnetic compass micro-jitter and sensor noise without introducing
/// phase lag or 0/360 degree wrap discontinuity.
class CircularLowPassFilter {
  /// Smoothing factor in range (0.0, 1.0].
  /// Default beta = 0.20 provides optimal balance between jitter dampening
  /// and responsiveness for human movement and vehicle rotation.
  final double beta;

  double _sinSum = 0.0;
  double _cosSum = 1.0;
  bool _hasSample = false;

  CircularLowPassFilter({this.beta = 0.20}) {
    assert(beta > 0.0 && beta <= 1.0, 'Beta must be in (0, 1]');
  }

  /// Whether at least one valid angle sample has been processed.
  bool get hasSample => _hasSample;

  /// Current smoothed angle in degrees [0, 360), or null if no sample received.
  double? get currentAngle {
    if (!_hasSample) return null;
    final double smoothedRad = math.atan2(_sinSum, _cosSum);
    final double smoothedDeg = smoothedRad * (180.0 / math.pi);
    return (smoothedDeg % 360.0 + 360.0) % 360.0;
  }

  /// Resets the internal accumulator state.
  void reset() {
    _sinSum = 0.0;
    _cosSum = 1.0;
    _hasSample = false;
  }

  /// Filters an incoming angle in degrees and returns the smoothed angle in [0, 360).
  /// Safely handles non-finite inputs by returning the previous smoothed angle.
  double filter(double rawAngleDeg) {
    if (!rawAngleDeg.isFinite) {
      return currentAngle ?? 0.0;
    }

    final double rad = rawAngleDeg * (math.pi / 180.0);
    final double s = math.sin(rad);
    final double c = math.cos(rad);

    if (!_hasSample) {
      _sinSum = s;
      _cosSum = c;
      _hasSample = true;
      return (rawAngleDeg % 360.0 + 360.0) % 360.0;
    }

    _sinSum = (1.0 - beta) * _sinSum + beta * s;
    _cosSum = (1.0 - beta) * _cosSum + beta * c;

    final double smoothedRad = math.atan2(_sinSum, _cosSum);
    final double smoothedDeg = smoothedRad * (180.0 / math.pi);
    return (smoothedDeg % 360.0 + 360.0) % 360.0;
  }
}

