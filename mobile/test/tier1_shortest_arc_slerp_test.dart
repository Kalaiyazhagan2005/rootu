import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_glider_interpolator.dart';

void main() {
  group('Tier 1: Shortest-Arc Slerp Feature Coverage', () {
    test('TC6.1: Clockwise boundary transition from 355 deg to 5 deg rotates +10 deg through 0 deg', () {
      final atQuarter = GpsGliderInterpolator.slerpHeading(355.0, 5.0, 0.25);
      final atHalf = GpsGliderInterpolator.slerpHeading(355.0, 5.0, 0.50);
      final atThreeQuarters = GpsGliderInterpolator.slerpHeading(355.0, 5.0, 0.75);

      expect(atQuarter, closeTo(357.5, 1e-4));
      // At half, wraps across 360 deg to 0 deg
      expect(atHalf == 0.0 || atHalf == 360.0, isTrue);
      expect(atThreeQuarters, closeTo(2.5, 1e-4));
    });

    test('TC6.2: Counter-clockwise boundary transition from 5 deg to 355 deg rotates -10 deg', () {
      final atQuarter = GpsGliderInterpolator.slerpHeading(5.0, 355.0, 0.25);
      final atHalf = GpsGliderInterpolator.slerpHeading(5.0, 355.0, 0.50);
      final atThreeQuarters = GpsGliderInterpolator.slerpHeading(5.0, 355.0, 0.75);

      expect(atQuarter, closeTo(2.5, 1e-4));
      expect(atHalf == 0.0 || atHalf == 360.0, isTrue);
      expect(atThreeQuarters, closeTo(357.5, 1e-4));
    });

    test('TC6.3: Midpoint interpolation at t = 0.5 between 350 deg and 10 deg yields North (0 deg)', () {
      final midpoint = GpsGliderInterpolator.slerpHeading(350.0, 10.0, 0.50);
      expect(midpoint == 0.0 || midpoint == 360.0, isTrue);
    });

    test('TC6.4: Identical start and target angles produce identical value across all t', () {
      const angle = 217.4;
      for (double t = 0.0; t <= 1.0; t += 0.2) {
        final result = GpsGliderInterpolator.slerpHeading(angle, angle, t);
        expect(result, closeTo(angle, 1e-4));
      }
    });

    test('TC6.5: Direct linear rotation within a quadrant progresses monotonically', () {
      const start = 30.0;
      const target = 60.0;

      double previous = start;
      for (double t = 0.1; t <= 1.0; t += 0.1) {
        final current = GpsGliderInterpolator.slerpHeading(start, target, t);
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
      expect(previous, closeTo(target, 1e-4));
    });

    test('TC6.6: Antipodal 180 deg turn rotates predictably without NaN or infinite loops', () {
      const start = 0.0;
      const target = 180.0;

      final atHalf = GpsGliderInterpolator.slerpHeading(start, target, 0.5);
      expect(atHalf.isFinite, isTrue);
      expect(atHalf >= 0.0 && atHalf < 360.0, isTrue);
    });
  });
}
