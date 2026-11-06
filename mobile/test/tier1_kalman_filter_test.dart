import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'helpers/test_kalman_filter.dart';

void main() {
  group('Tier 1: 2D Kalman Filter Math Feature Coverage', () {
    late GpsKalmanFilter kalman;

    setUp(() {
      kalman = GpsKalmanFilter();
    });

    test('TC4.1: State initialization sets reference origin and returns first raw position', () {
      expect(kalman.isInitialized, isFalse);
      const firstFix = LatLng(12.9716, 77.5946);

      final smoothed = kalman.filter(firstFix, 4.0, 0.0, 1000);

      expect(kalman.isInitialized, isTrue);
      expect(smoothed.latitude, equals(firstFix.latitude));
      expect(smoothed.longitude, equals(firstFix.longitude));
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
    });

    test('TC4.2: Low-accuracy fix has higher measurement noise R and smaller state update gain', () {
      const p1 = LatLng(12.9716, 77.5946);
      kalman.filter(p1, 3.0, 10.0, 1000);

      // High-accuracy fix (accuracy = 3.0m)
      const p2HighAcc = LatLng(12.9718, 77.5946);
      final highAccSmoothed = kalman.filter(p2HighAcc, 3.0, 10.0, 2000);
      final double deltaHighAcc = (highAccSmoothed.latitude - p1.latitude).abs();

      // Reset and test low-accuracy fix (accuracy = 50.0m) with same physical displacement
      kalman.reset();
      kalman.filter(p1, 3.0, 10.0, 1000);
      const p2LowAcc = LatLng(12.9718, 77.5946);
      final lowAccSmoothed = kalman.filter(p2LowAcc, 50.0, 10.0, 2000);
      final double deltaLowAcc = (lowAccSmoothed.latitude - p1.latitude).abs();

      // The filter trusts the high-accuracy fix more than the degraded fix
      expect(deltaHighAcc, greaterThan(deltaLowAcc));
    });

    test('TC4.3: Process noise adapts dynamically to velocity threshold (0.5 m/s)', () {
      const p1 = LatLng(12.9716, 77.5946);
      kalman.filter(p1, 5.0, 0.0, 1000); // speed = 0.0 m/s (stationary)

      // Slight noise while stationary
      const noisyDrift = LatLng(12.97162, 77.5946);
      final smoothedStationary = kalman.filter(noisyDrift, 8.0, 0.0, 2000);

      // Verify the filter heavily damps stationary drift
      final double driftLat = (smoothedStationary.latitude - p1.latitude).abs();
      expect(driftLat, lessThan(0.000015));
    });

    test('TC4.4: Spatial smoothing dampens zigzag jitter along a straight line trajectory', () {
      const baseLat = 12.9716;
      const baseLng = 77.5946;

      kalman.filter(const LatLng(baseLat, baseLng), 4.0, 10.0, 1000);

      // Sequence with lateral alternating noise
      final rawPoints = [
        const LatLng(baseLat + 0.0001, baseLng + 0.00008), // right jitter
        const LatLng(baseLat + 0.0002, baseLng - 0.00007), // left jitter
        const LatLng(baseLat + 0.0003, baseLng + 0.00009), // right jitter
        const LatLng(baseLat + 0.0004, baseLng - 0.00008), // left jitter
      ];

      final smoothedLngs = <double>[];
      for (int i = 0; i < rawPoints.length; i++) {
        final smoothed = kalman.filter(rawPoints[i], 6.0, 10.0, 2000 + i * 1000);
        smoothedLngs.add(smoothed.longitude);
      }

      // Smoothed points should have less lateral dispersion than raw jitter
      final rawDevMax = rawPoints.map((p) => (p.longitude - baseLng).abs()).reduce((a, b) => a > b ? a : b);
      final smoothedDevMax = smoothedLngs.map((lng) => (lng - baseLng).abs()).reduce((a, b) => a > b ? a : b);

      expect(smoothedDevMax, lessThan(rawDevMax));
    });

    test('TC4.5: Velocity prediction estimates coordinate progression across delta time', () {
      const p1 = LatLng(12.9716, 77.5946);
      kalman.filter(p1, 3.0, 15.0, 1000);

      const p2 = LatLng(12.9718, 77.5946); // moved North
      kalman.filter(p2, 3.0, 15.0, 2000);

      // Verify velocity state is positive in North direction
      expect(kalman.velocityMps, greaterThan(5.0));
    });

    test('TC4.6: Reset completely reinitializes filter states', () {
      kalman.filter(const LatLng(12.0, 77.0), 3.0, 5.0, 1000);
      expect(kalman.isInitialized, isTrue);

      kalman.reset();
      expect(kalman.isInitialized, isFalse);
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
      expect(kalman.velocityMps, equals(0.0));
    });

    test('TC4.7: Clock rollback anomaly (dt < -1.0s) cleanly triggers reference origin re-anchoring', () {
      // 1. Initial fix anchors origin at t = 10000 ms
      const initialFix = LatLng(12.97160, 77.59460);
      final firstResult = kalman.filter(initialFix, 4.0, 5.0, 10000);

      expect(kalman.isInitialized, isTrue);
      expect(firstResult.latitude, equals(initialFix.latitude));
      expect(firstResult.longitude, equals(initialFix.longitude));
      expect(kalman.refLat, equals(initialFix.latitude));
      expect(kalman.refLng, equals(initialFix.longitude));
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
      expect(kalman.velocityMps, equals(0.0));

      // 2. Advance time normally to t = 11000 ms (dt = +1.0s) with displacement North
      const movingFix = LatLng(12.97170, 77.59460);
      final movingResult = kalman.filter(movingFix, 4.0, 5.0, 11000);

      expect(movingResult.latitude, greaterThan(initialFix.latitude));
      expect(kalman.refLat, equals(initialFix.latitude));
      expect(kalman.posY, greaterThan(0.0));
      expect(kalman.velY, greaterThan(0.0));

      // 3. Inject negative clock rollback: t = 8000 ms (dt = -3.0s < -1.0s) at a distinct location
      const rollbackFix = LatLng(12.97300, 77.59500);
      final rollbackResult = kalman.filter(rollbackFix, 4.0, 0.0, 8000);

      // Assert clean origin re-anchoring defense:
      expect(rollbackResult.latitude, equals(rollbackFix.latitude));
      expect(rollbackResult.longitude, equals(rollbackFix.longitude));
      expect(kalman.refLat, equals(rollbackFix.latitude));
      expect(kalman.refLng, equals(rollbackFix.longitude));
      expect(kalman.referenceOrigin?.latitude, equals(rollbackFix.latitude));
      expect(kalman.referenceOrigin?.longitude, equals(rollbackFix.longitude));
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
      expect(kalman.velX, equals(0.0));
      expect(kalman.velY, equals(0.0));
      expect(kalman.velocityMps, equals(0.0));
      expect(kalman.isInitialized, isTrue);

      // 4. Contrast check: Minor clock jitter (dt >= -1.0s) should NOT reset origin
      // Fix at t = 7950 ms (dt = -0.05s >= -1.0s)
      const jitterFix = LatLng(12.97302, 77.59500);
      final jitterResult = kalman.filter(jitterFix, 4.0, 0.0, 7950);

      // Origin should remain anchored at rollbackFix, NOT jitterFix
      expect(kalman.refLat, equals(rollbackFix.latitude));
      expect(kalman.refLng, equals(rollbackFix.longitude));
      expect(jitterResult.latitude.isFinite, isTrue);
    });
  });
}
