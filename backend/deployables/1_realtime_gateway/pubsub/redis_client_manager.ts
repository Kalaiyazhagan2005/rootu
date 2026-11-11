import Redis, { Redis as RedisType } from 'ioredis';
import { EventEmitter } from 'events';
import { config } from '../../../shared/src/config/env';

export interface RedisManagerOptions {
  url?: string;
  inMemoryFallback?: boolean;
}

export class RedisClientManager {
  private primaryClient: RedisType | null = null;
  private pubClient: RedisType | null = null;
  private subClient: RedisType | null = null;
  private inMemoryEmitter = new EventEmitter();
  private inMemorySets = new Map<string, Set<string>>();
  private inMemoryHashes = new Map<string, Map<string, string>>();
  private inMemoryGeo = new Map<string, Map<string, { longitude: number; latitude: number }>>();
  private subCallbacks = new Map<string, Set<(message: string, channel: string) => void>>();
  private patternCallbacks = new Map<string, Set<(message: string, channel: string) => void>>();
  private isFallback = false;
  private isClosed = false;

  constructor(private options: RedisManagerOptions = {}) {
    this.inMemoryEmitter.setMaxListeners(0);
  }

  public async initialize(): Promise<void> {
    if (this.options.inMemoryFallback) {
      this.isFallback = true;
      return;
    }

    const redisUrl = this.options.url || config.redis.url;

    try {
      this.primaryClient = new Redis(redisUrl, {
        lazyConnect: true,
        maxRetriesPerRequest: 3,
        retryStrategy: (times) => {
          if (times > 5) {
            return null; // Stop retrying after 5 attempts
          }
          return Math.min(times * 100, 2000);
        },
      });

      this.primaryClient.on('error', (err) => {
        // Suppress unhandled rejection, connection errors handled gracefully
        console.error('[RealtimeGateway Redis Primary Error]:', err.message);
      });

      await this.primaryClient.connect();

      this.pubClient = this.primaryClient.duplicate();
      this.subClient = this.primaryClient.duplicate();

      this.pubClient.on('error', (err) => {
        console.error('[RealtimeGateway Redis Pub Error]:', err.message);
      });

      this.subClient.on('error', (err) => {
        console.error('[RealtimeGateway Redis Sub Error]:', err.message);
      });

      await Promise.all([this.pubClient.connect(), this.subClient.connect()]);

      // Handle message distribution on subscriber client
      this.subClient.on('message', (channel, message) => {
        const callbacks = this.subCallbacks.get(channel);
        if (callbacks) {
          for (const cb of callbacks) {
            try {
              cb(message, channel);
            } catch (err) {
              console.error('[RealtimeGateway PubSub Callback Error]:', err);
            }
          }
        }
      });

      this.subClient.on('pmessage', (pattern, channel, message) => {
        const callbacks = this.patternCallbacks.get(pattern);
        if (callbacks) {
          for (const cb of callbacks) {
            try {
              cb(message, channel);
            } catch (err) {
              console.error('[RealtimeGateway PubSub Pattern Callback Error]:', err);
            }
          }
        }
      });
    } catch (err: any) {
      console.warn('[RealtimeGateway Redis Init Failed - Activating in-memory fallback]:', err.message);
      this.isFallback = true;
      if (this.primaryClient) {
        this.primaryClient.disconnect();
        this.primaryClient = null;
      }
      if (this.pubClient) {
        this.pubClient.disconnect();
        this.pubClient = null;
      }
      if (this.subClient) {
        this.subClient.disconnect();
        this.subClient = null;
      }
    }
  }

  public getStatus(): 'ready' | 'connecting' | 'fallback' | 'closed' {
    if (this.isClosed) return 'closed';
    if (this.isFallback) return 'fallback';
    if (this.primaryClient && this.primaryClient.status === 'ready') return 'ready';
    return 'connecting';
  }

