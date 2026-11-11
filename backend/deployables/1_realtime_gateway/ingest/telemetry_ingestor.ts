import { db } from '../../../shared/src/database/db';
import { TelemetrySchema, ValidatedTelemetry } from './telemetry.schemas';
import { SanityChecker } from './sanity_checker';
import { TelemetryDownsampler } from './downsampler';
import { WriteBehindQueue } from './write_behind_queue';
import { RedisClientManager } from '../pubsub/redis_client_manager';
import { RoomManager } from '../pubsub/room_manager';
import { ClientContext } from '../src/types';

export interface IngestResult {
  success: boolean;
  code?: string;
  error?: string;
  persisted?: boolean;
}

export class TelemetryIngestor {
  constructor(
    private redisManager: RedisClientManager,
    private roomManager: RoomManager,
    private downsampler: TelemetryDownsampler,
    private writeBehindQueue: WriteBehindQueue
  ) {}

  public async ingest(
    rawPayload: any,
    context: ClientContext
  ): Promise<IngestResult> {
    const { userId, phoneE164 } = context;

    // 1. Strict Schema Validation with Zod
    const parseResult = TelemetrySchema.safeParse(rawPayload);
    if (!parseResult.success) {
      const issue = parseResult.error.issues[0];
      const issuePath = issue.path.join('.');
      return {
        success: false,
        code: 'SCHEMA_VALIDATION_ERROR',
        error: issuePath ? `${issuePath}: ${issue.message}` : issue.message,
      };
    }

    const telemetry: ValidatedTelemetry = parseResult.data;

    // Verify trip membership before ingesting trip-bound telemetry
    if (telemetry.tripId) {
      const isMember =
        context.joinedTrips.has(telemetry.tripId) ||
        (await db.isTripMember(telemetry.tripId, userId));
      if (!isMember) {
        return {
          success: false,
          code: 'FORBIDDEN_TRIP',
          error: 'User is not an authorized member of the specified trip',
        };
      }
    }

    // 2. Multi-tier Sanity & Anti-Spoofing Checks
    const sanity = SanityChecker.validate(telemetry, context.lastTelemetry);
    if (!sanity.valid) {
      return {
        success: false,
        code: sanity.code || 'SANITY_CHECK_FAILED',
        error: sanity.reason,
      };
    }

    // Update in-memory context snapshot only for monotonically advancing timestamps
    if (!context.lastTelemetry || telemetry.timestamp >= context.lastTelemetry.timestamp) {
      context.lastTelemetry = {
        latitude: telemetry.latitude,
        longitude: telemetry.longitude,
        timestamp: telemetry.timestamp,
      };
    }

    // 3. Redis GEOADD indexing for geospatial proximity and queries
    try {
      await this.redisManager.geoadd(
        'geo:riders',
        telemetry.longitude,
        telemetry.latitude,
        userId
      );

      if (telemetry.tripId) {
        await this.redisManager.geoadd(
          `geo:trip:${telemetry.tripId}`,
          telemetry.longitude,
          telemetry.latitude,
          userId
        );
      }

      // Ephemeral live snapshot cache with 120s TTL
      await this.redisManager.hset(`rider:pos:${userId}`, {
        latitude: telemetry.latitude,
        longitude: telemetry.longitude,
        speed: telemetry.speed,
        heading: telemetry.heading,
        altitude: telemetry.altitude,
        accuracy: telemetry.accuracy,
        timestamp: telemetry.timestamp,
        tripId: telemetry.tripId || '',
      });
      await this.redisManager.expire(`rider:pos:${userId}`, 120);
    } catch (err) {
      console.error('[TelemetryIngestor Redis GEO/HSET Error]:', err);
    }

    // 4. Downsampler Check & Asynchronous Write-Behind Queue
    let persisted = false;
    if (this.downsampler.shouldPersist(userId, telemetry)) {
      this.writeBehindQueue.enqueue({
        userId,
        latitude: telemetry.latitude,
        longitude: telemetry.longitude,
        speedKmh: telemetry.speed,
        bearingDegrees: telemetry.heading,
        recordedAt: new Date(telemetry.timestamp),
      });
      this.downsampler.recordPersisted(userId, telemetry);
      persisted = true;
    }

    // 5. Convoy Pub/Sub Fan-out across active riders
    if (telemetry.tripId) {
      await this.roomManager.publishLocation(
        telemetry.tripId,
        userId,
        phoneE164,
        telemetry
      );
    }

    return {
      success: true,
      persisted,
    };
  }

  public cleanupUser(userId: string): void {
    this.downsampler.clearUser(userId);
  }
}

