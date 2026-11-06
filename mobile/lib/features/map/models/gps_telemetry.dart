import 'package:latlong2/latlong.dart';

/// Strongly-typed production telemetry data model received from native platform channels
/// (Android FLP and Rotation Vector, iOS CoreLocation and Heading).
class GpsTelemetry {
  final LatLng position;
  final double accuracyMeters;
  final double altitudeMeters;
  final double speedKmh;

  /// GPS course bearing over ground in degrees (0..360), derived from GNSS satellite motion.
  final double heading;

  /// Physical device orientation / compass azimuth in degrees (0..360),
  /// or null if the hardware compass sensor is unavailable or uncalibrated.
  final double? compassHeading;

  final bool isMocked;
  final String sourceDescription;
  final DateTime timestamp;

  const GpsTelemetry({
    required this.position,
    required this.accuracyMeters,
    required this.altitudeMeters,
    required this.speedKmh,
    required this.heading,
    this.compassHeading,
    required this.isMocked,
    required this.sourceDescription,
    required this.timestamp,
  });

  /// Evaluates whether a raw platform map indicates a simulated or mock location.
  /// Checks all standard keys: 'isMock', 'isFromMockProvider', 'mock',
  /// 'is_mock', 'is_from_mock_provider', safely handling boolean, numeric (!= 0),
  /// and string ('true', '1') values without throwing TypeError.
  static bool isMapMocked(Map<dynamic, dynamic> map) {
    for (final key in const ['isMock', 'isFromMockProvider', 'mock', 'is_mock', 'is_from_mock_provider']) {
      final dynamic val = map[key];
      if (val == null) continue;
      if (val is bool && val) return true;
      if (val is num && val != 0) return true;
      if (val is String) {
        final lower = val.trim().toLowerCase();
        if (lower == 'true' || lower == '1') return true;
      }
    }
    return false;
  }

  /// Factory constructor to parse raw platform channel dictionary (Android FLP & iOS CoreLocation)
  factory GpsTelemetry.fromNativeMap(
    Map<dynamic, dynamic> map, {
    String source = 'HARDWARE GPS SATELLITE',
  }) {
    final num? rawLat = map['latitude'] as num?;
    final double lat = (rawLat != null &&
            rawLat.toDouble().isFinite &&
            rawLat.toDouble() >= -90.0 &&
            rawLat.toDouble() <= 90.0)
        ? rawLat.toDouble()
        : 0.0;

    final num? rawLng = map['longitude'] as num?;
    final double lng = (rawLng != null &&
            rawLng.toDouble().isFinite &&
            rawLng.toDouble() >= -180.0 &&
            rawLng.toDouble() <= 180.0)
        ? rawLng.toDouble()
        : 0.0;

    final num? rawAcc = (map['accuracy'] ?? map['accuracyMeters']) as num?;
    final double acc = (rawAcc != null &&
            rawAcc.toDouble().isFinite &&
            rawAcc.toDouble() > 0.0)
        ? rawAcc.toDouble()
        : 25.0;

    final num? rawAlt = map['altitude'] as num?;
    final double alt = (rawAlt != null && rawAlt.toDouble().isFinite)
        ? rawAlt.toDouble()
        : 0.0;

    final num? rawSpd = map['speed'] as num?;
    final double spd = (rawSpd != null &&
            rawSpd.toDouble().isFinite &&
            rawSpd.toDouble() > 0.0)
        ? (rawSpd.toDouble() * 3.6)
        : 0.0;

    final num? rawBrg = map['bearing'] as num?;
    final double brg = (rawBrg != null &&
            rawBrg.toDouble().isFinite &&
            rawBrg.toDouble() >= 0.0)
        ? (rawBrg.toDouble() == 360.0 ? 360.0 : (rawBrg.toDouble() % 360.0))
        : 0.0;

    final int? timeMs = (map['time'] as num?)?.toInt();
    final bool isMock = isMapMocked(map);

    // Parse native compass heading (0..360 degrees, or null if unavailable / negative / non-finite)
    final num? rawCompass =
        (map['compassHeading'] ?? map['compass_heading']) as num?;
    final double? compassHeading = (rawCompass != null &&
            rawCompass.toDouble().isFinite &&
            rawCompass.toDouble() >= 0.0 &&
            rawCompass.toDouble() <= 360.0)
        ? (rawCompass.toDouble() == 360.0
            ? 360.0
            : (rawCompass.toDouble() % 360.0))
        : null;

    return GpsTelemetry(
      position: LatLng(lat, lng),
      accuracyMeters: acc,
      altitudeMeters: alt,
      speedKmh: spd,
      heading: brg,
      compassHeading: compassHeading,
      isMocked: isMock,
      sourceDescription: source,
      timestamp: timeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(timeMs)
          : DateTime.now(),
    );
  }

  GpsTelemetry copyWith({
    LatLng? position,
    double? accuracyMeters,
    double? altitudeMeters,
    double? speedKmh,
    double? heading,
    double? compassHeading,
    bool? isMocked,
    String? sourceDescription,
    DateTime? timestamp,
  }) {
    return GpsTelemetry(
      position: position ?? this.position,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      speedKmh: speedKmh ?? this.speedKmh,
      heading: heading ?? this.heading,
      compassHeading: compassHeading ?? this.compassHeading,
      isMocked: isMocked ?? this.isMocked,
      sourceDescription: sourceDescription ?? this.sourceDescription,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpsTelemetry &&
          runtimeType == other.runtimeType &&
          position == other.position &&
          accuracyMeters == other.accuracyMeters &&
          altitudeMeters == other.altitudeMeters &&
          speedKmh == other.speedKmh &&
          heading == other.heading &&
          compassHeading == other.compassHeading &&
          isMocked == other.isMocked &&
          sourceDescription == other.sourceDescription &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
        position,
        accuracyMeters,
        altitudeMeters,
        speedKmh,
        heading,
        compassHeading,
        isMocked,
        sourceDescription,
        timestamp,
      );

  @override
  String toString() =>
      'GpsTelemetry(pos: $position, acc: ${accuracyMeters.toStringAsFixed(1)}m, '
      'spd: ${speedKmh.toStringAsFixed(1)}km/h, brg: ${heading.toStringAsFixed(1)} deg, '
      'compass: ${compassHeading != null ? '${compassHeading!.toStringAsFixed(1)} deg' : 'null'}, '
      'isMocked: $isMocked)';
}
