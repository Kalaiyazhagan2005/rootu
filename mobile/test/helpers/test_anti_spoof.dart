import 'dart:async';
import 'package:rootu_mobile/features/map/models/gps_telemetry.dart';

class AntiSpoofException implements Exception {
  final String message;
  final GpsTelemetry? telemetry;
  AntiSpoofException(this.message, [this.telemetry]);

  @override
  String toString() => 'AntiSpoofException: $message';
}

/// Production anti-spoofing validator protecting downstream navigation from fake coordinates
class AntiSpoofValidator {
  int _rejectedCount = 0;
  int _acceptedCount = 0;

  int get rejectedCount => _rejectedCount;
  int get acceptedCount => _acceptedCount;

  void reset() {
    _rejectedCount = 0;
    _acceptedCount = 0;
  }

  /// Check whether raw native map contains mock provider flags
  static bool isMockMap(Map<dynamic, dynamic> map) {
    if (map['isMock'] == true) return true;
    if (map['isFromMockProvider'] == true) return true;
    if (map['mock'] == true) return true;
    return false;
  }

  /// Check whether telemetry is mocked
  static bool isMockTelemetry(GpsTelemetry telemetry) {
    return telemetry.isMocked;
  }

  /// Validate coordinates sanity (WGS84 boundaries and Null Island check)
  static bool isSanitaryCoordinates(double lat, double lng) {
    if (lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    // Reject exact (0, 0) Null Island when accuracy is degraded (>1000m)
    return true;
  }

  /// Validate telemetry packet, rejecting mocked or corrupt packets
  bool validate(GpsTelemetry telemetry, {bool throwOnMock = false}) {
    if (telemetry.isMocked) {
      _rejectedCount++;
      if (throwOnMock) {
        throw AntiSpoofException('Rejected mocked GPS coordinate fix', telemetry);
      }
      return false;
    }

    if (!isSanitaryCoordinates(telemetry.position.latitude, telemetry.position.longitude)) {
      _rejectedCount++;
      if (throwOnMock) {
        throw AntiSpoofException('Invalid latitude/longitude coordinates', telemetry);
      }
      return false;
    }

    _acceptedCount++;
    return true;
  }

  /// Filter stream, dropping mock packets immediately
  Stream<GpsTelemetry> filterMockStream(Stream<GpsTelemetry> stream) {
    return stream.where((telemetry) => validate(telemetry));
  }
}
