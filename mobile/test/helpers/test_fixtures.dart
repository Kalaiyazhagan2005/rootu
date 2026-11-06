import 'package:latlong2/latlong.dart';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';

/// Synthetic and real-world test datasets for telemetry and sensor fusion verification
class TestFixtures {
  // Origin coordinate for realistic test scenarios (Bangalore Tech Corridor)
  static const double originLat = 12.9716;
  static const double originLng = 77.5946;

  /// 20-Waypoint simulated commuter route with acceleration, turns, cruising, and stop
  static List<GpsTelemetry> get commuterRouteTelemetry {
    final List<GpsTelemetry> route = [];
    int baseTime = 1700000000000;

    // Stage 1: Stationary at origin (Points 0-2)
    for (int i = 0; i < 3; i++) {
      route.add(GpsTelemetry(
        position: const LatLng(originLat, originLng),
        accuracyMeters: 4.2,
        altitudeMeters: 920.0,
        speedKmh: 0.0,
        heading: 90.0, // facing East
        isMocked: false,
        sourceDescription: 'TEST SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + i * 1000),
      ));
    }

    // Stage 2: Accelerating East along MG Road (Points 3-7)
    for (int i = 1; i <= 5; i++) {
      const double lat = originLat;
      final double lng = originLng + (i * 0.00015);
      final double speed = i * 7.2; // accelerates up to 36 km/h
      route.add(GpsTelemetry(
        position: LatLng(lat, lng),
        accuracyMeters: 3.8,
        altitudeMeters: 920.5,
        speedKmh: speed,
        heading: 90.0, // East
        isMocked: false,
        sourceDescription: 'TEST SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + (i + 2) * 1000),
      ));
    }

    // Stage 3: Sharp Right Turn South onto Brigade Road (Points 8-11)
    const double turnLng = originLng + (5 * 0.00015);
    const turnHeadings = [112.5, 135.0, 157.5, 180.0];
    for (int i = 0; i < 4; i++) {
      final double lat = originLat - ((i + 1) * 0.00010);
      route.add(GpsTelemetry(
        position: LatLng(lat, turnLng),
        accuracyMeters: 5.5,
        altitudeMeters: 919.0,
        speedKmh: 20.0,
        heading: turnHeadings[i],
        isMocked: false,
        sourceDescription: 'TEST SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + (i + 8) * 1000),
      ));
    }

    // Stage 4: Cruising South at 50 km/h (Points 12-16)
    for (int i = 1; i <= 5; i++) {
      final double lat = (originLat - (4 * 0.00010)) - (i * 0.00025);
      route.add(GpsTelemetry(
        position: LatLng(lat, turnLng),
        accuracyMeters: 4.0,
        altitudeMeters: 918.0,
        speedKmh: 50.0,
        heading: 180.0, // South
        isMocked: false,
        sourceDescription: 'TEST SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + (i + 11) * 1000),
      ));
    }

    // Stage 5: Decelerating to a Red Light Stop (Points 17-19)
    const double stopLat = (originLat - (4 * 0.00010)) - (5 * 0.00025);
    const decelSpeeds = [28.0, 12.0, 0.0];
    for (int i = 0; i < 3; i++) {
      route.add(GpsTelemetry(
        position: LatLng(stopLat - (i * 0.00004), turnLng),
        accuracyMeters: 4.8,
        altitudeMeters: 917.5,
        speedKmh: decelSpeeds[i],
        heading: 180.0,
        isMocked: false,
        sourceDescription: 'TEST SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + (i + 17) * 1000),
      ));
    }

    return route;
  }

  /// High-density Urban Canyon sequence: Straight line with +-15m multipath jitter
  static List<GpsTelemetry> get urbanCanyonJitterSequence {
    final List<GpsTelemetry> sequence = [];
    int baseTime = 1700000000000;
    // Jitter offsets simulating tall skyscrapers reflecting GPS signals
    const lateralJitterMeters = [
      0.0, 8.5, -12.4, 14.8, -9.2, 11.5, -14.0, 7.8, -6.5, 12.0,
      -8.0, 10.2, -13.5, 9.0, -11.0, 6.5, -7.0, 13.2, -9.5, 0.0,
    ];

    const double metersPerLatDegree = 111139.0;
    const double metersPerLngDegree = metersPerLatDegree * 0.97448; // cos(12.97 deg)

    for (int i = 0; i < 20; i++) {
      // Nominal trajectory: moving North along longitude line
      final double nominalLat = originLat + (i * 0.00010);
      const double nominalLng = originLng;

      // Add lateral jitter to longitude
      final double jitterMeters = lateralJitterMeters[i];
      final double jitteredLng = nominalLng + (jitterMeters / metersPerLngDegree);

      sequence.add(GpsTelemetry(
        position: LatLng(nominalLat, jitteredLng),
        accuracyMeters: 12.0 + (jitterMeters.abs() * 0.8), // Accuracy degrades during multipath
        altitudeMeters: 920.0,
        speedKmh: 18.0,
        heading: 0.0, // North
        isMocked: false,
        sourceDescription: 'URBAN CANYON SATELLITE',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + i * 1000),
      ));
    }
    return sequence;
  }

  /// Indoor stationary sequence: 30 seconds held on table with micro-compass perturbations
  static List<GpsTelemetry> get indoorStationarySequence {
    final List<GpsTelemetry> sequence = [];
    int baseTime = 1700000000000;
    const compassJitter = [
      45.0, 48.0, 43.5, 46.2, 44.1, 49.0, 42.8, 45.5, 47.1, 44.6,
      46.0, 43.9, 45.2, 48.3, 44.0, 46.5, 47.8, 43.2, 45.0, 46.1,
    ];

    for (int i = 0; i < 20; i++) {
      sequence.add(GpsTelemetry(
        position: const LatLng(originLat, originLng),
        accuracyMeters: 22.0, // Indoor coarse accuracy
        altitudeMeters: 925.0,
        speedKmh: 0.0, // Completely stationary
        heading: compassJitter[i],
        isMocked: false,
        sourceDescription: 'INDOOR FIX',
        timestamp: DateTime.fromMillisecondsSinceEpoch(baseTime + i * 1000),
      ));
    }
    return sequence;
  }
}
