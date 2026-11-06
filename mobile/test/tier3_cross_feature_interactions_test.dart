import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'helpers/test_glider_interpolator.dart';
import 'helpers/test_heading_fusion.dart';
import 'helpers/test_kalman_filter.dart';

void main() {
  group('Tier 3: Cross-Feature Interactions Integration Testing', () {
    test('TC3.I1: Kalman Filter + Glider Controller end-to-end continuous pipeline', () {
      final kalman = GpsKalmanFilter();
      final glider = SimulatedGpsGlider();

      final rawCoordinates = [
        const LatLng(12.9716, 77.5946),
        const LatLng(12.9717, 77.5947),
        const LatLng(12.9718, 77.5948),
      ];

      for (int i = 0; i < rawCoordinates.length; i++) {
        final smoothed = kalman.filter(rawCoordinates[i], 4.0, 10.0, 1000 + i * 1000);
        final telemetry = GpsTelemetry(
          position: smoothed,
          accuracyMeters: 4.0,
          altitudeMeters: 920.0,
          speedKmh: 36.0,
          heading: 45.0,
          isMocked: false,
          sourceDescription: 'TEST',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000 + i * 1000),
        );
        glider.onNewTelemetry(telemetry, timestampMs: 1000 + i * 1000);

        // Advance 60 FPS simulation ticks
        glider.tick(0.5);
        expect(glider.currentPosition, isNotNull);
        glider.tick(1.0);
      }

      expect(glider.hasFix, isTrue);
      expect(glider.currentPosition!.latitude, closeTo(12.9718, 1e-4));
      expect(glider.currentPosition!.longitude, closeTo(77.5948, 1e-4));
    });

    test('TC3.I2: Dynamic heading smooth handoff during complete stop-and-go acceleration cycle', () {
      final fusion = DynamicHeadingFusion();

      // Step 1: Stopped at red light (speed = 0 km/h, pointing East at 90 deg via compass)
      final h1 = fusion.update(90.0, -1.0, 0.0);
      expect(h1, closeTo(90.0, 1e-4));
      expect(fusion.lastGpsWeight, equals(0.0));

      // Step 2: Accelerating past 3.6 km/h (speed = 5.4 km/h, compass = 90 deg, GPS bearing = 120 deg)
      final h2 = fusion.update(90.0, 120.0, 5.4);
      // In transition zone: weight = (5.4 - 3.6) / 7.2 = 0.25 -> heading blends ~97.5 deg
      expect(fusion.lastGpsWeight, closeTo(0.25, 1e-3));
      expect(h2, closeTo(97.5, 1.0));

      // Step 3: Cruising at highway speed (speed = 60 km/h, GPS bearing dominates = 120 deg)
      final h3 = fusion.update(95.0, 120.0, 60.0);
      expect(fusion.lastGpsWeight, equals(1.0));
      expect(h3, closeTo(120.0, 1e-4));

      // Step 4: Decelerating back to stop (speed = 0 km/h, compass points 92 deg)
      final h4 = fusion.update(92.0, 120.0, 0.0);
      expect(fusion.lastGpsWeight, equals(0.0));
      expect(h4, closeTo(92.0, 1.0));
    });

    test('TC3.I3: Accuracy circle smoothly resizes during indoor fix degradation', () {
      final glider = SimulatedGpsGlider();

      // Fix 1: Outdoor sky lock (accuracy = 3.5m)
      final t1 = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 3.5,
        altitudeMeters: 920.0,
        speedKmh: 0.0,
        heading: 0.0,
        isMocked: false,
        sourceDescription: 'OUTDOOR',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      glider.onNewTelemetry(t1, timestampMs: 1000);
      expect(glider.currentAccuracy, closeTo(3.5, 1e-2));

      // Fix 2: Entering basement parking (accuracy degrades to 45.0m)
      final t2 = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 45.0,
        altitudeMeters: 915.0,
        speedKmh: 0.0,
        heading: 0.0,
        isMocked: false,
        sourceDescription: 'PARKING',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      glider.onNewTelemetry(t2, timestampMs: 2000);

      // Halfway through 60 FPS transition, accuracy circle expands smoothly
      glider.tick(0.5);
      expect(glider.currentAccuracy, closeTo(24.25, 1.0));

      // Completion of transition
      glider.tick(1.0);
      expect(glider.currentAccuracy, closeTo(45.0, 1e-2));
    });

    test('TC3.I4: Glider continuous start-point interpolation prevents snapping on mid-flight fix', () {
      final glider = SimulatedGpsGlider();

      // Point A
      glider.onNewTelemetry(
        GpsTelemetry(
          position: const LatLng(12.000, 77.000),
          accuracyMeters: 5.0,
          altitudeMeters: 100.0,
          speedKmh: 30.0,
          heading: 0.0,
          isMocked: false,
          sourceDescription: 'A',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
        timestampMs: 1000,
      );

      // Target B
      glider.onNewTelemetry(
        GpsTelemetry(
          position: const LatLng(12.010, 77.010),
          accuracyMeters: 5.0,
          altitudeMeters: 100.0,
          speedKmh: 30.0,
          heading: 0.0,
          isMocked: false,
          sourceDescription: 'B',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
        timestampMs: 2000,
      );

      // Glider advances to 60% progress towards Point B
      glider.tick(0.60);
      final midPosition = glider.currentPosition!;
      expect(midPosition.latitude, closeTo(12.006, 1e-4));

      // Early fix arrives (Point C) before Point B finishes animating
      glider.onNewTelemetry(
        GpsTelemetry(
          position: const LatLng(12.020, 77.020),
          accuracyMeters: 5.0,
          altitudeMeters: 100.0,
          speedKmh: 30.0,
          heading: 0.0,
          isMocked: false,
          sourceDescription: 'C',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2600),
        ),
        timestampMs: 2600,
      );

      // Immediately upon new fix arrival, current position must NOT jump back to A or B
      glider.tick(0.0);
      expect(glider.currentPosition!.latitude, closeTo(midPosition.latitude, 1e-5));
      expect(glider.currentPosition!.longitude, closeTo(midPosition.longitude, 1e-5));
    });
  });
}
