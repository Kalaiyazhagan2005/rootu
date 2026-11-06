import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'helpers/test_fixtures.dart';
import 'helpers/test_glider_interpolator.dart';
import 'helpers/test_heading_fusion.dart';
import 'helpers/test_kalman_filter.dart';

void main() {
  group('Tier 4: Real-World Workload Scenarios', () {
    test('TC4.W1: Simulated 20-waypoint commuter route end-to-end execution', () {
      final route = TestFixtures.commuterRouteTelemetry;
      expect(route.length, equals(20));

      final kalman = GpsKalmanFilter();
      final fusion = DynamicHeadingFusion();
      final glider = SimulatedGpsGlider();

      final smoothedPositions = <LatLng>[];
      final fusedHeadings = <double>[];

      for (final telemetry in route) {
        final timeMs = telemetry.timestamp.millisecondsSinceEpoch;
        final speedMps = telemetry.speedKmh / 3.6;

        // 1. Spatial smoothing
        final smoothed = kalman.filter(
          telemetry.position,
          telemetry.accuracyMeters,
          speedMps,
          timeMs,
        );
        smoothedPositions.add(smoothed);

        // 2. Heading fusion
        final fusedH = fusion.update(
          telemetry.heading,
          telemetry.speedKmh > 3.6 ? telemetry.heading : -1.0,
          telemetry.speedKmh,
        );
        fusedHeadings.add(fusedH);

        // 3. Glider ingestion
        final processedTelemetry = telemetry.copyWith(
          position: smoothed,
          heading: fusedH,
        );
        glider.onNewTelemetry(processedTelemetry, timestampMs: timeMs);

        // 4. Tick through 60 FPS interpolation
        glider.tick(0.5);
        expect(glider.currentPosition!.latitude.isFinite, isTrue);
        expect(glider.currentPosition!.longitude.isFinite, isTrue);
        glider.tick(1.0);
      }

      // Final waypoint is stationary at red light facing South (180 deg)
      expect(glider.currentSpeedKmh, equals(0.0));
      expect(fusedHeadings.last, closeTo(180.0, 10.0));
      expect(smoothedPositions.length, equals(20));
    });

    test('TC4.W2: Urban canyon multipath jitter reduction achieves >= 50% lateral stabilization', () {
      final sequence = TestFixtures.urbanCanyonJitterSequence;
      final kalman = GpsKalmanFilter();

      const metersPerLatDegree = 111139.0;
      final metersPerLngDegree = metersPerLatDegree * math.cos(TestFixtures.originLat * math.pi / 180.0);

      final rawDeviations = <double>[];
      final smoothedDeviations = <double>[];

      for (int i = 0; i < sequence.length; i++) {
        final t = sequence[i];
        final timeMs = t.timestamp.millisecondsSinceEpoch;
        final speedMps = t.speedKmh / 3.6;

        final smoothed = kalman.filter(t.position, t.accuracyMeters, speedMps, timeMs);

        // Calculate lateral deviation in meters from nominal longitude line
        final rawLatDev = (t.position.longitude - TestFixtures.originLng).abs() * metersPerLngDegree;
        final smoothedLatDev = (smoothed.longitude - TestFixtures.originLng).abs() * metersPerLngDegree;

        rawDeviations.add(rawLatDev);
        if (i >= 3) {
          // Exclude initial filter convergence steps for fair variance evaluation
          smoothedDeviations.add(smoothedLatDev);
        }
      }

      final meanRawDev = rawDeviations.reduce((a, b) => a + b) / rawDeviations.length;
      final meanSmoothedDev = smoothedDeviations.reduce((a, b) => a + b) / smoothedDeviations.length;

      // Assert lateral deviation is substantially damped by the filter (>= 50% jitter reduction)
      final double reductionPercent = ((meanRawDev - meanSmoothedDev) / meanRawDev) * 100.0;
      expect(reductionPercent, greaterThanOrEqualTo(50.0));
    });

    test('TC4.W3: Indoor stationary holding suppresses marker drift and stabilizes micro-compass jitter', () {
      final sequence = TestFixtures.indoorStationarySequence;
      final kalman = GpsKalmanFilter();
      final compassFilter = CircularLowPassFilter(beta: 0.15);

      const metersPerLatDegree = 111139.0;
      final rawHeadings = <double>[];
      final smoothedHeadings = <double>[];

      for (final t in sequence) {
        final timeMs = t.timestamp.millisecondsSinceEpoch;
        final smoothed = kalman.filter(t.position, t.accuracyMeters, 0.0, timeMs);

        // Marker position drift from true origin in meters
        final driftMeters = (smoothed.latitude - TestFixtures.originLat).abs() * metersPerLatDegree;
        expect(driftMeters, lessThan(2.0)); // Suppressed within 2 meters

        rawHeadings.add(t.heading);
        smoothedHeadings.add(compassFilter.filter(t.heading));
      }

      // Compass jitter variance reduction
      final rawMean = rawHeadings.reduce((a, b) => a + b) / rawHeadings.length;
      final rawVariance = rawHeadings.map((h) => math.pow(h - rawMean, 2)).reduce((a, b) => a + b) / rawHeadings.length;

      final smoothedMean = smoothedHeadings.reduce((a, b) => a + b) / smoothedHeadings.length;
      final smoothedVariance = smoothedHeadings.map((h) => math.pow(h - smoothedMean, 2)).reduce((a, b) => a + b) / smoothedHeadings.length;

      expect(smoothedVariance, lessThan(rawVariance));
    });

    test('TC4.W4: Codebase zero emojis compliance automated audit', () {
      final testDir = Directory('test');
      expect(testDir.existsSync(), isTrue);

      final emojiRegex = RegExp(
        r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F700}-\u{1F77F}]|[\u{1F780}-\u{1F7FF}]|[\u{1F800}-\u{1F8FF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
        unicode: true,
      );

      final dartFiles = testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      int filesChecked = 0;
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final matches = emojiRegex.allMatches(content);
        expect(
          matches.isEmpty,
          isTrue,
          reason: 'Emoji detected in ${file.path}: ${matches.map((m) => m.group(0)).toList()}',
        );
        filesChecked++;
      }

      expect(filesChecked, greaterThanOrEqualTo(10));
    });
  });
}