  public async publish(channel: string, message: string): Promise<number> {
    if (this.isFallback || !this.pubClient) {
      this.inMemoryEmitter.emit(channel, message, channel);
      // Also emit to matching pattern listeners
      for (const [pattern] of this.patternCallbacks) {
        const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
        if (regex.test(channel)) {
          this.inMemoryEmitter.emit(`pattern:${pattern}`, message, channel);
        }
      }
      return 1;
    }
    return this.pubClient.publish(channel, message);
  }

  public async subscribe(channel: string, handler: (message: string, channel: string) => void): Promise<void> {
    let callbacks = this.subCallbacks.get(channel);
    if (!callbacks) {
      callbacks = new Set();
      this.subCallbacks.set(channel, callbacks);
    }
    callbacks.add(handler);

    if (this.isFallback || !this.subClient) {
      this.inMemoryEmitter.on(channel, handler);
      return;
    }

    if (callbacks.size === 1) {
      await this.subClient.subscribe(channel);
    }
  }

  public async unsubscribe(channel: string, handler?: (message: string, channel: string) => void): Promise<void> {
    const callbacks = this.subCallbacks.get(channel);
    if (!callbacks) return;

    if (handler) {
      callbacks.delete(handler);
      if (this.isFallback || !this.subClient) {
        this.inMemoryEmitter.off(channel, handler);
      }
    } else {
      callbacks.clear();
      if (this.isFallback || !this.subClient) {
        this.inMemoryEmitter.removeAllListeners(channel);
      }
    }

    if (callbacks.size === 0) {
      this.subCallbacks.delete(channel);
      if (!this.isFallback && this.subClient && this.subClient.status === 'ready') {
        await this.subClient.unsubscribe(channel);
      }
    }
  }

  public async psubscribe(pattern: string, handler: (message: string, channel: string) => void): Promise<void> {
    let callbacks = this.patternCallbacks.get(pattern);
    if (!callbacks) {
      callbacks = new Set();
      this.patternCallbacks.set(pattern, callbacks);
    }
    callbacks.add(handler);

    if (this.isFallback || !this.subClient) {
      this.inMemoryEmitter.on(`pattern:${pattern}`, handler);
      return;
    }

    if (callbacks.size === 1) {
      await this.subClient.psubscribe(pattern);
    }
  }

  public async punsubscribe(pattern: string, handler?: (message: string, channel: string) => void): Promise<void> {
    const callbacks = this.patternCallbacks.get(pattern);
    if (!callbacks) return;

    if (handler) {
      callbacks.delete(handler);
      if (this.isFallback || !this.subClient) {
        this.inMemoryEmitter.off(`pattern:${pattern}`, handler);
      }
    } else {
      callbacks.clear();
      if (this.isFallback || !this.subClient) {
        this.inMemoryEmitter.removeAllListeners(`pattern:${pattern}`);
      }
    }

    if (callbacks.size === 0) {
      this.patternCallbacks.delete(pattern);
      if (!this.isFallback && this.subClient && this.subClient.status === 'ready') {
        await this.subClient.punsubscribe(pattern);
      }
    }
  }

  public async geoadd(key: string, longitude: number, latitude: number, member: string): Promise<number> {
    if (this.isFallback || !this.primaryClient) {
      let geoMap = this.inMemoryGeo.get(key);
      if (!geoMap) {
        geoMap = new Map();
        this.inMemoryGeo.set(key, geoMap);
      }
      geoMap.set(member, { longitude, latitude });
      return 1;
    }

    try {
      return await (this.primaryClient as any).geoadd(key, longitude, latitude, member);
    } catch (err: any) {
      if (err.message && (err.message.includes('unknown command') || err.message.includes('ERR'))) {
        let geoMap = this.inMemoryGeo.get(key);
        if (!geoMap) {
          geoMap = new Map();
          this.inMemoryGeo.set(key, geoMap);
        }
        geoMap.set(member, { longitude, latitude });
        return 1;
      }
      throw err;
    }
  }

