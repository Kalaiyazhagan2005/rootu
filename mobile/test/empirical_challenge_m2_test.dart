import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'package:rootu_mobile/features/map/services/circular_low_pass_filter.dart';
import 'package:rootu_mobile/features/map/services/dynamic_heading_fusion.dart';
import 'package:rootu_mobile/features/map/services/gps_kalman_filter.dart';
import 'package:rootu_mobile/features/map/services/gps_pipeline_service.dart';

void main() {
  group('CRITERION 1: Numerical Stability & Extreme Inputs Stress Testing', () {
    late GpsKalmanFilter kalman;
    late DynamicHeadingFusion fusion;
    late CircularLowPassFilter circular;

    setUp(() {
      kalman = GpsKalmanFilter();
      fusion = DynamicHeadingFusion();
      circular = CircularLowPassFilter();
    });

    test('STRESS 1.1: Extreme accuracy spike (500m) heavily downweights measurement', () {
      const origin = LatLng(12.9716, 77.5946);
      final p0 = kalman.filter(origin, 5.0, 10.0, 1000);
      expect(p0.latitude, closeTo(12.9716, 1e-6));
      expect(p0.longitude, closeTo(77.5946, 1e-6));

      // Move 5 meters East at 10 m/s with terrible 500m accuracy
      const raw1 = LatLng(12.9716, 77.594645);
      final p1 = kalman.filter(raw1, 500.0, 10.0, 2000);

      expect(p1.latitude.isFinite, isTrue);
      expect(p1.longitude.isFinite, isTrue);
      // Because accuracy is 500m (R = 250,000), innovation weight is negligible
      final distFromOrigin = const Distance().as(LengthUnit.Meter, origin, p1);
      expect(distFromOrigin, lessThan(3.0),
          reason: '500m accuracy spike must not drag state excessively');
    });

    test('STRESS 1.2: Sub-meter accuracy (0.1m) clamps to minimum threshold', () {
      const origin = LatLng(12.9716, 77.5946);
      kalman.filter(origin, 0.1, 5.0, 1000);

      // Verify that covariance does not collapse to zero or cause divide-by-zero
      const nextPos = LatLng(12.9717, 77.5947);
      final p1 = kalman.filter(nextPos, 0.1, 5.0, 2000);

      expect(p1.latitude.isFinite, isTrue);
      expect(p1.longitude.isFinite, isTrue);
      expect(kalman.velocityMps.isFinite, isTrue);
      expect(kalman.velocityMps, greaterThan(0.0));
    });

    test('STRESS 1.3: NaN, Infinity, negative, and zero accuracy values', () {
      const origin = LatLng(12.9716, 77.5946);
      kalman.filter(origin, 10.0, 0.0, 1000);

      final pNan = kalman.filter(const LatLng(12.97165, 77.59465), double.nan, 0.0, 2000);
      expect(pNan.latitude.isFinite, isTrue);
      expect(pNan.longitude.isFinite, isTrue);

      final pInf = kalman.filter(const LatLng(12.97170, 77.59470), double.infinity, 0.0, 3000);
      expect(pInf.latitude.isFinite, isTrue);
      expect(pInf.longitude.isFinite, isTrue);

      final pNeg = kalman.filter(const LatLng(12.97175, 77.59475), -15.0, 0.0, 4000);
      expect(pNeg.latitude.isFinite, isTrue);
      expect(pNeg.longitude.isFinite, isTrue);

      final pZero = kalman.filter(const LatLng(12.97180, 77.59480), 0.0, 0.0, 5000);
      expect(pZero.latitude.isFinite, isTrue);
      expect(pZero.longitude.isFinite, isTrue);
    });

    test('STRESS 1.4: NaN and Infinite geodetic coordinates rejected gracefully', () {
      // Prior to initialization
      final uninit = kalman.filter(const LatLng(double.nan, double.infinity), 10.0, 0.0, 1000);
      expect(uninit.latitude, equals(0.0));
      expect(uninit.longitude, equals(0.0));
      expect(kalman.isInitialized, isFalse);

      // Initialize with valid fix
      const origin = LatLng(12.9716, 77.5946);
      kalman.filter(origin, 5.0, 0.0, 2000);
      expect(kalman.isInitialized, isTrue);

      // Feed NaN latitude
      final pNan = kalman.filter(const LatLng(double.nan, 77.5946), 5.0, 0.0, 3000);
      expect(pNan.latitude.isFinite, isTrue);
      expect(pNan.longitude.isFinite, isTrue);
      expect(pNan.latitude, closeTo(12.9716, 1e-4));

      // Feed Infinite longitude
      final pInf = kalman.filter(const LatLng(12.9716, double.infinity), 5.0, 0.0, 4000);
      expect(pInf.latitude.isFinite, isTrue);
      expect(pInf.longitude.isFinite, isTrue);
      expect(pInf.longitude, closeTo(77.5946, 1e-4));
    });

    test('STRESS 1.5: NaN, Infinite, and negative speeds in Kalman filter and fusion', () {
      const origin = LatLng(12.9716, 77.5946);
      kalman.filter(origin, 5.0, double.nan, 1000);
      expect(kalman.velocityMps.isFinite, isTrue);

      kalman.filter(const LatLng(12.97161, 77.59461), 5.0, double.infinity, 2000);
      expect(kalman.velocityMps.isFinite, isTrue);

      kalman.filter(const LatLng(12.97162, 77.59462), 5.0, -25.0, 3000);
      expect(kalman.velocityMps.isFinite, isTrue);

      // Heading fusion with non-finite and negative speeds
      final h1 = fusion.update(90.0, 180.0, double.nan);
      expect(h1.isFinite, isTrue);
      expect(h1, closeTo(90.0, 1e-2), reason: 'NaN speed falls back to stationary compass');

      final h2 = fusion.update(90.0, 180.0, -10.0);
      expect(h2.isFinite, isTrue);
      expect(h2, closeTo(90.0, 1e-2), reason: 'Negative speed falls back to stationary compass');

      final h3 = fusion.update(90.0, 180.0, double.infinity);
      expect(h3.isFinite, isTrue);
    });

    test('STRESS 1.6: CircularLowPassFilter non-finite and boundary angles', () {
      expect(circular.filter(double.nan), equals(0.0));
      expect(circular.filter(double.infinity), equals(0.0));
      expect(circular.filter(double.negativeInfinity), equals(0.0));

      final first = circular.filter(45.0);
      expect(first, closeTo(45.0, 1e-3));

      // After initialization, non-finite input should return currentAngle
      expect(circular.filter(double.nan), closeTo(45.0, 1e-3));
      expect(circular.filter(double.infinity), closeTo(45.0, 1e-3));

      // Extreme out-of-range positive and negative angles
      final pos720 = circular.filter(765.0); // 765 = 2*360 + 45
      expect(pos720, closeTo(45.0, 1e-3));

      final neg315 = circular.filter(-315.0); // -315 = 45 deg
      expect(neg315, closeTo(45.0, 1e-3));
    });
  });

  group('CRITERION 2: Spatial Dynamics & Reset Defenses', () {
    late GpsKalmanFilter kalman;

    setUp(() {
      kalman = GpsKalmanFilter();
    });

    test('STRESS 2.1: Stationary locking suppresses zero-speed multipath wander', () {
      const centerLat = 12.9716;
      const centerLng = 77.5946;

      // Initialize at center
      kalman.filter(const LatLng(centerLat, centerLng), 5.0, 0.0, 1000);

      final rawDistances = <double>[];
      final smoothedDistances = <double>[];
      const distanceCalc = Distance();
      const center = LatLng(centerLat, centerLng);

      // Simulate 60 seconds of stationary GPS wander with +/- 1.5m oscillation
      for (int i = 1; i <= 60; i++) {
        final tMs = 1000 + i * 1000;
        final latOffset = (math.sin(i * 0.5) * 1.5) / 111139.0;
        final lngOffset = (math.cos(i * 0.7) * 1.5) / (111139.0 * math.cos(centerLat * math.pi / 180.0));

        final rawFix = LatLng(centerLat + latOffset, centerLng + lngOffset);
        final smoothed = kalman.filter(rawFix, 5.0, 0.0, tMs);

        rawDistances.add(distanceCalc.as(LengthUnit.Meter, center, rawFix));
        smoothedDistances.add(distanceCalc.as(LengthUnit.Meter, center, smoothed));
      }

      final double avgRawDrift = rawDistances.reduce((a, b) => a + b) / rawDistances.length;
      final double avgSmoothedDrift = smoothedDistances.reduce((a, b) => a + b) / smoothedDistances.length;

      expect(avgSmoothedDrift, lessThan(avgRawDrift),
          reason: 'Kalman stationary process noise must dampen average drift excursion');
      expect(avgSmoothedDrift, lessThan(1.5),
          reason: 'Smoothed drift must remain tightly locked under 1.5 meters');
    });

    test('STRESS 2.2: High-speed turn (120 km/h 90-degree cornering) does not reset filter', () {
      // 120 km/h = 33.33 m/s
      const double speedMps = 120.0 / 3.6;
      var currentLat = 12.9716;
      var currentLng = 77.5946;
      int tMs = 10000;

      kalman.filter(LatLng(currentLat, currentLng), 4.0, speedMps, tMs);

      // Travel East for 5 seconds at 10 Hz (100ms dt = 3.333m per step)
      final double metersPerLngDeg = 111139.0 * math.cos(currentLat * math.pi / 180.0);
      for (int i = 0; i < 50; i++) {
        tMs += 100;
        currentLng += (speedMps * 0.1) / metersPerLngDeg;
        kalman.filter(LatLng(currentLat, currentLng), 4.0, speedMps, tMs);
      }

      // Verify velocity state before turn adapted close to 33.33 m/s
      expect(kalman.velocityMps, closeTo(speedMps, 5.0),
          reason: 'Kalman velocity state should adapt to vehicle speed before cornering');

      final originBeforeTurn = kalman.referenceOrigin;

      // Sharp 90-degree North turn: now moving North at 33.33 m/s for 50 steps (5s)
      for (int i = 0; i < 50; i++) {
        tMs += 100;
        currentLat += (speedMps * 0.1) / 111139.0;
        final smoothed = kalman.filter(LatLng(currentLat, currentLng), 4.0, speedMps, tMs);

        // Filter must continue tracking without resetting reference origin
        expect(kalman.referenceOrigin, equals(originBeforeTurn),
            reason: 'High-speed 120 km/h turn must NOT trigger false teleportation reset');
        expect(smoothed.latitude.isFinite, isTrue);
        expect(smoothed.longitude.isFinite, isTrue);
      }

      // Check position lag after 5 seconds of 120 km/h North motion:
      // Coordinate error should be bounded within plausible kinematic tracking limits (< 15 meters)
      final lastSmoothed = kalman.filter(LatLng(currentLat, currentLng), 4.0, speedMps, tMs + 100);
      final double latLagMeters = (lastSmoothed.latitude - currentLat).abs() * 111139.0;
      expect(latLagMeters, lessThan(15.0),
          reason: 'Smoothed position must closely track vehicle trajectory at 120 km/h');
    });

    test('STRESS 2.3: 10-second blackout gap triggers clean reset and re-anchoring', () {
      const initialFix = LatLng(12.9716, 77.5946);
      kalman.filter(initialFix, 4.0, 5.0, 1000);
      kalman.filter(const LatLng(12.9717, 77.5947), 4.0, 5.0, 2000);

      // Blackout gap of 10.0 seconds (10,000 ms)
      const blackoutFix = LatLng(12.9740, 77.5970);
      final smoothedAfterBlackout = kalman.filter(blackoutFix, 4.0, 5.0, 12000);

      // Must re-anchor directly to blackoutFix without overshoot
      expect(smoothedAfterBlackout.latitude, equals(blackoutFix.latitude));
      expect(smoothedAfterBlackout.longitude, equals(blackoutFix.longitude));
      expect(kalman.refLat, equals(blackoutFix.latitude));
      expect(kalman.refLng, equals(blackoutFix.longitude));
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
      expect(kalman.velX, equals(0.0));
      expect(kalman.velY, equals(0.0));
    });

    test('STRESS 2.4: 200-meter anomalous teleportation triggers clean reset', () {
      const initialFix = LatLng(12.9716, 77.5946);
      kalman.filter(initialFix, 4.0, 1.0, 1000);

      // Low speed (1 m/s), dt = 1.0s, plausible displacement is 1.0 * 1.0 + 50 = 51m
      // Teleportation jump of 200 meters North
      const double latJump200m = 200.0 / 111139.0;
      final teleportFix = LatLng(initialFix.latitude + latJump200m, initialFix.longitude);

      final smoothedAfterJump = kalman.filter(teleportFix, 4.0, 1.0, 2000);

      // Must detect teleportation and re-anchor directly to teleportFix
      expect(smoothedAfterJump.latitude, equals(teleportFix.latitude));
      expect(smoothedAfterJump.longitude, equals(teleportFix.longitude));
      expect(kalman.refLat, equals(teleportFix.latitude));
      expect(kalman.refLng, equals(teleportFix.longitude));
      expect(kalman.posX, equals(0.0));
      expect(kalman.posY, equals(0.0));
    });

    test('STRESS 2.5: Clock rollback behavior empirical test', () {
      const initialFix = LatLng(12.9716, 77.5946);
      kalman.filter(initialFix, 4.0, 0.0, 10000);

      // Send a fix with clock timestamp rolled back by 5 seconds (5000 ms in the past)
      const rollbackFix = LatLng(12.97165, 77.59465);
      final smoothed = kalman.filter(rollbackFix, 4.0, 0.0, 5000);

      // Filter must handle gracefully without crashing or throwing
      expect(smoothed.latitude.isFinite, isTrue);
      expect(smoothed.longitude.isFinite, isTrue);
    });
  });

  group('CRITERION 3: Heading & Angular Boundary Stress Testing', () {
    late DynamicHeadingFusion fusion;
    late CircularLowPassFilter circular;

    setUp(() {
      fusion = DynamicHeadingFusion();
      circular = CircularLowPassFilter();
    });

    test('STRESS 3.1: North boundary wrap-around (359.9 deg <-> 0.1 deg) in CircularLowPassFilter', () {
      // Initialize with 359.9 deg
      final first = circular.filter(359.9);
      expect(first, closeTo(359.9, 1e-2));

      // Feed 0.1 deg: should smooth clockwise across 0, not counter-clockwise by 359 deg
      final second = circular.filter(0.1);
      expect(second.isFinite, isTrue);
      // beta = 0.20: angle should move from 359.9 towards 0.1 by ~20% of 0.2 deg = ~0.04 deg -> ~359.94 deg
      expect(second >= 359.8 || second <= 0.2, isTrue,
          reason: 'Circular filter must interpolate across North boundary');

      // Continuous oscillation across North
      for (int i = 0; i < 20; i++) {
        final angle = (i % 2 == 0) ? 359.5 : 0.5;
        final res = circular.filter(angle);
        expect(res >= 358.0 || res <= 2.0, isTrue,
            reason: 'Result must stay within +/- 2 deg of North, not flip to 180 deg');
      }
    });

    test('STRESS 3.2: Shortest-arc slerp across North boundary and antipodes', () {
      // 359.9 to 0.1 at t = 0.5
      final midNorth = DynamicHeadingFusion.shortestArcSlerp(359.9, 0.1, 0.5);
      expect(midNorth, closeTo(0.0, 0.05));

      // 0.1 to 359.9 at t = 0.5
      final revNorth = DynamicHeadingFusion.shortestArcSlerp(0.1, 359.9, 0.5);
      expect(revNorth, closeTo(0.0, 0.05));

      // 350 to 10 at t = 0.5
      final mid350_10 = DynamicHeadingFusion.shortestArcSlerp(350.0, 10.0, 0.5);
      expect(mid350_10, closeTo(0.0, 1e-3));

      // 10 to 350 at t = 0.5
      final rev10_350 = DynamicHeadingFusion.shortestArcSlerp(10.0, 350.0, 0.5);
      expect(rev10_350, closeTo(0.0, 1e-3));

      // Exact antipodal 180 deg transition
      final antipode = DynamicHeadingFusion.shortestArcSlerp(0.0, 180.0, 0.5);
      expect(antipode.isFinite, isTrue);
      expect(antipode >= 0.0 && antipode < 360.0, isTrue);

      // Clamp t outside [0, 1]
      expect(DynamicHeadingFusion.shortestArcSlerp(10.0, 50.0, -0.5), closeTo(10.0, 1e-3));
      expect(DynamicHeadingFusion.shortestArcSlerp(10.0, 50.0, 1.5), closeTo(50.0, 1e-3));
    });

    test('STRESS 3.3: DynamicHeadingFusion speed phase transitions and blend across North', () {
      // Phase 1 (stationary <= 3.6 km/h): 100% compass
      final hStationary = fusion.update(359.0, 90.0, 2.0);
      expect(fusion.lastGpsWeight, equals(0.0));
      expect(hStationary, closeTo(359.0, 1e-2));

      // Phase 3 (cruising >= 10.8 km/h): 100% GPS
      final hCruising = fusion.update(359.0, 90.0, 15.0);
      expect(fusion.lastGpsWeight, equals(1.0));
      expect(hCruising, closeTo(90.0, 1e-2));

      // Phase 2 (mid blend at 7.2 km/h): 50% compass (359 deg) and 50% GPS (1 deg)
      // Reset to avoid filter history
      fusion.reset();
      // First prime the filter at 359 deg
      fusion.update(359.0, 1.0, 7.2);
      final hMid = fusion.update(359.0, 1.0, 7.2);
      expect(fusion.lastGpsWeight, closeTo(0.5, 1e-3));
      // Blend between ~359 and 1.0 should be very close to 0.0 (North)
      expect(hMid >= 359.0 || hMid <= 1.0, isTrue,
          reason: 'Fused heading at 50% blend between 359 and 1 must point North');
    });

    test('STRESS 3.4: Sensor fallback cascades (null compass, negative GPS bearing, both invalid)', () {
      // 1. Compass is null, GPS is valid, at stationary speed
      fusion.reset();
      final hGpsOnly = fusion.update(null, 120.0, 0.0);
      expect(hGpsOnly, closeTo(120.0, 1e-2));
      expect(fusion.lastGpsWeight, equals(1.0));

      // 2. GPS bearing is -1.0 (iOS stationary sentinel), compass is valid, at cruising speed
      fusion.reset();
      final hCompassOnly = fusion.update(240.0, -1.0, 50.0);
      expect(hCompassOnly, closeTo(240.0, 1e-2));
      expect(fusion.lastGpsWeight, equals(0.0));

      // 3. Both sensors invalid: retain previous valid heading
      final hRetained = fusion.update(null, -1.0, 20.0);
      expect(hRetained, closeTo(hCompassOnly, 1e-2));

      // 4. Negative compass (-1.0) treated as invalid
      fusion.reset();
      final hNegCompass = fusion.update(-1.0, 315.0, 0.0);
      expect(hNegCompass, closeTo(315.0, 1e-2));
    });

    test('STRESS 3.5: Rapid continuous counter-clockwise rotation through 360 degrees', () {
      // Rotate CCW: 360 -> 330 -> 300 -> 270 -> 240 -> ... -> 30 -> 0 -> 330
      double current = 360.0;
      for (int i = 0; i < 24; i++) {
        current = (current - 30.0 + 360.0) % 360.0;
        final res = circular.filter(current);
        expect(res.isFinite, isTrue);
        expect(res >= 0.0 && res < 360.0, isTrue);
      }
    });
  });

  group('CRITERION 4: Concurrency & Stream Performance', () {
    late GpsPipelineService pipeline;

    setUp(() {
      pipeline = GpsPipelineService();
    });

    test('STRESS 4.1: Synchronous throughput exceeds 1,000 packets/sec with zero corruption', () {
      const int packetCount = 2000;
      final stopwatch = Stopwatch()..start();

      const origin = LatLng(12.9716, 77.5946);
      for (int i = 0; i < packetCount; i++) {
        final telemetry = GpsTelemetry(
          position: LatLng(origin.latitude + i * 0.00001, origin.longitude + i * 0.00001),
          accuracyMeters: 5.0,
          altitudeMeters: 900.0,
          speedKmh: 40.0,
          heading: (i * 5.0) % 360.0,
          compassHeading: (i * 5.0) % 360.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000000 + i * 100),
          isMocked: false,
          sourceDescription: 'STRESS TEST BENCHMARK',
        );

        final processed = pipeline.processTelemetry(telemetry);

        expect(processed.position.latitude.isFinite, isTrue);
        expect(processed.position.longitude.isFinite, isTrue);
        expect(processed.heading.isFinite, isTrue);
        expect(processed.heading >= 0.0 && processed.heading < 360.0, isTrue);
        expect(processed.speedKmh, equals(40.0));
      }

      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final double throughput = (packetCount / (elapsedMs / 1000.0));

      expect(elapsedMs, lessThan(1000),
          reason: 'Processing $packetCount packets took ${elapsedMs}ms, must take < 1000ms');
      expect(throughput, greaterThan(1000.0),
          reason: 'Throughput was ${throughput.toStringAsFixed(0)} packets/s, must be > 1000');
    });

    test('STRESS 4.2: Asynchronous stream transformation preserves packet sequence and integrity', () async {
      const int streamPackets = 1500;
      final controller = StreamController<GpsTelemetry>();
      final transformedStream = pipeline.transformStream(controller.stream);

      final receivedPackets = <GpsTelemetry>[];
      final completer = Completer<void>();

      transformedStream.listen(
        (packet) {
          receivedPackets.add(packet);
          if (receivedPackets.length == streamPackets) {
            completer.complete();
          }
        },
        onError: (e) => completer.completeError(e),
      );

      const origin = LatLng(12.9716, 77.5946);
      for (int i = 0; i < streamPackets; i++) {
        controller.add(
          GpsTelemetry(
            position: LatLng(origin.latitude + (i * 0.00001), origin.longitude),
            accuracyMeters: 4.5,
            altitudeMeters: 920.0,
            speedKmh: 25.0,
            heading: (i * 2.0) % 360.0,
            compassHeading: (i * 2.0) % 360.0,
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000000 + i * 50),
            isMocked: false,
            sourceDescription: 'STRESS TEST STREAM',
          ),
        );
      }

      await completer.future.timeout(const Duration(seconds: 3));
      await controller.close();

      expect(receivedPackets.length, equals(streamPackets));
      for (int i = 0; i < streamPackets; i++) {
        expect(receivedPackets[i].position.latitude.isFinite, isTrue);
        expect(receivedPackets[i].position.longitude.isFinite, isTrue);
        expect(receivedPackets[i].heading.isFinite, isTrue);
      }
    });

    test('STRESS 4.3: Multi-subscriber broadcast stream concurrency stress', () async {
      const int packetCount = 500;
      const int subscriberCount = 5;

      final controller = StreamController<GpsTelemetry>.broadcast();
      final transformedBroadcast = pipeline
          .transformStream(controller.stream)
          .asBroadcastStream();

      final subscriberResults = List.generate(
        subscriberCount,
        (_) => <GpsTelemetry>[],
      );
      final completers = List.generate(
        subscriberCount,
        (_) => Completer<void>(),
      );

      final subscriptions = <StreamSubscription<GpsTelemetry>>[];
      for (int s = 0; s < subscriberCount; s++) {
        final subIndex = s;
        final sub = transformedBroadcast.listen((packet) {
          subscriberResults[subIndex].add(packet);
          if (subscriberResults[subIndex].length == packetCount &&
              !completers[subIndex].isCompleted) {
            completers[subIndex].complete();
          }
        });
        subscriptions.add(sub);
      }

      const origin = LatLng(12.9716, 77.5946);
      for (int i = 0; i < packetCount; i++) {
        controller.add(
          GpsTelemetry(
            position: LatLng(origin.latitude, origin.longitude + (i * 0.00001)),
            accuracyMeters: 6.0,
            altitudeMeters: 910.0,
            speedKmh: 12.0,
            heading: (i * 10.0) % 360.0,
            compassHeading: (i * 10.0) % 360.0,
            timestamp: DateTime.fromMillisecondsSinceEpoch(3000000 + i * 20),
            isMocked: false,
            sourceDescription: 'STRESS TEST BROADCAST',
          ),
        );
      }

      await Future.wait(completers.map((c) => c.future))
          .timeout(const Duration(seconds: 4));

      for (int s = 0; s < subscriberCount; s++) {
        expect(subscriberResults[s].length, equals(packetCount));
        // Verify all subscribers received identical output
        expect(
          subscriberResults[s].last.position.latitude,
          equals(subscriberResults[0].last.position.latitude),
        );
        expect(
          subscriberResults[s].last.heading,
          equals(subscriberResults[0].last.heading),
        );
      }

      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await controller.close();
    });
  });
}
