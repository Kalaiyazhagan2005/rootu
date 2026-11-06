import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/gps_telemetry.dart';
import 'dynamic_heading_fusion.dart';
import 'gps_kalman_filter.dart';

/// Pure Dart pipeline service that bridges raw GpsTelemetry to smoothed/fused
/// GpsTelemetry using GpsKalmanFilter and DynamicHeadingFusion.
class GpsPipelineService {
  final GpsKalmanFilter _kalmanFilter;
  final DynamicHeadingFusion _headingFusion;

  /// Creates a GpsPipelineService with optional filter injection for testing.
  GpsPipelineService({
    GpsKalmanFilter? kalmanFilter,
    DynamicHeadingFusion? headingFusion,
  })  : _kalmanFilter = kalmanFilter ?? GpsKalmanFilter(),
        _headingFusion = headingFusion ?? DynamicHeadingFusion();

  /// Access to internal Kalman filter for telemetry or diagnostic status.
  GpsKalmanFilter get kalmanFilter => _kalmanFilter;

  /// Access to internal heading fusion engine.
  DynamicHeadingFusion get headingFusion => _headingFusion;

  /// Resets internal filters, reference origin, and covariance matrices.
  void reset() {
    _kalmanFilter.reset();
    _headingFusion.reset();
  }

  /// Processes a single raw telemetry packet and returns an updated GpsTelemetry
  /// instance with smoothed position, fused heading, and guaranteed 100% finite metrics.
  GpsTelemetry processTelemetry(GpsTelemetry raw) {
    final int timestampMs = raw.timestamp.millisecondsSinceEpoch;

    // Sanitize speed: enforce finite and non-negative
    final double safeSpeedKmh = (raw.speedKmh.isFinite && raw.speedKmh >= 0.0)
        ? raw.speedKmh
        : 0.0;
    final double speedMps = safeSpeedKmh / 3.6;

    // Sanitize accuracy: enforce finite and strictly positive (default 25.0m)
    final double safeAccuracy = (raw.accuracyMeters.isFinite && raw.accuracyMeters > 0.0)
        ? raw.accuracyMeters
        : 25.0;

    // Sanitize compass heading: null or finite in [0.0, 360.0]
    final double? safeCompass = (raw.compassHeading != null &&
            raw.compassHeading!.isFinite &&
            raw.compassHeading! >= 0.0 &&
            raw.compassHeading! <= 360.0)
        ? raw.compassHeading
        : null;

    // Sanitize altitude: enforce finite (default 0.0m)
    final double safeAltitude =
        raw.altitudeMeters.isFinite ? raw.altitudeMeters : 0.0;

    // 1. Spatial smoothing: eliminate discrete coordinate jumps
    final LatLng smoothedPosition = _kalmanFilter.filter(
      raw.position,
      safeAccuracy,
      speedMps,
      timestampMs,
    );

    // Sanitize smoothed position guarantee
    final LatLng safePosition = (smoothedPosition.latitude.isFinite &&
            smoothedPosition.longitude.isFinite)
        ? smoothedPosition
        : const LatLng(0.0, 0.0);

    // 2. Heading fusion: blend compass azimuth and GPS bearing based on speed
    final double fusedHeading = _headingFusion.update(
      safeCompass,
      raw.heading,
      safeSpeedKmh,
    );
    final double safeFusedHeading = fusedHeading.isFinite
        ? (fusedHeading % 360.0 + 360.0) % 360.0
        : 0.0;

    // 3. Return updated telemetry instance with 100% finite sanitized fields.
    // Construct directly to avoid copyWith null-coalescing pitfall where nullable
    // compassHeading: null falls back to this.compassHeading (retaining NaN).
    return GpsTelemetry(
      position: safePosition,
      accuracyMeters: safeAccuracy,
      altitudeMeters: safeAltitude,
      speedKmh: safeSpeedKmh,
      heading: safeFusedHeading,
      compassHeading: safeCompass,
      isMocked: raw.isMocked,
      sourceDescription: raw.sourceDescription,
      timestamp: raw.timestamp,
    );
  }

  /// Transforms an upstream Stream of raw GpsTelemetry into a smoothed stream.
  Stream<GpsTelemetry> transformStream(Stream<GpsTelemetry> rawStream) {
    return rawStream.map(processTelemetry);
  }

  /// Creates a StreamTransformer for idiomatic Dart stream composition:
  /// `rawStream.transform(GpsPipelineService.transformer())`
  static StreamTransformer<GpsTelemetry, GpsTelemetry> transformer({
    GpsKalmanFilter? kalmanFilter,
    DynamicHeadingFusion? headingFusion,
  }) {
    final pipeline = GpsPipelineService(
      kalmanFilter: kalmanFilter,
      headingFusion: headingFusion,
    );
    return StreamTransformer<GpsTelemetry, GpsTelemetry>.fromHandlers(
      handleData: (raw, sink) {
        sink.add(pipeline.processTelemetry(raw));
      },
      handleDone: (sink) {
        pipeline.reset();
        sink.close();
      },
    );
  }
}

