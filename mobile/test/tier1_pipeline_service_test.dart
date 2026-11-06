import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'package:rootu_mobile/features/map/services/gps_pipeline_service.dart';
import 'package:rootu_mobile/features/map/services/native_gps_service.dart';

void main() {
  group('Tier 1: GpsPipelineService & NativeGpsService Wiring', () {
    late GpsPipelineService pipeline;

    setUp(() {
      pipeline = GpsPipelineService();
      NativeGpsService.resetForTesting();
    });

    test('TC_PIPE.1: Processes single telemetry fix with spatial smoothing and heading fusion', () {
      final rawFix = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 920.0,
        speedKmh: 0.0,
        heading: 180.0,
        compassHeading: 45.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processed = pipeline.processTelemetry(rawFix);

      // On first fix, position matches reference origin
      expect(processed.position.latitude, equals(rawFix.position.latitude));
      expect(processed.position.longitude, equals(rawFix.position.longitude));
      // At stationary speed (0 km/h), heading locks to compass (45 deg)
      expect(processed.heading, closeTo(45.0, 1e-4));
      // Auxiliary fields preserved
      expect(processed.accuracyMeters, equals(4.0));
      expect(processed.altitudeMeters, equals(920.0));
      expect(processed.speedKmh, equals(0.0));
      expect(processed.isMocked, isFalse);
    });

    test('TC_PIPE.2: Transforms a Stream of telemetry fixes continuously', () async {
      final streamController = StreamController<GpsTelemetry>();
      final smoothedStream = pipeline.transformStream(streamController.stream);

      final results = <GpsTelemetry>[];
      final subscription = smoothedStream.listen(results.add);

      final t1 = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 3.0,
        altitudeMeters: 900.0,
        speedKmh: 20.0,
        heading: 90.0,
        compassHeading: 85.0,
        isMocked: false,
        sourceDescription: 'STREAM_1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final t2 = GpsTelemetry(
        position: const LatLng(12.9718, 77.5946),
        accuracyMeters: 3.0,
        altitudeMeters: 900.0,
        speedKmh: 20.0,
        heading: 90.0,
        compassHeading: 85.0,
        isMocked: false,
        sourceDescription: 'STREAM_2',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      streamController.add(t1);
      streamController.add(t2);
      await streamController.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(results.length, equals(2));
      // Cruising speed (20 km/h >= 10.8 km/h) locks to GPS bearing (90.0)
      expect(results[1].heading, closeTo(90.0, 1e-4));
      await subscription.cancel();
    });

    test('TC_PIPE.3: StreamTransformer transforms telemetry stream via transform()', () async {
      final streamController = StreamController<GpsTelemetry>();
      final transformedStream = streamController.stream.transform(
        GpsPipelineService.transformer(),
      );

      final results = <GpsTelemetry>[];
      final subscription = transformedStream.listen(results.add);

      final fix = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 5.0,
        altitudeMeters: 910.0,
        speedKmh: 5.4,
        heading: 120.0,
        compassHeading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      streamController.add(fix);
      await streamController.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(results.length, equals(1));
      expect(results.first.position.latitude, equals(12.9716));
      await subscription.cancel();
    });

    test('TC_PIPE.4: reset() re-initializes Kalman filter and heading fusion state', () {
      final fix = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 920.0,
        speedKmh: 10.0,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      pipeline.processTelemetry(fix);
      expect(pipeline.kalmanFilter.isInitialized, isTrue);
      expect(pipeline.headingFusion.hasInitialHeading, isTrue);

      pipeline.reset();
      expect(pipeline.kalmanFilter.isInitialized, isFalse);
      expect(pipeline.headingFusion.hasInitialHeading, isFalse);
    });

    test('TC_PIPE.5: NativeGpsService exposes smoothedTelemetryStream and resetForTesting', () {
      final smoothedStream = NativeGpsService.smoothedTelemetryStream;
      expect(smoothedStream.isBroadcast, isTrue);

      NativeGpsService.resetForTesting();
      final freshStream = NativeGpsService.smoothedTelemetryStream;
      expect(freshStream, isNotNull);
    });
  });
}

