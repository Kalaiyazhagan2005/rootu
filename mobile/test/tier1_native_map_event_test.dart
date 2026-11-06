import 'package:flutter_test/flutter_test.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';
import 'helpers/test_anti_spoof.dart';

void main() {
  group('Tier 1: Native Map Event Mapping Feature Coverage', () {
    test('TC2.1: Maps Android native LocationManager dictionary with all primitives', () {
      final androidMap = <dynamic, dynamic>{
        'latitude': 13.082680,
        'longitude': 80.270718,
        'accuracy': 3.2,
        'altitude': 14.5,
        'speed': 15.5, // 15.5 m/s = 55.8 km/h
        'bearing': 240.0,
        'time': 1700000100000,
        'isMock': false,
      };

      final telemetry = GpsTelemetry.fromNativeMap(
        androidMap,
        source: 'ANDROID FLP SATELLITE',
      );

      expect(telemetry.position.latitude, equals(13.082680));
      expect(telemetry.position.longitude, equals(80.270718));
      expect(telemetry.accuracyMeters, equals(3.2));
      expect(telemetry.altitudeMeters, equals(14.5));
      expect(telemetry.speedKmh, closeTo(55.8, 1e-4));
      expect(telemetry.heading, equals(240.0));
      expect(telemetry.isMocked, isFalse);
      expect(telemetry.sourceDescription, equals('ANDROID FLP SATELLITE'));
    });

    test('TC2.2: Maps iOS CoreLocation payload dictionary structure', () {
      final iosMap = <dynamic, dynamic>{
        'latitude': 37.774929,
        'longitude': -122.419416,
        'accuracy': 5.0,
        'altitude': 30.2,
        'speed': 8.33333, // 30.0 km/h
        'bearing': 90.0,
        'time': 1700000200000,
        'isMock': false,
      };

      final telemetry = GpsTelemetry.fromNativeMap(
        iosMap,
        source: 'IOS CORELOCATION',
      );

      expect(telemetry.position.latitude, equals(37.774929));
      expect(telemetry.position.longitude, equals(-122.419416));
      expect(telemetry.speedKmh, closeTo(30.0, 1e-1));
      expect(telemetry.heading, equals(90.0));
      expect(telemetry.sourceDescription, equals('IOS CORELOCATION'));
    });

    test('TC2.3: Validates coordinate ranges within global WGS84 bounds', () {
      expect(AntiSpoofValidator.isSanitaryCoordinates(12.97, 77.59), isTrue);
      expect(AntiSpoofValidator.isSanitaryCoordinates(-89.9, -179.9), isTrue);
      expect(AntiSpoofValidator.isSanitaryCoordinates(90.0, 180.0), isTrue);

      // Out of bounds checks
      expect(AntiSpoofValidator.isSanitaryCoordinates(90.01, 77.0), isFalse);
      expect(AntiSpoofValidator.isSanitaryCoordinates(-90.1, 77.0), isFalse);
      expect(AntiSpoofValidator.isSanitaryCoordinates(12.0, 180.01), isFalse);
      expect(AntiSpoofValidator.isSanitaryCoordinates(12.0, -180.01), isFalse);
    });

    test('TC2.4: Validates speed conversion from meters per second to km/h', () {
      final testCases = [
        {'mps': 0.0, 'expectedKmh': 0.0},
        {'mps': 1.0, 'expectedKmh': 3.6},
        {'mps': 5.0, 'expectedKmh': 18.0},
        {'mps': 10.0, 'expectedKmh': 36.0},
        {'mps': 25.0, 'expectedKmh': 90.0},
        {'mps': 33.3333, 'expectedKmh': 120.0},
      ];

      for (final tc in testCases) {
        final map = {
          'latitude': 12.0,
          'longitude': 77.0,
          'speed': tc['mps'],
        };
        final telemetry = GpsTelemetry.fromNativeMap(map);
        expect(telemetry.speedKmh, closeTo(tc['expectedKmh']!, 1e-2));
      }
    });

    test('TC2.5: Verifies non-negative speed clamping for negative sensor errors', () {
      final map = {
        'latitude': 12.0,
        'longitude': 77.0,
        'speed': -5.0, // Invalid speed output from glitching hardware
      };

      final telemetry = GpsTelemetry.fromNativeMap(map);
      expect(telemetry.speedKmh, equals(0.0));
    });
  });
}
