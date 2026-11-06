import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_heading_fusion.dart';

void main() {
  group('Tier 1: Dynamic Heading Fusion Feature Coverage', () {
    late DynamicHeadingFusion fusion;

    setUp(() {
      fusion = DynamicHeadingFusion();
    });

    test('TC5.1: Stationary speed (<= 3.6 km/h) uses 100% compass heading', () {
      final heading = fusion.update(45.0, 180.0, 0.0);

      expect(heading, closeTo(45.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(0.0));
    });

    test('TC5.2: Cruising speed (>= 10.8 km/h) uses 100% GPS course bearing', () {
      final heading = fusion.update(45.0, 180.0, 25.0);

      expect(heading, closeTo(180.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(1.0));
    });

    test('TC5.3: Intermediate speed (7.2 km/h) calculates 50% linear slerp blend', () {
      // 7.2 km/h is midway between 3.6 km/h and 10.8 km/h
      // Compass = 90 deg, GPS = 180 deg -> midway should be ~135 deg
      final heading = fusion.update(90.0, 180.0, 7.2);

      expect(fusion.lastGpsWeight, closeTo(0.5, 1e-4));
      expect(heading, closeTo(135.0, 1e-1));
    });

    test('TC5.4: Fallback to compass when GPS bearing is unavailable or negative', () {
      final heading = fusion.update(120.0, -1.0, 50.0); // GPS bearing is -1.0 (invalid)

      expect(heading, closeTo(120.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(0.0));
    });

    test('TC5.5: Fallback to GPS bearing when compass heading is unavailable', () {
      final heading = fusion.update(-1.0, 270.0, 0.0); // Compass unavailable

      expect(heading, closeTo(270.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(1.0));
    });

    test('TC5.6: Circular low-pass filter eliminates micro-jitter from magnetic compass', () {
      final filter = CircularLowPassFilter(beta: 0.20);

      // Initialize filter with 45.0 degrees
      filter.filter(45.0);

      // Micro-jitter of +5 degrees
      final smoothed = filter.filter(50.0);

      // Result should be damped between 45.0 and 50.0 (~46.0)
      expect(smoothed, greaterThan(45.0));
      expect(smoothed, lessThan(47.5));
    });
  });
}
