import { RedisClientManager } from './redis_client_manager';
import { RoomManager } from './room_manager';

export interface EmergencyAlert {
  tripId: string;
  userId: string;
  alertType: 'SOS' | 'CRASH' | 'PANIC';
  details?: string;
  location: {
    latitude: number;
    longitude: number;
  };
  timestamp: number;
}

export interface TeaBreakAlert {
  tripId: string;
  userId: string;
  action: 'PROPOSED' | 'STARTED' | 'RESUMED';
  proposedLocation?: {
    latitude: number;
    longitude: number;
    name?: string;
  };
  timestamp: number;
}

export class AlertRouter {
  private subscribedTrips = new Set<string>();

  constructor(
    private redisManager: RedisClientManager,
    private roomManager: RoomManager
  ) {}

  public async subscribeTripAlerts(tripId: string): Promise<void> {
    if (this.subscribedTrips.has(tripId)) return;
    this.subscribedTrips.add(tripId);

    const emergencyChannel = `rootu:trip:${tripId}:emergency`;
    const alertsChannel = `rootu:trip:${tripId}:alerts`;

    await this.redisManager.subscribe(emergencyChannel, (message) => {
      try {
        const alert = JSON.parse(message);
        this.roomManager.broadcastToRoom(tripId, {
          type: 'emergency:alert',
          tripId: alert.tripId,
          userId: alert.userId,
          alertType: alert.alertType,
          details: alert.details,
          location: alert.location,
          timestamp: alert.timestamp,
        });
      } catch (err) {
        console.error('[AlertRouter emergency message parse error]:', err);
      }
    });

    await this.redisManager.subscribe(alertsChannel, (message) => {
      try {
        const alert = JSON.parse(message);
        this.roomManager.broadcastToRoom(tripId, alert);
      } catch (err) {
        console.error('[AlertRouter general alert message parse error]:', err);
      }
    });
  }

  public async unsubscribeTripAlerts(tripId: string): Promise<void> {
    if (!this.subscribedTrips.has(tripId)) return;
    this.subscribedTrips.delete(tripId);

    await this.redisManager.unsubscribe(`rootu:trip:${tripId}:emergency`);
    await this.redisManager.unsubscribe(`rootu:trip:${tripId}:alerts`);
  }

  public isSubscribed(tripId: string): boolean {
    return this.subscribedTrips.has(tripId);
  }

  public async routeEmergency(alert: EmergencyAlert): Promise<void> {
    const channel = `rootu:trip:${alert.tripId}:emergency`;
    const payload = JSON.stringify(alert);
    await this.redisManager.publish(channel, payload);
  }

  public async routeTeaBreak(alert: TeaBreakAlert): Promise<void> {
    const channel = `rootu:trip:${alert.tripId}:alerts`;
    const payload = JSON.stringify({
      type: 'convoy:tea_break_alert',
      tripId: alert.tripId,
      userId: alert.userId,
      action: alert.action,
      proposedLocation: alert.proposedLocation,
      timestamp: alert.timestamp,
    });
    await this.redisManager.publish(channel, payload);
  }
}

