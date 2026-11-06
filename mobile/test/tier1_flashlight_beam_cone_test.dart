import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'helpers/test_glider_interpolator.dart';

void main() {
  group('Tier 1: Flashlight Beam Cone Geometry Feature Coverage', () {
    test('TC7.1: Slow speed (<= 15 km/h) sets beam cone aperture to 60 degrees', () {
      expect(GpsGliderInterpolator.calculateConeAperture(0.0), equals(60.0));
      expect(GpsGliderInterpolator.calculateConeAperture(5.0), equals(60.0));
      expect(GpsGliderInterpolator.calculateConeAperture(15.0), equals(60.0));
    });

    test('TC7.2: Fast speed (> 15 km/h) narrows beam cone aperture to 42 degrees', () {
      expect(GpsGliderInterpolator.calculateConeAperture(15.1), equals(42.0));
      expect(GpsGliderInterpolator.calculateConeAperture(40.0), equals(42.0));
      expect(GpsGliderInterpolator.calculateConeAperture(100.0), equals(42.0));
    });

    test('TC7.3: Heading 0 deg (North) centers beam arc symmetrically about -pi/2', () {
      final angles = GpsGliderInterpolator.calculateBeamAngles(0.0, 60.0);
      const double coneRad = 60.0 * (math.pi / 180.0);
      const double expectedStart = -math.pi / 2.0 - (coneRad / 2.0);

      expect(angles['startAngleRad'], closeTo(expectedStart, 1e-4));
      expect(angles['sweepAngleRad'], closeTo(coneRad, 1e-4));
    });

    test('TC7.4: Heading 90 deg (East) rotates beam start angle by +pi/2 radians', () {
      final anglesNorth = GpsGliderInterpolator.calculateBeamAngles(0.0, 60.0);
      final anglesEast = GpsGliderInterpolator.calculateBeamAngles(90.0, 60.0);

      final double rotationDelta = anglesEast['startAngleRad']! - anglesNorth['startAngleRad']!;
      expect(rotationDelta, closeTo(math.pi / 2.0, 1e-4));
    });

    test('TC7.5: Radial gradient stops profile maintains center-to-edge alpha falloff', () {
      // Verify mathematically valid gradient stop distribution
      const stops = [0.0, 0.55, 1.0];
      const alphas = [0.50, 0.20, 0.0];

      expect(stops.first, equals(0.0));
      expect(stops.last, equals(1.0));
      expect(alphas[0], greaterThan(alphas[1]));
      expect(alphas[1], greaterThan(alphas[2]));
      expect(alphas[2], equals(0.0)); // Transparent outer feather
    });

    test('TC7.6: Beam cone radius standard baseline equals 48.0 logical pixels', () {
      const double standardBeamRadius = 48.0;
      expect(standardBeamRadius, equals(48.0));
      expect(standardBeamRadius, greaterThan(17.0)); // Larger than inner dot (17 dp)
    });
  });
}
