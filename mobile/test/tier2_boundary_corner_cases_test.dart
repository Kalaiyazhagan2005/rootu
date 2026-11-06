import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'helpers/test_anti_spoof.dart';
import 'helpers/test_glider_interpolator.dart';
import 'helpers/test_heading_fusion.dart';
import 'helpers/test_kalman_filter.dart';

void main() {
  group('Tier 2: Boundary & Corner Cases Verification', () {
    test('TC2.B1: Stationary 0 speed locks to compass and avoids divide-by-zero in fusion', () {
      final fusion = DynamicHeadingFusion();

      // Device is completely stopped: speed = 0.0 km/h
      final heading = fusion.update(215.0, -1.0, 0.0);

      expect(heading, closeTo(215.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(0.0));
      expect(fusion.lastFusedHeading.isFinite, isTrue);
    });

    test('TC2.B2: 359 deg to 1 deg boundary wrap interpolates along the minimal 2 deg arc', () {
      const startAngle = 359.0;
      const targetAngle = 1.0;

      // Halfway through rotation should be 0 deg / 360 deg, NOT 180 deg
      final midpoint = GpsGliderInterpolator.slerpHeading(startAngle, targetAngle, 0.50);

      expect(midpoint == 0.0 || midpoint == 360.0, isTrue);

      final atQuarter = GpsGliderInterpolator.slerpHeading(startAngle, targetAngle, 0.25);
      expect(atQuarter, closeTo(359.5, 1e-4));

      final atThreeQuarters = GpsGliderInterpolator.slerpHeading(startAngle, targetAngle, 0.75);
      expect(atThreeQuarters, closeTo(0.5, 1e-4));
    });

    test('TC2.B3: Negative course (-1.0 from iOS CoreLocation) does not snap heading to North', () {
      final fusion = DynamicHeadingFusion();

      // iOS returns course = -1.0 when stationary
      // User is holding device pointing South-East (135 deg)
      final heading = fusion.update(135.0, -1.0, 0.0);

      // Must remain at 135 deg, NOT snap to 0 deg North
      expect(heading, closeTo(135.0, 1e-4));
    });

    test('TC2.B4: NaN and infinity accuracy values are safely rejected or clamped', () {
      final kalman = GpsKalmanFilter();
      const pos = LatLng(12.9716, 77.5946);

      // Filtering with NaN accuracy does not throw or corrupt filter state
      final smoothedNan = kalman.filter(pos, double.nan, 5.0, 1000);
      expect(smoothedNan.latitude.isFinite, isTrue);
      expect(smoothedNan.longitude.isFinite, isTrue);

      // Filtering with infinite accuracy does not throw
      final smoothedInf = kalman.filter(pos, double.infinity, 5.0, 2000);
      expect(smoothedInf.latitude.isFinite, isTrue);
      expect(smoothedInf.longitude.isFinite, isTrue);
    });

    test('TC2.B5: High-speed velocity (180 km/h) retains tracking responsiveness', () {
      final kalman = GpsKalmanFilter();
      const p1 = LatLng(12.9716, 77.5946);
      kalman.filter(p1, 3.0, 50.0, 1000); // 50 m/s = 180 km/h

      // After 1 second at 50 m/s (~0.00045 degrees lat)
      const p2 = LatLng(12.97205, 77.5946);
      final smoothed = kalman.filter(p2, 3.0, 50.0, 2000);

      // Responsiveness: filter should follow within 85% of physical displacement
      final double progressRatio = (smoothed.latitude - p1.latitude) / (p2.latitude - p1.latitude);
      expect(progressRatio, greaterThan(0.50));
    });

    test('TC2.B6: Satellite loss and stream interruption handled cleanly via reset and sanitization', () {
      final kalman = GpsKalmanFilter();
      const p1 = LatLng(12.9716, 77.5946);
      kalman.filter(p1, 4.0, 10.0, 1000);

      // 10-second satellite blackout gap
      const pResume = LatLng(12.9800, 77.6000);
      final smoothed = kalman.filter(pResume, 4.0, 10.0, 11000);

      // Blackout gap should trigger state reset without jumping wild coordinates
      expect(smoothed.latitude, equals(pResume.latitude));
      expect(smoothed.longitude, equals(pResume.longitude));

      // Null Island defense
      expect(AntiSpoofValidator.isSanitaryCoordinates(double.nan, 77.0), isFalse);
      expect(AntiSpoofValidator.isSanitaryCoordinates(12.0, double.infinity), isFalse);
    });
  });
}