  public async getInMemoryGeo(key: string, member: string): Promise<{ longitude: number; latitude: number } | null> {
    const geoMap = this.inMemoryGeo.get(key);
    return geoMap?.get(member) || null;
  }

  public async hset(key: string, data: Record<string, any>): Promise<number> {
    if (this.isClosed) return 0;
    if (this.isFallback || !this.primaryClient) {
      let hash = this.inMemoryHashes.get(key);
      if (!hash) {
        hash = new Map();
        this.inMemoryHashes.set(key, hash);
      }
      for (const [k, v] of Object.entries(data)) {
        hash.set(k, String(v));
      }
      return Object.keys(data).length;
    }

    const stringifiedData: Record<string, string> = {};
    for (const [k, v] of Object.entries(data)) {
      stringifiedData[k] = v !== undefined && v !== null ? String(v) : '';
    }
    await this.primaryClient.hmset(key, stringifiedData);
    return Object.keys(data).length;
  }

  public async hgetall(key: string): Promise<Record<string, string>> {
    if (this.isClosed) return {};
    if (this.isFallback || !this.primaryClient) {
      const hash = this.inMemoryHashes.get(key);
      if (!hash) return {};
      const res: Record<string, string> = {};
      for (const [k, v] of hash.entries()) {
        res[k] = v;
      }
      return res;
    }
    return this.primaryClient.hgetall(key);
  }

  public async expire(key: string, seconds: number): Promise<number> {
    if (this.isClosed || this.isFallback || !this.primaryClient) {
      return 1;
    }
    return this.primaryClient.expire(key, seconds);
  }

  public async sadd(key: string, ...members: string[]): Promise<number> {
    if (this.isClosed) return 0;
    if (this.isFallback || !this.primaryClient) {
      let set = this.inMemorySets.get(key);
      if (!set) {
        set = new Set();
        this.inMemorySets.set(key, set);
      }
      let added = 0;
      for (const m of members) {
        if (!set.has(m)) {
          set.add(m);
          added++;
        }
      }
      return added;
    }
    return this.primaryClient.sadd(key, ...members);
  }

  public async srem(key: string, ...members: string[]): Promise<number> {
    if (this.isClosed) return 0;
    if (this.isFallback || !this.primaryClient) {
      const set = this.inMemorySets.get(key);
      if (!set) return 0;
      let removed = 0;
      for (const m of members) {
        if (set.delete(m)) removed++;
      }
      return removed;
    }
    return this.primaryClient.srem(key, ...members);
  }

  public async smembers(key: string): Promise<string[]> {
    if (this.isFallback || !this.primaryClient) {
      const set = this.inMemorySets.get(key);
      return set ? Array.from(set) : [];
    }
    return this.primaryClient.smembers(key);
  }

  public async sismember(key: string, member: string): Promise<number> {
    if (this.isFallback || !this.primaryClient) {
      const set = this.inMemorySets.get(key);
      return set && set.has(member) ? 1 : 0;
    }
    return this.primaryClient.sismember(key, member);
  }

  public async disconnect(): Promise<void> {
    this.isClosed = true;
    this.inMemoryEmitter.removeAllListeners();
    this.subCallbacks.clear();
    this.patternCallbacks.clear();
    this.inMemorySets.clear();
    this.inMemoryHashes.clear();
    this.inMemoryGeo.clear();

    const disconnectPromises: Promise<any>[] = [];
    if (this.primaryClient) {
      disconnectPromises.push(
        this.primaryClient.quit().catch(() => {
          this.primaryClient?.disconnect();
        })
      );
    }
    if (this.pubClient) {
      disconnectPromises.push(
        this.pubClient.quit().catch(() => {
          this.pubClient?.disconnect();
        })
      );
    }
    if (this.subClient) {
      disconnectPromises.push(
        this.subClient.quit().catch(() => {
          this.subClient?.disconnect();
        })
      );
    }
    await Promise.all(disconnectPromises);
    this.primaryClient = null;
    this.pubClient = null;
    this.subClient = null;
  }
}