import { ValidatedTelemetry } from './telemetry.schemas';
import { SanityChecker } from './sanity_checker';

export interface DownsamplerOptions {
  minIntervalMs?: number; // e.g. 5000ms
  minDistanceMeters?: number; // e.g. 25m
  minHeadingDegrees?: number; // e.g. 30 deg
}

export interface LastPersistedPoint {
  latitude: number;
  longitude: number;
  speed: number;
  heading: number;
  timestamp: number;
}

export class TelemetryDownsampler {
  private lastPersistedByUser = new Map<string, LastPersistedPoint>();
  private readonly minIntervalMs: number;
  private readonly minDistanceMeters: number;
  private readonly minHeadingDegrees: number;

  constructor(options: DownsamplerOptions = {}) {
    this.minIntervalMs = options.minIntervalMs || 5000;
    this.minDistanceMeters = options.minDistanceMeters || 25;
    this.minHeadingDegrees = options.minHeadingDegrees || 30;
  }

  public shouldPersist(userId: string, telemetry: ValidatedTelemetry): boolean {
    const last = this.lastPersistedByUser.get(userId);

    if (!last) {
      // First point is always persisted
      return true;
    }

    const elapsedMs = telemetry.timestamp - last.timestamp;
    if (elapsedMs < 1000) {
      // Never persist faster than 1 second to avoid database congestion
      return false;
    }

    // 1. Time threshold reached
    if (elapsedMs >= this.minIntervalMs) {
      return true;
    }

    // 2. Distance displacement threshold reached
    const distanceMeters = SanityChecker.haversineDistanceMeters(
      last.latitude,
      last.longitude,
      telemetry.latitude,
      telemetry.longitude
    );
    if (distanceMeters >= this.minDistanceMeters) {
      return true;
    }

    // 3. Significant heading / turn change
    const headingDiff = Math.abs(telemetry.heading - last.heading);
    const normalizedHeadingDiff = headingDiff > 180 ? 360 - headingDiff : headingDiff;
    if (normalizedHeadingDiff >= this.minHeadingDegrees && telemetry.speed > 5) {
      return true;
    }

    // 4. Significant speed change (stopped <-> moving)
    const wasStopped = last.speed < 2.0;
    const isMoving = telemetry.speed >= 10.0;
    if (wasStopped && isMoving) {
      return true;
    }
    const wasMoving = last.speed >= 10.0;
    const isStopped = telemetry.speed < 2.0;
    if (wasMoving && isStopped) {
      return true;
    }

    return false;
  }

  public recordPersisted(userId: string, telemetry: ValidatedTelemetry): void {
    this.lastPersistedByUser.set(userId, {
      latitude: telemetry.latitude,
      longitude: telemetry.longitude,
      speed: telemetry.speed,
      heading: telemetry.heading,
      timestamp: telemetry.timestamp,
    });
  }

  public clearUser(userId: string): void {
    this.lastPersistedByUser.delete(userId);
  }

  public hasUser(userId: string): boolean {
    return this.lastPersistedByUser.has(userId);
  }

  public clearAll(): void {
    this.lastPersistedByUser.clear();
  }
}

