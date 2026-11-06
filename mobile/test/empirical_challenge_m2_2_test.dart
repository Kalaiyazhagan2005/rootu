import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'package:rootu_mobile/features/map/services/gps_pipeline_service.dart';
import 'package:rootu_mobile/features/map/services/native_gps_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hardwareMethodChannel =
      MethodChannel('com.example.rootu_mobile/gps_hardware');
  const gpsEventChannel =
      EventChannel('com.example.rootu_mobile/gps_stream');

  group('CHALLENGE 1: Stream Lifecycle & Memory Leak Prevention', () {
    setUp(() {
      NativeGpsService.resetForTesting();
    });

    tearDown(() {
      NativeGpsService.resetForTesting();
    });

    test('TC_CHALLENGE_1.1: 50 sequential subscribe/cancel cycles on smoothedTelemetryStream do not exhaust stream or throw StateError', () async {
      StreamController<Map<dynamic, dynamic>>? mockChannelController;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      for (int i = 0; i < 50; i++) {
        final stream = NativeGpsService.smoothedTelemetryStream;
        expect(stream.isBroadcast, isTrue);

        final received = Completer<GpsTelemetry>();
        final subscription = stream.listen((telemetry) {
          if (!received.isCompleted) {
            received.complete(telemetry);
          }
        });

        // Send a valid packet
        mockChannelController?.add({
          'latitude': 12.9716,
          'longitude': 77.5946,
          'accuracy': 4.0,
          'speed': 0.0,
          'bearing': 0.0,
          'compassHeading': 90.0,
          'time': 1000 + i * 100,
          'isMock': false,
        });

        final telemetry = await received.future;
        expect(telemetry.position.latitude, equals(12.9716));

        await subscription.cancel();
      }
    });

    test('TC_CHALLENGE_1.2: Multiple concurrent subscribers receive synchronized telemetry with clean partial cancellation', () async {
      StreamController<Map<dynamic, dynamic>>? mockChannelController;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      final stream = NativeGpsService.smoothedTelemetryStream;
      final results1 = <GpsTelemetry>[];
      final results2 = <GpsTelemetry>[];
      final results3 = <GpsTelemetry>[];
      final results4 = <GpsTelemetry>[];
      final results5 = <GpsTelemetry>[];

      final sub1 = stream.listen(results1.add);
      final sub2 = stream.listen(results2.add);
      final sub3 = stream.listen(results3.add);
      final sub4 = stream.listen(results4.add);
      final sub5 = stream.listen(results5.add);

      // Emit first packet
      mockChannelController?.add({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 3.0,
        'speed': 0.0,
        'bearing': 0.0,
        'compassHeading': 45.0,
        'time': 1000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(results1.length, equals(1));
      expect(results2.length, equals(1));
      expect(results3.length, equals(1));
      expect(results4.length, equals(1));
      expect(results5.length, equals(1));

      // Cancel 3 subscribers
      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();

      // Emit second packet
      mockChannelController?.add({
        'latitude': 12.9718,
        'longitude': 77.5948,
        'accuracy': 3.0,
        'speed': 5.0,
        'bearing': 90.0,
        'compassHeading': 50.0,
        'time': 2000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Cancelled subscribers received no further events
      expect(results1.length, equals(1));
      expect(results2.length, equals(1));
      expect(results3.length, equals(1));

      // Remaining active subscribers received the second event
      expect(results4.length, equals(2));
      expect(results5.length, equals(2));

      await sub4.cancel();
      await sub5.cancel();
    });

    test('TC_CHALLENGE_1.3: resetForTesting clears stream caches and resets internal pipeline state', () async {
      StreamController<Map<dynamic, dynamic>>? mockChannelController;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      final stream1 = NativeGpsService.smoothedTelemetryStream;
      final results1 = <GpsTelemetry>[];
      final sub1 = stream1.listen(results1.add);

      mockChannelController?.add({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 4.0,
        'speed': 10.0,
        'bearing': 90.0,
        'compassHeading': 90.0,
        'time': 1000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results1.length, equals(1));
      await sub1.cancel();

      // Call resetForTesting
      NativeGpsService.resetForTesting();

      // After reset, accessing smoothedTelemetryStream yields fresh stream
      final stream2 = NativeGpsService.smoothedTelemetryStream;
      expect(identical(stream1, stream2), isFalse);

      final results2 = <GpsTelemetry>[];
      final sub2 = stream2.listen(results2.add);

      mockChannelController?.add({
        'latitude': 13.0827,
        'longitude': 80.2707,
        'accuracy': 3.0,
        'speed': 0.0,
        'bearing': 0.0,
        'compassHeading': 180.0,
        'time': 2000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results2.length, equals(1));
      // First fix after reset anchors exactly to new coordinates (Chennai)
      expect(results2.first.position.latitude, equals(13.0827));
      expect(results2.first.position.longitude, equals(80.2707));

      await sub2.cancel();
    });

    test('TC_CHALLENGE_1.4: GpsPipelineService.transformer cleanly resets pipeline on stream done', () async {
      final controller = StreamController<GpsTelemetry>();
      final pipeline = GpsPipelineService();
      final transformed = controller.stream.transform(
        GpsPipelineService.transformer(
          kalmanFilter: pipeline.kalmanFilter,
          headingFusion: pipeline.headingFusion,
        ),
      );

      final results = <GpsTelemetry>[];
      final sub = transformed.listen(results.add);

      controller.add(GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        compassHeading: 85.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(results.length, equals(1));
      expect(pipeline.kalmanFilter.isInitialized, isTrue);

      await controller.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // After stream done, transformer's handleDone resets internal filter
      expect(pipeline.kalmanFilter.isInitialized, isFalse);
      await sub.cancel();
    });
  });

  group('CHALLENGE 2: Cold-Start Immediate Fix & Coordinate Continuity', () {
    setUp(() {
      NativeGpsService.resetForTesting();
    });

    tearDown(() {
      NativeGpsService.resetForTesting();
    });

    test('TC_CHALLENGE_2.1: getImmediateSmoothedFix followed by smoothedTelemetryStream provides continuous coordinates without origin glitch', () async {
      // Mock hardware method channel for immediate fix
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hardwareMethodChannel, (call) async {
        if (call.method == 'getRawGpsLocation') {
          return {
            'latitude': 12.9716,
            'longitude': 77.5946,
            'accuracy': 4.0,
            'speed': 0.0,
            'bearing': 0.0,
            'compassHeading': 45.0,
            'time': 1000,
            'isMock': false,
          };
        }
        return null;
      });

      // 1. Fetch immediate fix (cold start)
      final immediateFix = await NativeGpsService.getImmediateSmoothedFix();
      expect(immediateFix, isNotNull);
      expect(immediateFix!.position.latitude, equals(12.9716));
      expect(immediateFix.position.longitude, equals(77.5946));
      expect(immediateFix.heading, closeTo(45.0, 1e-4));

      // Mock EventChannel for streaming updates
      StreamController<Map<dynamic, dynamic>>? mockChannelController;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      // 2. Subscribe to smoothed stream
      final streamedFixes = <GpsTelemetry>[];
      final sub = NativeGpsService.smoothedTelemetryStream.listen(streamedFixes.add);

      // Emit second fix 500ms later with a tiny 2-meter physical movement
      // 0.00002 deg lat ~ 2.22 meters
      mockChannelController?.add({
        'latitude': 12.97162,
        'longitude': 77.59462,
        'accuracy': 4.0,
        'speed': 1.0,
        'bearing': 45.0,
        'compassHeading': 46.0,
        'time': 1500,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(streamedFixes.length, equals(1));

      final firstStreamFix = streamedFixes.first;

      // Coordinate continuity check:
      // The smoothed stream position must NOT glitch to (0, 0) or teleport away.
      // It must be smoothly between initial fix (12.9716) and new raw fix (12.97162).
      expect(firstStreamFix.position.latitude, greaterThanOrEqualTo(12.97160));
      expect(firstStreamFix.position.latitude, lessThanOrEqualTo(12.971625));
      expect(firstStreamFix.position.longitude, greaterThanOrEqualTo(77.59460));
      expect(firstStreamFix.position.longitude, lessThanOrEqualTo(77.594625));

      // Heading continuity: compass smoothly moves from 45.0 towards 46.0
      expect(firstStreamFix.heading, closeTo(45.2, 0.5));

      await sub.cancel();
    });

    test('TC_CHALLENGE_2.2: Interrupted stream blackout gap (>5s) safely re-anchors without runaway oscillation', () async {
      StreamController<Map<dynamic, dynamic>>? mockChannelController;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      final streamedFixes = <GpsTelemetry>[];
      final sub = NativeGpsService.smoothedTelemetryStream.listen(streamedFixes.add);

      // Emit fix 1
      mockChannelController?.add({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 4.0,
        'speed': 5.0,
        'bearing': 90.0,
        'compassHeading': 90.0,
        'time': 1000,
        'isMock': false,
      });

      // Emit fix 2 after 8 seconds (blackout gap > 5s threshold)
      mockChannelController?.add({
        'latitude': 12.9800,
        'longitude': 77.6000,
        'accuracy': 4.0,
        'speed': 5.0,
        'bearing': 90.0,
        'compassHeading': 90.0,
        'time': 9000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(streamedFixes.length, equals(2));

      // After blackout gap, filter re-anchors cleanly to incoming fix
      expect(streamedFixes[1].position.latitude, equals(12.9800));
      expect(streamedFixes[1].position.longitude, equals(77.6000));

      await sub.cancel();
    });
  });

  group('CHALLENGE 3: Anti-Spoof Leak Prevention & Isolation', () {
    setUp(() {
      NativeGpsService.resetForTesting();
    });

    tearDown(() {
      NativeGpsService.resetForTesting();
    });

    test('TC_CHALLENGE_3.1: getImmediateSmoothedFix returns null on all mock flag variations and does not initialize pipeline', () async {
      final mockPayloads = [
        {'latitude': 12.9716, 'longitude': 77.5946, 'isMock': true},
        {'latitude': 12.9716, 'longitude': 77.5946, 'isFromMockProvider': true},
        {'latitude': 12.9716, 'longitude': 77.5946, 'mock': true},
        {'latitude': 12.9716, 'longitude': 77.5946, 'is_mock': 1},
        {'latitude': 12.9716, 'longitude': 77.5946, 'is_from_mock_provider': 'true'},
      ];

      for (final payload in mockPayloads) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(hardwareMethodChannel, (call) async => payload);

        final fix = await NativeGpsService.getImmediateSmoothedFix();
        expect(fix, isNull, reason: 'Mock payload $payload must be rejected immediately');
      }
    });

    test('TC_CHALLENGE_3.2: Stream mock packets are 100% blocked from smoothedTelemetryStream and never contaminate state', () async {
      StreamController<Map<dynamic, dynamic>>? mockChannelController;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        gpsEventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            mockChannelController = StreamController<Map<dynamic, dynamic>>();
            mockChannelController!.stream.listen(
              (event) => sink.success(event),
              onError: (err) => sink.error(code: 'ERR', message: err.toString()),
              onDone: () => sink.endOfStream(),
            );
          },
          onCancel: (args) {
            mockChannelController?.close();
            mockChannelController = null;
          },
        ),
      );

      final smoothedFixes = <GpsTelemetry>[];
      final rejectedFixes = <GpsTelemetry>[];

      final sub1 = NativeGpsService.smoothedTelemetryStream.listen(smoothedFixes.add);
      final sub2 = NativeGpsService.mockDetectionStream.listen(rejectedFixes.add);

      // Packet 1: Genuine fix (Bangalore)
      mockChannelController?.add({
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 4.0,
        'speed': 0.0,
        'bearing': 0.0,
        'compassHeading': 90.0,
        'time': 1000,
        'isMock': false,
      });

      // Packet 2: Mock packet (Spoofed Delhi coordinate)
      mockChannelController?.add({
        'latitude': 28.6139,
        'longitude': 77.2090,
        'accuracy': 5.0,
        'speed': 100.0,
        'bearing': 0.0,
        'compassHeading': 0.0,
        'time': 2000,
        'isMock': true,
      });

      // Packet 3: Mock packet with legacy Android flag
      mockChannelController?.add({
        'latitude': 28.6140,
        'longitude': 77.2091,
        'accuracy': 5.0,
        'speed': 100.0,
        'bearing': 0.0,
        'compassHeading': 0.0,
        'time': 3000,
        'isFromMockProvider': true,
      });

      // Packet 4: Genuine fix (Bangalore + 2m)
      mockChannelController?.add({
        'latitude': 12.97162,
        'longitude': 77.59462,
        'accuracy': 4.0,
        'speed': 0.0,
        'bearing': 0.0,
        'compassHeading': 92.0,
        'time': 4000,
        'isMock': false,
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert smoothed stream received ONLY the 2 genuine packets
      expect(smoothedFixes.length, equals(2));
      expect(smoothedFixes.every((t) => !t.isMocked), isTrue);
      expect(smoothedFixes[0].position.latitude, equals(12.9716));
      expect(smoothedFixes[1].position.latitude, closeTo(12.97161, 0.00002));

      // Assert audit stream caught both mock packets
      expect(rejectedFixes.length, equals(2));
      expect(rejectedFixes.every((t) => t.isMocked), isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });
  });

  group('CHALLENGE 4: Non-Finite Values Propagation Defense', () {
    late GpsPipelineService pipeline;

    setUp(() {
      pipeline = GpsPipelineService();
    });

    test('TC_CHALLENGE_4.1: Latitude and longitude with NaN and Infinity are sanitized to finite coordinates', () {
      final rawNan = GpsTelemetry(
        position: const LatLng(double.nan, double.nan),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processedNan = pipeline.processTelemetry(rawNan);
      expect(processedNan.position.latitude.isFinite, isTrue);
      expect(processedNan.position.longitude.isFinite, isTrue);

      final rawInf = GpsTelemetry(
        position: const LatLng(double.infinity, -double.infinity),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final processedInf = pipeline.processTelemetry(rawInf);
      expect(processedInf.position.latitude.isFinite, isTrue);
      expect(processedInf.position.longitude.isFinite, isTrue);
    });

    test('TC_CHALLENGE_4.2: Heading with NaN and Infinity produces finite normalized heading [0, 360)', () {
      final rawNan = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: double.nan,
        compassHeading: double.nan,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processedNan = pipeline.processTelemetry(rawNan);
      expect(processedNan.heading.isFinite, isTrue);
      expect(processedNan.heading, greaterThanOrEqualTo(0.0));
      expect(processedNan.heading, lessThan(360.0));

      final rawInf = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: double.infinity,
        compassHeading: double.infinity,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final processedInf = pipeline.processTelemetry(rawInf);
      expect(processedInf.heading.isFinite, isTrue);
      expect(processedInf.heading, greaterThanOrEqualTo(0.0));
      expect(processedInf.heading, lessThan(360.0));
    });

    test('TC_CHALLENGE_4.3: Accuracy with NaN or Infinity NEVER escapes GpsPipelineService as non-finite', () {
      final rawNanAcc = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: double.nan,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processedNanAcc = pipeline.processTelemetry(rawNanAcc);
      expect(
        processedNanAcc.accuracyMeters.isFinite,
        isTrue,
        reason: 'accuracyMeters must be finite and sanitized against NaN by GpsPipelineService',
      );
      expect(
        processedNanAcc.accuracyMeters,
        greaterThan(0.0),
        reason: 'accuracyMeters must be positive',
      );

      final rawInfAcc = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: double.infinity,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final processedInfAcc = pipeline.processTelemetry(rawInfAcc);
      expect(
        processedInfAcc.accuracyMeters.isFinite,
        isTrue,
        reason: 'accuracyMeters must be finite and sanitized against Infinity by GpsPipelineService',
      );
    });

    test('TC_CHALLENGE_4.4: Speed with NaN or Infinity NEVER escapes GpsPipelineService as non-finite', () {
      final rawNanSpeed = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: double.nan,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processedNanSpeed = pipeline.processTelemetry(rawNanSpeed);
      expect(
        processedNanSpeed.speedKmh.isFinite,
        isTrue,
        reason: 'speedKmh must be finite and sanitized against NaN by GpsPipelineService',
      );
      expect(
        processedNanSpeed.speedKmh,
        greaterThanOrEqualTo(0.0),
        reason: 'speedKmh must be non-negative',
      );

      final rawInfSpeed = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: double.infinity,
        heading: 90.0,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final processedInfSpeed = pipeline.processTelemetry(rawInfSpeed);
      expect(
        processedInfSpeed.speedKmh.isFinite,
        isTrue,
        reason: 'speedKmh must be finite and sanitized against Infinity by GpsPipelineService',
      );
    });

    test('TC_CHALLENGE_4.5: Compass heading with NaN or Infinity NEVER escapes GpsPipelineService as non-finite', () {
      final rawNanCompass = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        compassHeading: double.nan,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      );

      final processedNanCompass = pipeline.processTelemetry(rawNanCompass);
      expect(
        processedNanCompass.compassHeading == null ||
            processedNanCompass.compassHeading!.isFinite,
        isTrue,
        reason: 'compassHeading must be finite or null when input is NaN',
      );

      final rawInfCompass = GpsTelemetry(
        position: const LatLng(12.9716, 77.5946),
        accuracyMeters: 4.0,
        altitudeMeters: 900.0,
        speedKmh: 10.0,
        heading: 90.0,
        compassHeading: double.infinity,
        isMocked: false,
        sourceDescription: 'TEST',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );

      final processedInfCompass = pipeline.processTelemetry(rawInfCompass);
      expect(
        processedInfCompass.compassHeading == null ||
            processedInfCompass.compassHeading!.isFinite,
        isTrue,
        reason: 'compassHeading must be finite or null when input is Infinity',
      );
    });

    test('TC_CHALLENGE_4.6: Corrupted telemetry stream with all non-finite fields sanitized throughout stream', () async {
      final controller = StreamController<GpsTelemetry>();
      final transformed = pipeline.transformStream(controller.stream);

      final results = <GpsTelemetry>[];
      final sub = transformed.listen(results.add);

      controller.add(GpsTelemetry(
        position: const LatLng(double.nan, double.infinity),
        accuracyMeters: double.nan,
        altitudeMeters: double.infinity,
        speedKmh: double.nan,
        heading: double.nan,
        compassHeading: double.infinity,
        isMocked: false,
        sourceDescription: 'CORRUPTED',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.close();

      expect(results.length, equals(1));
      final item = results.first;

      expect(item.position.latitude.isFinite, isTrue);
      expect(item.position.longitude.isFinite, isTrue);
      expect(item.accuracyMeters.isFinite, isTrue);
      expect(item.speedKmh.isFinite, isTrue);
      expect(item.heading.isFinite, isTrue);
      expect(item.compassHeading == null || item.compassHeading!.isFinite, isTrue);

      await sub.cancel();
    });
  });
}
