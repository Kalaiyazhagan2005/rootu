import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';

void main() {
  group('Tier 1: Telemetry Parsing Feature Coverage', () {
    test('TC1.1: Parses standard full telemetry dictionary correctly', () {
      final map = {
        'latitude': 12.971598,
        'longitude': 77.594562,
        'accuracy': 4.5,
        'altitude': 920.8,
        'speed': 10.0, // 10 m/s = 36 km/h
        'bearing': 180.5,
        'time': 1700000000000,
        'isMock': false,
      };

      final telemetry = GpsTelemetry.fromNativeMap(
        map,
        source: 'LIVE GPS SATELLITE',
      );

      expect(telemetry.position.latitude, closeTo(12.971598, 1e-6));
      expect(telemetry.position.longitude, closeTo(77.594562, 1e-6));
      expect(telemetry.accuracyMeters, equals(4.5));
      expect(telemetry.altitudeMeters, equals(920.8));
      expect(telemetry.speedKmh, closeTo(36.0, 1e-4));
      expect(telemetry.heading, equals(180.5));
      expect(telemetry.isMocked, isFalse);
      expect(telemetry.sourceDescription, equals('LIVE GPS SATELLITE'));
      expect(telemetry.timestamp.millisecondsSinceEpoch, equals(1700000000000));
    });

    test('TC1.2: Handles missing and null fields with safe defaults', () {
      final map = <String, dynamic>{};

      final telemetry = GpsTelemetry.fromNativeMap(map);

      expect(telemetry.position.latitude, equals(0.0));
      expect(telemetry.position.longitude, equals(0.0));
      expect(telemetry.accuracyMeters, equals(25.0));
      expect(telemetry.altitudeMeters, equals(0.0));
      expect(telemetry.speedKmh, equals(0.0));
      expect(telemetry.heading, equals(0.0));
      expect(telemetry.isMocked, isFalse);
      expect(telemetry.sourceDescription, equals('HARDWARE GPS SATELLITE'));
      expect(telemetry.timestamp, isNotNull);
    });

    test('TC1.3: Accurately handles integer numbers for float fields', () {
      final map = {
        'latitude': 13,
        'longitude': 80,
        'accuracy': 5,
        'altitude': 100,
        'speed': 20,
        'bearing': 90,
        'time': 1700000005000,
        'isMock': false,
      };

      final telemetry = GpsTelemetry.fromNativeMap(map);

      expect(telemetry.position.latitude, equals(13.0));
      expect(telemetry.position.longitude, equals(80.0));
      expect(telemetry.accuracyMeters, equals(5.0));
      expect(telemetry.altitudeMeters, equals(100.0));
      expect(telemetry.speedKmh, closeTo(72.0, 1e-4)); // 20 * 3.6
      expect(telemetry.heading, equals(90.0));
      expect(telemetry.isMocked, isFalse);
    });

    test('TC1.4: Handles negative or invalid bearing by clamping to zero', () {
      final map = {
        'latitude': 12.0,
        'longitude': 77.0,
        'accuracy': 3.0,
        'speed': 0.0,
        'bearing': -1.0, // Stationary indicator from iOS CoreLocation
      };

      final telemetry = GpsTelemetry.fromNativeMap(map);

      expect(telemetry.heading, equals(0.0));
      expect(telemetry.speedKmh, equals(0.0));
    });

    test('TC1.5: copyWith produces distinct copy with selective modifications', () {
      final original = GpsTelemetry(
        position: const LatLng(12.97, 77.59),
        accuracyMeters: 5.0,
        altitudeMeters: 900.0,
        speedKmh: 45.0,
        heading: 180.0,
        isMocked: false,
        sourceDescription: 'ORIGINAL SOURCE',
        timestamp: DateTime(2026, 11, 3),
      );

      final updated = original.copyWith(
        position: const LatLng(13.00, 77.65),
        speedKmh: 60.0,
        accuracyMeters: 3.5,
      );

      expect(updated.position.latitude, equals(13.00));
      expect(updated.position.longitude, equals(77.65));
      expect(updated.speedKmh, equals(60.0));
      expect(updated.accuracyMeters, equals(3.5));
      expect(updated.altitudeMeters, equals(900.0)); // Unchanged
      expect(updated.heading, equals(180.0));       // Unchanged
      expect(original.position.latitude, equals(12.97)); // Immutability verified
    });
  });
}
