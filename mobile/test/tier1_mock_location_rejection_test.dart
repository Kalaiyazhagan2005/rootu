import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'helpers/test_anti_spoof.dart';

void main() {
  group('Tier 1: Mock Location Rejection & Anti-Spoofing Feature Coverage', () {
    late AntiSpoofValidator validator;

    setUp(() {
      validator = AntiSpoofValidator();
    });

    test('TC3.1: Parses isMocked true from Android API 31+ isMock dictionary flag', () {
      final mockMap = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': true,
      };

      final telemetry = GpsTelemetry.fromNativeMap(mockMap);
      expect(telemetry.isMocked, isTrue);
    });

    test('TC3.2: AntiSpoofValidator rejects mock packet and increments rejection counter', () {
      final mockMap = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': true,
      };
      final telemetry = GpsTelemetry.fromNativeMap(mockMap);

      final isValid = validator.validate(telemetry);

      expect(isValid, isFalse);
      expect(validator.rejectedCount, equals(1));
      expect(validator.acceptedCount, equals(0));
    });

    test('TC3.3: Strict validation mode throws AntiSpoofException upon mock injection', () {
      final mockMap = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 5.0,
        'isMock': true,
      };
      final telemetry = GpsTelemetry.fromNativeMap(mockMap);

      expect(
        () => validator.validate(telemetry, throwOnMock: true),
        throwsA(isA<AntiSpoofException>()),
      );
    });

    test('TC3.4: Genuine satellite fix with isMocked false passes validation cleanly', () {
      final genuineMap = {
        'latitude': 12.9716,
        'longitude': 77.5946,
        'accuracy': 3.5,
        'isMock': false,
      };
      final telemetry = GpsTelemetry.fromNativeMap(genuineMap);

      final isValid = validator.validate(telemetry);

      expect(isValid, isTrue);
      expect(validator.acceptedCount, equals(1));
      expect(validator.rejectedCount, equals(0));
    });

    test('TC3.5: Stream filter drops mocked packets while preserving genuine sequence', () async {
      final controller = StreamController<GpsTelemetry>();
      final filteredStream = validator.filterMockStream(controller.stream);

      final received = <GpsTelemetry>[];
      final subscription = filteredStream.listen((t) => received.add(t));

      final p1 = GpsTelemetry.fromNativeMap({'latitude': 12.0, 'longitude': 77.0, 'isMock': false});
      final p2Mock = GpsTelemetry.fromNativeMap({'latitude': 12.1, 'longitude': 77.1, 'isMock': true});
      final p3 = GpsTelemetry.fromNativeMap({'latitude': 12.2, 'longitude': 77.2, 'isMock': false});
      final p4Mock = GpsTelemetry.fromNativeMap({'latitude': 12.3, 'longitude': 77.3, 'isMock': true});

      controller.add(p1);
      controller.add(p2Mock);
      controller.add(p3);
      controller.add(p4Mock);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received.length, equals(2));
      expect(received[0].position.latitude, equals(12.0));
      expect(received[1].position.latitude, equals(12.2));
      expect(validator.rejectedCount, equals(2));
      expect(validator.acceptedCount, equals(2));

      await subscription.cancel();
      await controller.close();
    });

    test('TC3.6: Detects legacy and alternative mock flags in raw dictionary', () {
      expect(AntiSpoofValidator.isMockMap({'isMock': true}), isTrue);
      expect(AntiSpoofValidator.isMockMap({'isFromMockProvider': true}), isTrue);
      expect(AntiSpoofValidator.isMockMap({'mock': true}), isTrue);
      expect(AntiSpoofValidator.isMockMap({'isMock': false}), isFalse);
      expect(AntiSpoofValidator.isMockMap({}), isFalse);
    });
  });
}
