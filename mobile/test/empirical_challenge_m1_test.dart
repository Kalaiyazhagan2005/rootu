import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'package:rootu_mobile/features/map/services/native_gps_service.dart';
import 'helpers/test_heading_fusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EMPIRICAL CHALLENGE 1: Anti-Spoofing Stress Testing', () {
    setUp(() {
      NativeGpsService.resetForTesting();
    });

    test('CHALLENGE 1.1: GpsTelemetry parses isMock == true', () {
      final map = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': true,
      };
      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(telemetry.isMocked, isTrue);
    });

    test('CHALLENGE 1.2: GpsTelemetry parses isFromMockProvider == true (Legacy Android)', () {
      final map = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isFromMockProvider': true,
      };
      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(
        telemetry.isMocked,
        isTrue,
        reason: 'isFromMockProvider == true MUST be parsed as isMocked == true by GpsTelemetry',
      );
    });

    test('CHALLENGE 1.3: GpsTelemetry parses mock == true (Alternative mock flag)', () {
      final map = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'mock': true,
      };
      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(
        telemetry.isMocked,
        isTrue,
        reason: 'mock == true flag MUST be parsed as isMocked == true by GpsTelemetry',
      );
    });

    test('CHALLENGE 1.3a: GpsTelemetry handles integer mock flag (isMock: 1)', () {
      final map = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': 1,
      };
      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(telemetry.isMocked, isTrue);
    });

    test('CHALLENGE 1.3b: GpsTelemetry handles string mock flag (isMock: "true")', () {
      final map = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': 'true',
      };
      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(telemetry.isMocked, isTrue);
    });

    test('CHALLENGE 1.4: NativeGpsService.getImmediateHardwareFix() rejects mock fix (isMock: true)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.rootu_mobile/gps_hardware'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getRawGpsLocation') {
            return {
              'latitude': 12.9716,
              'longitude': 77.5946,
              'accuracy': 5.0,
              'isMock': true,
            };
          }
          return null;
        },
      );

      final fix = await NativeGpsService.getImmediateHardwareFix();
      expect(fix, isNull, reason: 'Mock fix must return null and be 100% rejected');
    });

    test('CHALLENGE 1.5: NativeGpsService.getImmediateHardwareFix() rejects isFromMockProvider: true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.example.rootu_mobile/gps_hardware'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'getRawGpsLocation') {
            return {
              'latitude': 12.9716,
              'longitude': 77.5946,
              'accuracy': 5.0,
              'isFromMockProvider': true,
            };
          }
          return null;
        },
      );

      final fix = await NativeGpsService.getImmediateHardwareFix();
      expect(
        fix,
        isNull,
        reason: 'Fix with isFromMockProvider == true MUST return null and be 100% rejected',
      );
    });

    test('CHALLENGE 1.6: NativeGpsService.telemetryStream rejects mock packets (isMock: true)', () async {
      // Setup mock EventChannel
      const eventChannel = EventChannel('com.example.rootu_mobile/gps_stream');
      final emittedEvents = <GpsTelemetry>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            // Send genuine packet
            sink.success({
              'latitude': 12.9716,
              'longitude': 77.5946,
              'accuracy': 5.0,
              'isMock': false,
            });
            // Send mock packet with isMock == true
            sink.success({
              'latitude': 13.0000,
              'longitude': 77.6000,
              'accuracy': 5.0,
              'isMock': true,
            });
            // Send genuine packet
            sink.success({
              'latitude': 12.9720,
              'longitude': 77.5950,
              'accuracy': 4.0,
              'isMock': false,
            });
          },
        ),
      );

      final sub = NativeGpsService.telemetryStream.listen(emittedEvents.add);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(emittedEvents.length, equals(2));
      expect(emittedEvents.any((t) => t.isMocked), isFalse);
      expect(emittedEvents[0].position.latitude, equals(12.9716));
      expect(emittedEvents[1].position.latitude, equals(12.9720));

      await sub.cancel();
    });

    test('CHALLENGE 1.7: NativeGpsService.telemetryStream rejects isFromMockProvider: true', () async {
      const eventChannel = EventChannel('com.example.rootu_mobile/gps_stream');
      final emittedEvents = <GpsTelemetry>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (args, sink) {
            sink.success({
              'latitude': 12.9716,
              'longitude': 77.5946,
              'accuracy': 5.0,
              'isMock': false,
            });
            // Mock packet sent with legacy flag isFromMockProvider
            sink.success({
              'latitude': 13.0000,
              'longitude': 77.6000,
              'accuracy': 5.0,
              'isFromMockProvider': true,
            });
          },
        ),
      );

      final sub = NativeGpsService.telemetryStream.listen(emittedEvents.add);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        emittedEvents.length,
        equals(1),
        reason: 'Packet with isFromMockProvider: true MUST be rejected and not emitted on telemetryStream',
      );
      expect(emittedEvents[0].position.latitude, equals(12.9716));

      await sub.cancel();
    });
  });

  group('EMPIRICAL CHALLENGE 2: Heading & Orientation Edge Cases', () {
    test('CHALLENGE 2.1: Negative compass azimuths (-1.0, -90.0) parse to null', () {
      final mapNegative1 = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': -1.0,
      };
      final t1 = GpsTelemetry.fromNativeMap(mapNegative1);
      expect(t1.compassHeading, isNull);

      final mapNegative90 = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': -90.0,
      };
      final t2 = GpsTelemetry.fromNativeMap(mapNegative90);
      expect(t2.compassHeading, isNull);
    });

    test('CHALLENGE 2.2: Missing compass values parse to null', () {
      final mapMissing = {
        'latitude': 12.0,
        'longitude': 77.0,
      };
      final t = GpsTelemetry.fromNativeMap(mapMissing);
      expect(t.compassHeading, isNull);
    });

    test('CHALLENGE 2.3: NaN compass azimuth parses safely without crash', () {
      final mapNan = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': double.nan,
      };
      final t = GpsTelemetry.fromNativeMap(mapNan);
      expect(t.compassHeading, isNull);
      expect(t.toString(), isNotEmpty);
    });

    test('CHALLENGE 2.4: Infinity compass azimuth does not cause crash or invalid heading state', () {
      final mapInf = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': double.infinity,
      };
      final t = GpsTelemetry.fromNativeMap(mapInf);

      // compassHeading should be null when azimuth is infinite or non-finite
      expect(
        t.compassHeading == null || (t.compassHeading!.isFinite && t.compassHeading! >= 0 && t.compassHeading! <= 360),
        isTrue,
        reason: 'Compass heading must be finite within [0, 360] degrees or null',
      );

      // Verify compass heading is not treated as a valid finite heading in fusion
      final fusion = DynamicHeadingFusion();
      final fused = fusion.update(t.compassHeading ?? -1.0, 90.0, 0.0);
      expect(fused.isFinite, isTrue);
    });

    test('CHALLENGE 2.4b: Infinite bearing and speed are handled cleanly', () {
      final mapInf = {
        'latitude': 12.0,
        'longitude': 77.0,
        'bearing': double.infinity,
        'speed': double.infinity,
      };
      final t = GpsTelemetry.fromNativeMap(mapInf);

      expect(t.heading.isFinite, isTrue, reason: 'heading must be finite');
      expect(t.speedKmh.isFinite, isTrue, reason: 'speedKmh must be finite');
    });

    test('CHALLENGE 2.5: Edge angles (0 deg, 360 deg, 359 -> 1 deg)', () {
      final map0 = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': 0.0,
      };
      final t0 = GpsTelemetry.fromNativeMap(map0);
      expect(t0.compassHeading, equals(0.0));

      final map360 = {
        'latitude': 12.0,
        'longitude': 77.0,
        'compassHeading': 360.0,
      };
      final t360 = GpsTelemetry.fromNativeMap(map360);
      expect(t360.compassHeading, equals(360.0));

      // Circular wrap test with DynamicHeadingFusion
      final fusion = DynamicHeadingFusion();
      // Start pointing at 359 deg
      final h1 = fusion.update(359.0, -1.0, 0.0);
      expect(h1, closeTo(359.0, 1e-3));

      // Update pointing at 1.0 deg (wrap across 0/360)
      final h2 = fusion.update(1.0, -1.0, 0.0);
      // Smoothed filter beta=0.20 from 359 to 1 should rotate forward across 0, not backwards 358 degrees
      expect(h2.isFinite, isTrue);
      expect(h2 >= 359.0 || h2 <= 2.0, isTrue,
          reason: 'Transition across North boundary (359 -> 1) must take shortest arc');
    });

    test('CHALLENGE 2.6: NaN or Infinity in other fields during toString()', () {
      final mapInfAcc = {
        'latitude': 12.0,
        'longitude': 77.0,
        'accuracy': double.infinity,
        'speed': double.infinity,
        'bearing': double.infinity,
      };
      final t = GpsTelemetry.fromNativeMap(mapInfAcc);
      // Test if toString throws UnsupportedError
      expect(() => t.toString(), returnsNormally,
          reason: 'toString() must handle infinite/NaN values gracefully');
    });
  });
}
