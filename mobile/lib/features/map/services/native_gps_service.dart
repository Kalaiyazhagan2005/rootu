import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gps_telemetry.dart';
import 'gps_pipeline_service.dart';

/// Production native GPS service interfacing with Android FLP and iOS CoreLocation channels
/// with rigorous anti-spoof rejection of mock/simulated coordinates.
class NativeGpsService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.rootu_mobile/gps_hardware');
  static const EventChannel _eventChannel =
      EventChannel('com.example.rootu_mobile/gps_stream');

  /// Cached transformed broadcast stream ensuring zero mock data reaches subscribers
  static Stream<GpsTelemetry>? _validatedTelemetryStream;

  /// Pipeline service instance for coordinate smoothing and heading fusion
  static final GpsPipelineService _pipelineService = GpsPipelineService();
  static Stream<GpsTelemetry>? _smoothedTelemetryStream;

  /// Optional audit stream of rejected mock packets for security diagnostics / testing
  static final StreamController<GpsTelemetry> _mockDetectionController =
      StreamController<GpsTelemetry>.broadcast();

  /// Stream of detected and rejected mock telemetry packets
  static Stream<GpsTelemetry> get mockDetectionStream =>
      _mockDetectionController.stream;

  /// Optional callback invoked when a mock location is detected and rejected
  static void Function(GpsTelemetry rejectedTelemetry)? onMockLocationDetected;

  /// Explicitly start native GPS streaming hardware
  static Future<bool> startGpsStream() async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startGpsStream');
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly stop native GPS streaming hardware
  static Future<bool> stopGpsStream() async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('stopGpsStream');
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Query if GPS hardware is available on the device
  static Future<bool> isGpsHardwareAvailable() async {
    try {
      final bool? result =
          await _methodChannel.invokeMethod<bool>('isGpsHardwareAvailable');
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Check whether hardware location services are enabled on device
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Ensure location permissions (Precise Location) are granted
  static Future<LocationPermission> checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      try {
        final accuracyStatus = await Geolocator.getLocationAccuracy();
        if (accuracyStatus == LocationAccuracyStatus.reduced) {
          await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'preciseMapNavigation',
          );
        }
      } catch (_) {
        // Ignored on platforms not supporting accuracy status
      }
    }
    return permission;
  }

  /// Query the native hardware GPS chip for immediate cached fix, with anti-spoof validation
  static Future<GpsTelemetry?> getImmediateHardwareFix() async {
    try {
      final dynamic rawGps = await _methodChannel.invokeMethod('getRawGpsLocation');
      if (rawGps != null && rawGps is Map) {
        final telemetry = GpsTelemetry.fromNativeMap(
          rawGps,
          source: 'HARDWARE GPS SATELLITE',
        );

        if (GpsTelemetry.isMapMocked(rawGps) || telemetry.isMocked) {
          _handleMockRejection(telemetry, source: 'CACHED HARDWARE FIX');
          return null;
        }

        return telemetry;
      }
    } catch (_) {}
    return null;
  }

  /// Processes an immediate hardware fix through the pipeline to ensure
  /// consistent initialization between cached and streaming fixes.
  static Future<GpsTelemetry?> getImmediateSmoothedFix() async {
    final rawFix = await getImmediateHardwareFix();
    if (rawFix == null) return null;
    return _pipelineService.processTelemetry(rawFix);
  }

  /// Clean broadcast stream of authentic, validated real-time hardware GPS telemetry.
  /// Drops mock/simulated coordinates immediately so zero mock data reaches downstream UI.
  static Stream<GpsTelemetry> get telemetryStream {
    return _validatedTelemetryStream ??= _createValidatedStream();
  }

  /// Broadcast stream of authentic, Kalman-smoothed, and heading-fused GPS telemetry.
  /// Ready for consumption by 60 FPS GpsGliderController and MapScreen.
  static Stream<GpsTelemetry> get smoothedTelemetryStream {
    return _smoothedTelemetryStream ??=
        _pipelineService.transformStream(telemetryStream).asBroadcastStream();
  }

  /// Internal pipeline creating the filtered broadcast stream
  static Stream<GpsTelemetry> _createValidatedStream() {
    return _eventChannel
        .receiveBroadcastStream()
        .where((dynamic event) => event is Map)
        .where((dynamic event) {
          final map = event as Map;
          if (GpsTelemetry.isMapMocked(map)) {
            final telemetry = GpsTelemetry.fromNativeMap(
              map,
              source: 'LIVE GPS SATELLITE',
            );
            _handleMockRejection(telemetry, source: 'LIVE GPS STREAM');
            return false;
          }
          return true;
        })
        .map((dynamic event) {
          return GpsTelemetry.fromNativeMap(
            event as Map,
            source: 'LIVE GPS SATELLITE',
          );
        })
        .where((GpsTelemetry telemetry) {
          if (telemetry.isMocked) {
            _handleMockRejection(telemetry, source: 'LIVE GPS STREAM');
            return false; // Reject and drop mock coordinate
          }
          return true; // Authentic GPS fix accepted
        });
  }

  /// Internal logging and notification handler for rejected mock packets
  static void _handleMockRejection(GpsTelemetry telemetry, {required String source}) {
    developer.log(
      '[AntiSpoofValidator] REJECTED mock GPS telemetry from $source at '
      '(${telemetry.position.latitude}, ${telemetry.position.longitude}), '
      'accuracy=${telemetry.accuracyMeters}m. Zero mock data enforced.',
      name: 'NativeGpsService',
      level: 900,
    );

    debugPrint(
      '[AntiSpoofValidator] Mock location packet dropped from $source: '
      'lat=${telemetry.position.latitude}, lng=${telemetry.position.longitude}',
    );

    if (!_mockDetectionController.isClosed) {
      _mockDetectionController.add(telemetry);
    }
    onMockLocationDetected?.call(telemetry);
  }

  /// Open device GPS settings
  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Open app permissions settings
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Testing hook to reset cached streams or inject mock event channel in tests
  @visibleForTesting
  static void resetForTesting() {
    _validatedTelemetryStream = null;
    _smoothedTelemetryStream = null;
    _pipelineService.reset();
    onMockLocationDetected = null;
  }
}
