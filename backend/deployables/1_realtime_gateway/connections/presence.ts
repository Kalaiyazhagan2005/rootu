import { RedisClientManager } from '../pubsub/redis_client_manager';

export class PresenceTracker {
  private localOnlineUsers = new Set<string>();

  constructor(private redisManager: RedisClientManager) {}

  public async setUserOnline(userId: string): Promise<void> {
    this.localOnlineUsers.add(userId);
    try {
      await this.redisManager.sadd('presence:online_users', userId);
      await this.redisManager.hset(`presence:user:${userId}`, {
        status: 'online',
        lastSeenAt: Date.now(),
      });
      await this.redisManager.expire(`presence:user:${userId}`, 180);
    } catch (err) {
      console.error('[PresenceTracker setUserOnline Error]:', err);
    }
  }

  public async refreshUserPresence(userId: string): Promise<void> {
    if (!this.localOnlineUsers.has(userId)) return;
    try {
      await this.redisManager.expire(`presence:user:${userId}`, 180);
    } catch (err) {
      // Ignored
    }
  }

  public async setUserOffline(userId: string): Promise<void> {
    this.localOnlineUsers.delete(userId);
    try {
      await this.redisManager.srem('presence:online_users', userId);
      await this.redisManager.hset(`presence:user:${userId}`, {
        status: 'offline',
        lastSeenAt: Date.now(),
      });
      await this.redisManager.expire(`presence:user:${userId}`, 60);
    } catch (err) {
      console.error('[PresenceTracker setUserOffline Error]:', err);
    }
  }

  public async isUserOnline(userId: string): Promise<boolean> {
    if (this.localOnlineUsers.has(userId)) {
      return true;
    }
    try {
      const isMember = await this.redisManager.sismember('presence:online_users', userId);
      return isMember === 1;
    } catch (err) {
      console.error('[PresenceTracker isUserOnline Error]:', err);
      return false;
    }
  }

  public async setTripPresence(tripId: string, userId: string, joined: boolean): Promise<void> {
    const key = `trip:${tripId}:active_riders`;
    try {
      if (joined) {
        await this.redisManager.sadd(key, userId);
      } else {
        await this.redisManager.srem(key, userId);
      }
    } catch (err) {
      console.error('[PresenceTracker setTripPresence Error]:', err);
    }
  }

  public async getActiveTripRiders(tripId: string): Promise<string[]> {
    const key = `trip:${tripId}:active_riders`;
    try {
      return await this.redisManager.smembers(key);
    } catch (err) {
      console.error('[PresenceTracker getActiveTripRiders Error]:', err);
      return [];
    }
  }

  public async getTotalOnlineRidersCount(): Promise<number> {
    try {
      const members = await this.redisManager.smembers('presence:online_users');
      return members.length;
    } catch (err) {
      return this.localOnlineUsers.size;
    }
  }

  public getLocalOnlineUsers(): string[] {
    return Array.from(this.localOnlineUsers);
  }
}

