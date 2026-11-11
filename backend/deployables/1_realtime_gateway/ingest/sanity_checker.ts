import { ValidatedTelemetry } from './telemetry.schemas';

export interface SanityCheckResult {
  valid: boolean;
  code?: string;
  reason?: string;
}

export interface PreviousLocationSnapshot {
  latitude: number;
  longitude: number;
  timestamp: number;
}

export class SanityChecker {
  private static readonly EARTH_RADIUS_METERS = 6371000;
  private static readonly MAX_DRIFT_FUTURE_MS = 5 * 60 * 1000; // 5 minutes
  private static readonly MAX_DRIFT_PAST_MS = 24 * 60 * 60 * 1000; // 24 hours
  private static readonly MAX_ACCURACY_METERS = 100.0;
  private static readonly MAX_VELOCITY_MPS = 100.0; // ~360 km/h

  /**
   * Calculates great-circle distance between two geodetic coordinates using Haversine formula.
   */
  public static haversineDistanceMeters(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number
  ): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180.0;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const phi1 = toRad(lat1);
    const phi2 = toRad(lat2);

    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const clampedA = Math.min(1, Math.max(0, a));
    const c = 2 * Math.atan2(Math.sqrt(clampedA), Math.sqrt(1 - clampedA));

    return this.EARTH_RADIUS_METERS * c;
  }

  /**
   * Performs multi-tier sanity boundary and anti-spoofing checks on incoming telemetry.
   */
  public static validate(
    telemetry: ValidatedTelemetry,
    prevSnapshot?: PreviousLocationSnapshot,
    currentTimeMs: number = Date.now()
  ): SanityCheckResult {
    // 1. Null Island check: GPS unacquired / default hardware register
    if (Math.abs(telemetry.latitude) < 0.000001 && Math.abs(telemetry.longitude) < 0.000001) {
      return {
        valid: false,
        code: 'NULL_ISLAND_COORDINATES',
        reason: 'GPS coordinates at Null Island (0,0) indicate uncalibrated sensor fix',
      };
    }

    // 2. Timestamp drift checks
    if (telemetry.timestamp > currentTimeMs + this.MAX_DRIFT_FUTURE_MS) {
      return {
        valid: false,
        code: 'FUTURE_TIMESTAMP',
        reason: 'Telemetry timestamp is skewed into future beyond acceptable threshold',
      };
    }

    if (telemetry.timestamp < currentTimeMs - this.MAX_DRIFT_PAST_MS) {
      return {
        valid: false,
        code: 'EXPIRED_TIMESTAMP',
        reason: 'Telemetry timestamp is older than 24 hours',
      };
    }

    // 3. Horizontal accuracy threshold check
    if (telemetry.accuracy > this.MAX_ACCURACY_METERS) {
      return {
        valid: false,
        code: 'POOR_GPS_ACCURACY',
        reason: `GPS accuracy ${telemetry.accuracy}m exceeds maximum allowed threshold of ${this.MAX_ACCURACY_METERS}m`,
      };
    }

    // 4. Physical displacement & teleportation check against previous snapshot
    if (prevSnapshot) {
      const deltaSec = (telemetry.timestamp - prevSnapshot.timestamp) / 1000.0;

      // Reject severely out-of-order points (>10s in the past relative to latest received)
      if (deltaSec < -10) {
        return {
          valid: false,
          code: 'OUT_OF_ORDER_TIMESTAMP',
          reason: 'Telemetry timestamp arrived significantly out of order',
        };
      }

      const distanceMeters = this.haversineDistanceMeters(
        prevSnapshot.latitude,
        prevSnapshot.longitude,
        telemetry.latitude,
        telemetry.longitude
      );

      // Displacements greater than GPS jitter threshold (> 25m) are strictly bounded by physics
      if (distanceMeters > 25.0) {
        if (deltaSec <= 0) {
          return {
            valid: false,
            code: 'TELEPORTATION_SPOOF_DETECTED',
            reason: `Displacement of ${distanceMeters.toFixed(
              1
            )}m detected with zero or negative elapsed time`,
          };
        }

        const calculatedVelocityMps = distanceMeters / deltaSec;
        if (calculatedVelocityMps > this.MAX_VELOCITY_MPS) {
          return {
            valid: false,
            code: 'TELEPORTATION_SPOOF_DETECTED',
            reason: `Displacement velocity ${calculatedVelocityMps.toFixed(
              1
            )} m/s exceeds physical limits (possible GPS spoofing or teleportation)`,
          };
        }
      }
    }

    return { valid: true };
  }
}

