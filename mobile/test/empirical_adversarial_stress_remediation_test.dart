import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'package:rootu_mobile/features/map/services/gps_kalman_filter.dart';
import 'package:rootu_mobile/features/map/services/gps_pipeline_service.dart';

void main() {
  group('Empirical Challenger Remediation Stress Test Suite', () {
    // -------------------------------------------------------------------------
    // SECTION 1: GpsKalmanFilter Clock Rollback Stress Tests
    // -------------------------------------------------------------------------
    group('GpsKalmanFilter Clock Rollback Anomalies', () {
      late GpsKalmanFilter kalman;

      setUp(() {
        kalman = GpsKalmanFilter();
      });

      test('Rollback dt = -5.0s triggers origin re-anchoring and resets state', () {
        const p0 = LatLng(12.9716, 77.5946);
        kalman.filter(p0, 5.0, 10.0, 10000);
        expect(kalman.isInitialized, isTrue);
        expect(kalman.refLat, equals(12.9716));
        expect(kalman.refLng, equals(77.5946));

        // Advance 2 seconds
        const p1 = LatLng(12.9718, 77.5948);
        kalman.filter(p1, 5.0, 10.0, 12000);

        // Rollback by -5.0s (timestamp 7000ms vs previous 12000ms: rawDt = -5.0s)
        const pRollback = LatLng(12.9750, 77.5980);
        final out = kalman.filter(pRollback, 8.0, 0.0, 7000);

        // Expect immediate re-anchoring to pRollback
        expect(out.latitude, equals(12.9750));
        expect(out.longitude, equals(77.5980));
        expect(kalman.refLat, equals(12.9750));
        expect(kalman.refLng, equals(77.5980));
        expect(kalman.posX, equals(0.0));
        expect(kalman.posY, equals(0.0));
        expect(kalman.velocityMps, equals(0.0));
      });

      test('Rollback dt = -10.0s triggers origin re-anchoring and resets state', () {
        const p0 = LatLng(12.9716, 77.5946);
        kalman.filter(p0, 5.0, 5.0, 20000);

        // Rollback by -10.0s (timestamp 10000ms vs previous 20000ms: rawDt = -10.0s)
        const pRollback = LatLng(12.9800, 77.5900);
        final out = kalman.filter(pRollback, 12.0, 2.0, 10000);

        expect(out.latitude, equals(12.9800));
        expect(out.longitude, equals(77.5900));
        expect(kalman.refLat, equals(12.9800));
        expect(kalman.refLng, equals(77.5900));
        expect(kalman.posX, equals(0.0));
        expect(kalman.posY, equals(0.0));
        expect(kalman.velocityMps, equals(0.0));
      });

      test('Rollback dt = -100.0s triggers origin re-anchoring and resets state', () {
        const p0 = LatLng(12.9716, 77.5946);
        kalman.filter(p0, 5.0, 15.0, 150000);

        // Rollback by -100.0s (timestamp 50000ms vs previous 150000ms: rawDt = -100.0s)
        const pRollback = LatLng(13.0000, 77.6000);
        final out = kalman.filter(pRollback, 10.0, 0.0, 50000);

        expect(out.latitude, equals(13.0000));
        expect(out.longitude, equals(77.6000));
        expect(kalman.refLat, equals(13.0000));
        expect(kalman.refLng, equals(77.6000));
        expect(kalman.posX, equals(0.0));
        expect(kalman.posY, equals(0.0));
        expect(kalman.velocityMps, equals(0.0));
      });

      test('Boundary test: dt = -1.001s triggers re-anchoring, dt = -0.999s preserves origin', () {
        const p0 = LatLng(12.9716, 77.5946);
        kalman.filter(p0, 5.0, 0.0, 10000);

        // dt = -0.999s (timestamp 9001ms vs 10000ms)
        // rawDt = -0.999s, which is >= -1.0s, so it is treated as minor jitter (NOT blackout gap)
        const pJitter = LatLng(12.97161, 77.59461);
        final outJitter = kalman.filter(pJitter, 5.0, 0.0, 9001);
        expect(kalman.refLat, equals(12.9716),
            reason: 'dt = -0.999s must NOT re-anchor origin; it should be absorbed as jitter');
        expect(outJitter.latitude.isFinite, isTrue);
        expect(outJitter.longitude.isFinite, isTrue);

        // Reset and test dt = -1.001s (timestamp 8999ms vs 10000ms)
        kalman.reset();
        kalman.filter(p0, 5.0, 0.0, 10000);
        const pAnomaly = LatLng(12.9720, 77.5950);
        final outAnomaly = kalman.filter(pAnomaly, 5.0, 0.0, 8999);
        expect(kalman.refLat, equals(12.9720),
            reason: 'dt = -1.001s must trigger re-anchoring');
        expect(outAnomaly.latitude, equals(12.9720));
        expect(outAnomaly.longitude, equals(77.5950));
      });
    });

    // -------------------------------------------------------------------------
    // SECTION 2: GpsKalmanFilter Positive Burst Jitter & Velocity Spikes
    // -------------------------------------------------------------------------
    group('GpsKalmanFilter Positive Burst Jitter Defense', () {
      late GpsKalmanFilter kalman;

      setUp(() {
        kalman = GpsKalmanFilter();
      });

      test('High-frequency burst jitter at dt = 0.001s (1ms) does not cause velocity spikes', () {
        const origin = LatLng(12.9716, 77.5946);
        kalman.filter(origin, 5.0, 0.0, 1000);

        int currentTimeMs = 1000;
        double currentLat = 12.9716;
        double currentLng = 77.5946;

        // Simulate 100 burst packets arriving at 1ms intervals (dt = 0.001s)
        // with minor GPS sensor position noise (~0.1m displacement)
        for (int i = 0; i < 100; i++) {
          currentTimeMs += 1; // 1 millisecond
          final double delta = (i % 2 == 0) ? 0.000001 : -0.000001;
          final pos = LatLng(currentLat + delta, currentLng + delta);
          final smoothed = kalman.filter(pos, 5.0, 0.0, currentTimeMs);

          expect(smoothed.latitude.isFinite, isTrue);
          expect(smoothed.longitude.isFinite, isTrue);
          expect(kalman.velocityMps, lessThan(10.0),
              reason: 'Velocity must NOT spike during 1ms burst packets. Actual: ${kalman.velocityMps}');
        }
      });

      test('Burst jitter at dt = 0.005s (5ms) maintains bounded velocity', () {
        const origin = LatLng(12.9716, 77.5946);
        kalman.filter(origin, 5.0, 0.0, 1000);

        int currentTimeMs = 1000;
        for (int i = 0; i < 50; i++) {
          currentTimeMs += 5; // 5 milliseconds (dt = 0.005s)
          final double delta = (i % 2 == 0) ? 0.000002 : -0.000002;
          final pos = LatLng(12.9716 + delta, 77.5946 + delta);
          kalman.filter(pos, 5.0, 0.0, currentTimeMs);

          expect(kalman.velocityMps, lessThan(8.0),
              reason: 'Velocity must remain stable during 5ms bursts. Actual: ${kalman.velocityMps}');
        }
      });

      test('Extreme burst jitter at dt = 0.0001s (0.1ms) with large displacement is safely bounded', () {
        const origin = LatLng(12.9716, 77.5946);
        kalman.filter(origin, 5.0, 0.0, 10000);

        // Immediate packet 0.1ms later with 0.5m displacement
        const nextPos = LatLng(12.971605, 77.594605);
        kalman.filter(nextPos, 5.0, 0.0, 10000); // dt = 0s -> clamped to 0.05s
        expect(kalman.velocityMps, lessThan(15.0));

        kalman.filter(nextPos, 5.0, 0.0, 10001); // dt = 0.001s -> clamped dtVel = 0.05s
        expect(kalman.velocityMps, lessThan(15.0));
      });
    });

    // -------------------------------------------------------------------------
    // SECTION 3: GpsPipelineService Non-Finite Neutralization Stress Tests
    // -------------------------------------------------------------------------
    group('GpsPipelineService Non-Finite Neutralization Defense', () {
      late GpsPipelineService pipeline;

      setUp(() {
        pipeline = GpsPipelineService();
      });

      test('Simultaneous corruption of all fields with NaN produces 100% finite safe telemetry', () {
        final corrupted = GpsTelemetry(
          position: const LatLng(double.nan, double.nan),
          accuracyMeters: double.nan,
          altitudeMeters: double.nan,
          speedKmh: double.nan,
          heading: double.nan,
          compassHeading: double.nan,
          isMocked: false,
          sourceDescription: 'stress_test',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        );

        final processed = pipeline.processTelemetry(corrupted);

        expect(processed.position.latitude.isFinite, isTrue);
        expect(processed.position.longitude.isFinite, isTrue);
        expect(processed.position.latitude, equals(0.0));
        expect(processed.position.longitude, equals(0.0));
        expect(processed.accuracyMeters.isFinite, isTrue);
        expect(processed.accuracyMeters, equals(25.0));
        expect(processed.altitudeMeters.isFinite, isTrue);
        expect(processed.altitudeMeters, equals(0.0));
        expect(processed.speedKmh.isFinite, isTrue);
        expect(processed.speedKmh, equals(0.0));
        expect(processed.heading.isFinite, isTrue);
        expect(processed.heading, equals(0.0));
        expect(processed.compassHeading, isNull);
      });

      test('Simultaneous corruption of all fields with Infinity produces 100% finite safe telemetry', () {
        final corrupted = GpsTelemetry(
          position: const LatLng(double.infinity, double.negativeInfinity),
          accuracyMeters: double.infinity,
          altitudeMeters: double.infinity,
          speedKmh: double.infinity,
          heading: double.infinity,
          compassHeading: double.infinity,
          isMocked: false,
          sourceDescription: 'stress_test',
          timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
        );

        final processed = pipeline.processTelemetry(corrupted);

        expect(processed.position.latitude.isFinite, isTrue);
        expect(processed.position.longitude.isFinite, isTrue);
        expect(processed.accuracyMeters.isFinite, isTrue);
        expect(processed.accuracyMeters, equals(25.0));
        expect(processed.altitudeMeters.isFinite, isTrue);
        expect(processed.altitudeMeters, equals(0.0));
        expect(processed.speedKmh.isFinite, isTrue);
        expect(processed.speedKmh, equals(0.0));
        expect(processed.heading.isFinite, isTrue);
        expect(processed.heading, equals(0.0));
        expect(processed.compassHeading, isNull);
      });

      test('Negative values in accuracy, speed, compass heading are sanitized', () {
        // Case A: Both compass and heading are negative -> falls back to _lastFusedHeading (0.0)
        final corruptedBoth = GpsTelemetry(
          position: const LatLng(12.9716, 77.5946),
          accuracyMeters: -50.0,
          altitudeMeters: -100.0,
          speedKmh: -25.0,
          heading: -90.0,
          compassHeading: -45.0,
          isMocked: false,
          sourceDescription: 'stress_test',
          timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
        );

        final processedBoth = pipeline.processTelemetry(corruptedBoth);

        expect(processedBoth.position.latitude.isFinite, isTrue);
        expect(processedBoth.position.longitude.isFinite, isTrue);
        expect(processedBoth.accuracyMeters, equals(25.0));
        expect(processedBoth.altitudeMeters, equals(-100.0));
        expect(processedBoth.speedKmh, equals(0.0));
        // When both heading and compass are negative, fallback to previous heading (0.0)
        expect(processedBoth.heading, equals(0.0));
        expect(processedBoth.compassHeading, isNull);

        // Case B: Compass is negative (-1.0 uncalibrated), but GPS bearing is valid (270.0)
        final validGpsNegativeCompass = GpsTelemetry(
          position: const LatLng(12.9718, 77.5948),
          accuracyMeters: -20.0,
          altitudeMeters: -50.0,
          speedKmh: -10.0,
          heading: 270.0,
          compassHeading: -1.0,
          isMocked: false,
          sourceDescription: 'stress_test',
          timestamp: DateTime.fromMillisecondsSinceEpoch(4000),
        );

        final processedValidGps = pipeline.processTelemetry(validGpsNegativeCompass);
        expect(processedValidGps.accuracyMeters, equals(25.0));
        expect(processedValidGps.speedKmh, equals(0.0));
        expect(processedValidGps.heading, equals(270.0));
        expect(processedValidGps.compassHeading, isNull);
      });

      test('Continuous stream of 1000 randomized corrupted packets produces 100% finite stream without crash', () async {
        final random = math.Random(42);
        final rawStreamController = StreamController<GpsTelemetry>();

        final processedList = <GpsTelemetry>[];
        final subscription = pipeline.transformStream(rawStreamController.stream).listen((telemetry) {
          processedList.add(telemetry);
        });

        for (int i = 0; i < 1000; i++) {
          final double lat = random.nextBool() ? 12.9716 + (random.nextDouble() - 0.5) * 0.01 : (random.nextBool() ? double.nan : double.infinity);
          final double lng = random.nextBool() ? 77.5946 + (random.nextDouble() - 0.5) * 0.01 : (random.nextBool() ? double.nan : double.infinity);
          final double accuracy = random.nextBool() ? random.nextDouble() * 50.0 : (random.nextBool() ? double.nan : -10.0);
          final double speed = random.nextBool() ? random.nextDouble() * 100.0 : (random.nextBool() ? double.nan : -50.0);
          final double heading = random.nextBool() ? random.nextDouble() * 360.0 : (random.nextBool() ? double.nan : 999.0);
          final double? compass = random.nextBool()
              ? (random.nextBool() ? random.nextDouble() * 360.0 : null)
              : (random.nextBool() ? double.nan : -1.0);
          final double altitude = random.nextBool() ? 900.0 + random.nextDouble() * 50.0 : double.nan;

          rawStreamController.add(GpsTelemetry(
            position: LatLng(lat, lng),
            accuracyMeters: accuracy,
            altitudeMeters: altitude,
            speedKmh: speed,
            heading: heading,
            compassHeading: compass,
            isMocked: false,
            sourceDescription: 'stress_test',
            timestamp: DateTime.fromMillisecondsSinceEpoch(10000 + i * 100),
          ));
        }

        await rawStreamController.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(processedList.length, equals(1000));
        for (int i = 0; i < processedList.length; i++) {
          final t = processedList[i];
          expect(t.position.latitude.isFinite, isTrue, reason: 'Index $i latitude non-finite');
          expect(t.position.longitude.isFinite, isTrue, reason: 'Index $i longitude non-finite');
          expect(t.accuracyMeters.isFinite, isTrue, reason: 'Index $i accuracy non-finite');
          expect(t.accuracyMeters, greaterThan(0.0), reason: 'Index $i accuracy non-positive');
          expect(t.speedKmh.isFinite, isTrue, reason: 'Index $i speed non-finite');
          expect(t.speedKmh, greaterThanOrEqualTo(0.0), reason: 'Index $i speed negative');
          expect(t.heading.isFinite, isTrue, reason: 'Index $i heading non-finite');
          expect(t.heading, greaterThanOrEqualTo(0.0), reason: 'Index $i heading < 0');
          expect(t.heading, lessThan(360.0), reason: 'Index $i heading >= 360');
          expect(t.altitudeMeters.isFinite, isTrue, reason: 'Index $i altitude non-finite');
          if (t.compassHeading != null) {
            expect(t.compassHeading!.isFinite, isTrue, reason: 'Index $i compass non-finite');
            expect(t.compassHeading!, greaterThanOrEqualTo(0.0));
            expect(t.compassHeading!, lessThanOrEqualTo(360.0));
          }
        }
      });
    });
  });
}
