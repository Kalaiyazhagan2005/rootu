import { WebSocket } from 'ws';
import { db } from '../../../shared/src/database/db';
import { ClientContext, TelemetryPayload } from '../src/types';
import { RedisClientManager } from './redis_client_manager';
import { ValidatedTelemetry } from '../ingest/telemetry.schemas';

export type RoomEmptyListener = (tripId: string) => Promise<void> | void;

export class RoomManager {
  private tripRooms = new Map<string, Set<WebSocket>>();
  private socketTrips = new Map<WebSocket, Set<string>>();
  private socketUsers = new Map<WebSocket, string>();
  private subscribedChannels = new Set<string>();
  private roomEmptyListeners = new Set<RoomEmptyListener>();

  constructor(private redisManager: RedisClientManager) {}

  public onRoomEmpty(listener: RoomEmptyListener): void {
    this.roomEmptyListeners.add(listener);
  }

  public async joinTrip(
    tripId: string,
    context: ClientContext
  ): Promise<{ success: boolean; activeRiders: string[]; error?: string }> {
    const { socket, userId } = context;

    // 1. Verify trip existence and membership
    const trip = await db.findTripById(tripId);
    if (!trip) {
      return { success: false, activeRiders: [], error: 'Trip does not exist' };
    }

    if (!trip.isActive) {
      return { success: false, activeRiders: [], error: 'Trip is no longer active' };
    }

    const isMember = await db.isTripMember(tripId, userId);
    if (!isMember) {
      return {
        success: false,
        activeRiders: [],
        error: 'User is not an authorized member of this trip',
      };
    }

    // Idempotent join: if already joined on this socket, return active riders immediately
    if (context.joinedTrips.has(tripId)) {
      const activeRiders = await this.redisManager.smembers(`trip:${tripId}:active_riders`);
      return { success: true, activeRiders };
    }

    // 2. Add socket to local room structures
    let roomSockets = this.tripRooms.get(tripId);
    if (!roomSockets) {
      roomSockets = new Set();
      this.tripRooms.set(tripId, roomSockets);
    }
    roomSockets.add(socket);

    let tripsForSocket = this.socketTrips.get(socket);
    if (!tripsForSocket) {
      tripsForSocket = new Set();
      this.socketTrips.set(socket, tripsForSocket);
    }
    tripsForSocket.add(tripId);
    this.socketUsers.set(socket, userId);
    context.joinedTrips.add(tripId);

    // 3. Register in Redis active riders set
    await this.redisManager.sadd(`trip:${tripId}:active_riders`, userId);

    // 4. Ensure subscription to Redis location channel for this trip
    const locationChannel = `rootu:trip:${tripId}:locations`;
    if (!this.subscribedChannels.has(locationChannel)) {
      this.subscribedChannels.add(locationChannel);
      await this.redisManager.subscribe(locationChannel, (message) => {
        this.handleLocationChannelMessage(tripId, message);
      });
    }

    // 5. Broadcast rider joined notification to convoy
    await this.redisManager.publish(
      `rootu:trip:${tripId}:alerts`,
      JSON.stringify({
        type: 'trip:rider_joined',
        tripId,
        userId,
        timestamp: Date.now(),
      })
    );

    const activeRiders = await this.redisManager.smembers(`trip:${tripId}:active_riders`);
    return { success: true, activeRiders };
  }

  public async leaveTrip(tripId: string, context: ClientContext): Promise<void> {
    const { socket, userId } = context;

    this.socketUsers.delete(socket);

    const roomSockets = this.tripRooms.get(tripId);
    if (roomSockets) {
      roomSockets.delete(socket);
      if (roomSockets.size === 0) {
        this.tripRooms.delete(tripId);
        // Unsubscribe from Redis location channel if no local sockets remain
        const locationChannel = `rootu:trip:${tripId}:locations`;
        if (this.subscribedChannels.has(locationChannel)) {
          this.subscribedChannels.delete(locationChannel);
          await this.redisManager.unsubscribe(locationChannel);
        }

        // Notify room empty listeners to clean up alert channel subscriptions
        for (const listener of this.roomEmptyListeners) {
          try {
            await listener(tripId);
          } catch (err) {
            console.error('[RoomManager onRoomEmpty error]:', err);
          }
        }
      }
    }

    const tripsForSocket = this.socketTrips.get(socket);
    if (tripsForSocket) {
      tripsForSocket.delete(tripId);
      if (tripsForSocket.size === 0) {
        this.socketTrips.delete(socket);
      }
    }
    context.joinedTrips.delete(tripId);

    // Check if THIS user has any other active socket in this trip
    let hasOtherSocketInTrip = false;
    const remainingSockets = this.tripRooms.get(tripId);
    if (remainingSockets) {
      for (const s of remainingSockets) {
        if (this.socketUsers.get(s) === userId) {
          hasOtherSocketInTrip = true;
          break;
        }
      }
    }

    if (!hasOtherSocketInTrip) {
      await this.redisManager.srem(`trip:${tripId}:active_riders`, userId);
      await this.redisManager.publish(
        `rootu:trip:${tripId}:alerts`,
        JSON.stringify({
          type: 'trip:rider_left',
          tripId,
          userId,
          timestamp: Date.now(),
        })
      );
    }
  }

  public async leaveAllTrips(socket: WebSocket, context: ClientContext): Promise<void> {
    const trips = Array.from(context.joinedTrips);
    for (const tripId of trips) {
      await this.leaveTrip(tripId, context);
    }
  }

  public async publishLocation(
    tripId: string,
    userId: string,
    phoneE164: string,
    telemetry: ValidatedTelemetry
  ): Promise<void> {
    const payload = JSON.stringify({
      tripId,
      userId,
      phoneE164,
      telemetry,
      publishedAt: Date.now(),
    });
    await this.redisManager.publish(`rootu:trip:${tripId}:locations`, payload);
  }

  private handleLocationChannelMessage(tripId: string, message: string): void {
    try {
      const data = JSON.parse(message);
      const roomSockets = this.tripRooms.get(tripId);
      if (!roomSockets) return;

      const broadcastMsg = JSON.stringify({
        type: 'telemetry:broadcast',
        tripId,
        userId: data.userId,
        phoneE164: data.phoneE164,
        data: data.telemetry,
      });

      for (const sock of roomSockets) {
        if (sock.readyState === WebSocket.OPEN) {
          try {
            sock.send(broadcastMsg);
          } catch (err) {
            console.error('[RoomManager send error]:', err);
          }
        }
      }
    } catch (err) {
      console.error('[RoomManager location parse error]:', err);
    }
  }

  public broadcastToRoom(tripId: string, message: any, excludeSocket?: WebSocket): number {
    const roomSockets = this.tripRooms.get(tripId);
    if (!roomSockets) return 0;

    const payload = typeof message === 'string' ? message : JSON.stringify(message);
    let count = 0;

    for (const sock of roomSockets) {
      if (sock !== excludeSocket && sock.readyState === WebSocket.OPEN) {
        try {
          sock.send(payload);
          count++;
        } catch (err) {
          console.error('[RoomManager broadcastToRoom error]:', err);
        }
      }
    }
    return count;
  }

  public getActiveTripsCount(): number {
    return this.tripRooms.size;
  }

  public getRoomSocketCount(tripId: string): number {
    return this.tripRooms.get(tripId)?.size || 0;
  }
}

