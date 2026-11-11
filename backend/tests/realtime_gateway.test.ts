process.env.NODE_ENV = 'test';
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert';
import { WebSocket } from 'ws';
import { RealtimeGatewayApp } from '../deployables/1_realtime_gateway/src/app';
import { db } from '../shared/src/database/db';
import { TokenService } from '../shared/src/services/token.service';
import { SanityChecker } from '../deployables/1_realtime_gateway/ingest/sanity_checker';
import { TelemetryDownsampler } from '../deployables/1_realtime_gateway/ingest/downsampler';
import { WriteBehindQueue } from '../deployables/1_realtime_gateway/ingest/write_behind_queue';

class TestWsClient {
  public ws: WebSocket;
  private messageQueue: any[] = [];
  private waiters: Array<{ expectedType?: string; resolve: (msg: any) => void }> = [];

  constructor(ws: WebSocket) {
    this.ws = ws;
    this.ws.on('message', (data: any) => {
      try {
        const text = typeof data === 'string' ? data : data.toString('utf8');
        const parsed = JSON.parse(text);

        const waiterIdx = this.waiters.findIndex(
          (w) => !w.expectedType || w.expectedType === parsed.type
        );
        if (waiterIdx >= 0) {
          const waiter = this.waiters.splice(waiterIdx, 1)[0];
          waiter.resolve(parsed);
        } else {
          this.messageQueue.push(parsed);
        }
      } catch (err) {
        // Ignore non-json frames
      }
    });
  }

  public waitFor(expectedTypeOrTimeout?: string | number, timeoutMs: number = 4000): Promise<any> {
    const expectedType = typeof expectedTypeOrTimeout === 'string' ? expectedTypeOrTimeout : undefined;
    const timeout = typeof expectedTypeOrTimeout === 'number' ? expectedTypeOrTimeout : timeoutMs;

    if (expectedType) {
      const idx = this.messageQueue.findIndex((m) => m.type === expectedType);
      if (idx >= 0) {
        return Promise.resolve(this.messageQueue.splice(idx, 1)[0]);
      }
    } else if (this.messageQueue.length > 0) {
      return Promise.resolve(this.messageQueue.shift());
    }

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(
          new Error(
            `waitForMessage${expectedType ? `('${expectedType}')` : ''} timed out after ${timeout}ms. Buffered: ${JSON.stringify(
              this.messageQueue.map((m) => m.type)
            )}`
          )
        );
      }, timeout);

      this.waiters.push({
        expectedType,
        resolve: (msg) => {
          clearTimeout(timer);
          resolve(msg);
        },
      });
    });
  }

  public send(data: any): void {
    this.ws.send(typeof data === 'string' ? data : JSON.stringify(data));
  }

  public close(): void {
    this.ws.close();
  }

  public on(event: string, handler: any): void {
    this.ws.on(event, handler);
  }

  public get readyState(): number {
    return this.ws.readyState;
  }
}

function createWsClient(url: string): Promise<TestWsClient> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error(`WebSocket connection timeout to ${url}`));
    }, 4000);

    ws.on('open', () => {
      clearTimeout(timer);
      resolve(new TestWsClient(ws));
    });

    ws.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

function waitForMessage(
  client: TestWsClient | WebSocket,
  expectedTypeOrTimeout?: string | number,
  timeoutMs: number = 4000
): Promise<any> {
  if (client instanceof TestWsClient) {
    return client.waitFor(expectedTypeOrTimeout, timeoutMs);
  }

  const expectedType = typeof expectedTypeOrTimeout === 'string' ? expectedTypeOrTimeout : undefined;
  const timeout = typeof expectedTypeOrTimeout === 'number' ? expectedTypeOrTimeout : timeoutMs;

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`waitForMessage${expectedType ? `('${expectedType}')` : ''} timed out after ${timeout}ms`));
    }, timeout);

    const onMessage = (data: any) => {
      try {
        const text = typeof data === 'string' ? data : data.toString('utf8');
        const parsed = JSON.parse(text);
        if (!expectedType || parsed.type === expectedType) {
          clearTimeout(timer);
          (client as WebSocket).off('message', onMessage);
          resolve(parsed);
        }
      } catch (err) {
        // Ignore
      }
    };

    (client as WebSocket).on('message', onMessage);
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe('RootU Realtime Gateway Microservice Production Test Suite', () => {
  let app: RealtimeGatewayApp;
  let serverBaseUrl: string;
  let wsBaseUrl: string;
  const testPort = 3105;

  let testUser1: any;
  let testUser2: any;
  let tokenUser1: string;
  let tokenUser2: string;
  let testTrip: any;

  before(async () => {
    app = new RealtimeGatewayApp({
      connection: {
        authTimeoutMs: 1500,
        heartbeatIntervalMs: 500,
      },
      queue: {
        flushIntervalMs: 200,
        batchSize: 10,
      },
      downsampler: {
        minIntervalMs: 2000,
        minDistanceMeters: 20,
      },
    });

    const address = await app.start(testPort, '127.0.0.1');
    serverBaseUrl = `http://127.0.0.1:${testPort}`;
    wsBaseUrl = `ws://127.0.0.1:${testPort}/ws`;
  });

  beforeEach(async () => {
    app.writeBehindQueue.clear();
    app.downsampler.clearAll();
    await db.clearAll();

    testUser1 = await db.createUser({
      phoneE164: '+919900000001',
      fullName: 'Rider One',
      passwordHash: 'hashed_password_1',
      termsAcceptedAt: new Date(),
    });

    testUser2 = await db.createUser({
      phoneE164: '+919900000002',
      fullName: 'Rider Two',
      passwordHash: 'hashed_password_2',
      termsAcceptedAt: new Date(),
    });

    tokenUser1 = TokenService.signAccessToken(testUser1.id, testUser1.phoneE164);
    tokenUser2 = TokenService.signAccessToken(testUser2.id, testUser2.phoneE164);

    testTrip = await db.createTrip({
      title: 'Himalayan Convoy 2026',
      joinCode: 'HIM26',
      creatorId: testUser1.id,
    });
    await db.addTripMember(testTrip.id, testUser2.id, 'RIDER');
  });

  after(async () => {
    await app.stop();
  });

  // =========================================================================
  // 1. HEALTH CHECK & STATS
  // =========================================================================
  it('GW-01: Health check endpoint reports status and gateway metrics', async () => {
    const res = await app.fastify.inject({
      method: 'GET',
      url: '/health',
    });

    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.strictEqual(body.status, 'ok');
    assert.strictEqual(body.service, 'rootu-realtime-gateway');
    assert.ok(body.stats);
    assert.strictEqual(typeof body.stats.activeConnections, 'number');
    assert.strictEqual(typeof body.stats.activeUsers, 'number');
  });

  // =========================================================================
  // 2. JWT HANDSHAKE AUTHENTICATION
  // =========================================================================
  it('GW-02: Rejects handshake upgrade when token is invalid or expired', async () => {
    await assert.rejects(
      () => createWsClient(`${wsBaseUrl}?token=invalid.jwt.token.signature`),
      (err: any) => {
        assert.ok(err.message.includes('401') || err.message.includes('Unexpected server response'));
        return true;
      }
    );
  });

  it('GW-03: Successfully connects and authenticates via query param token in handshake', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    const msg = await waitForMessage(ws);

    assert.strictEqual(msg.type, 'auth:success');
    assert.strictEqual(msg.userId, testUser1.id);
    assert.strictEqual(msg.phoneE164, testUser1.phoneE164);

    const isOnline = await app.presenceTracker.isUserOnline(testUser1.id);
    assert.strictEqual(isOnline, true);

    ws.close();
    await sleep(100);
  });

  it('GW-04: Rejects handshake for deactivated user account', async () => {
    await db.setUserActive(testUser1.id, false);

    await assert.rejects(
      () => createWsClient(`${wsBaseUrl}?token=${tokenUser1}`),
      (err: any) => {
        assert.ok(err.message.includes('401') || err.message.includes('Unexpected server response'));
        return true;
      }
    );
  });

  // =========================================================================
  // 3. IN-SOCKET DEFERRED AUTHENTICATION & TIMEOUT
  // =========================================================================
  it('GW-05: Authenticates in-socket with auth message when no handshake token is supplied', async () => {
    const ws = await createWsClient(wsBaseUrl);

    // Send auth payload
    ws.send(JSON.stringify({ type: 'auth', token: tokenUser2 }));
    const msg = await waitForMessage(ws);

    assert.strictEqual(msg.type, 'auth:success');
    assert.strictEqual(msg.userId, testUser2.id);

    ws.close();
    await sleep(100);
  });

  it('GW-06: Disconnects unauthenticated client if auth timeout expires', async () => {
    const ws = await createWsClient(wsBaseUrl);

    const msg = await waitForMessage(ws, 3000);
    assert.strictEqual(msg.type, 'auth:error');
    assert.strictEqual(msg.code, 'AUTH_TIMEOUT');

    // Socket should close
    await new Promise<void>((resolve) => {
      if (ws.readyState === WebSocket.CLOSED) resolve();
      else ws.on('close', () => resolve());
    });
  });

  it('GW-07: Rejects non-auth messages when connection is unauthenticated', async () => {
    const ws = await createWsClient(wsBaseUrl);

    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9716,
          longitude: 77.5946,
          speed: 40,
          heading: 90,
          altitude: 900,
          accuracy: 5,
          timestamp: Date.now(),
        },
      })
    );

    const msg = await waitForMessage(ws);
    assert.strictEqual(msg.type, 'auth:error');
    assert.strictEqual(msg.code, 'UNAUTHENTICATED');

    ws.close();
    await sleep(100);
  });

  // =========================================================================
  // 4. HEARTBEAT & PING-PONG REAPER
  // =========================================================================
  it('GW-08: Responds to ping message with pong and refreshes liveness', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws); // consume auth:success

    ws.send(JSON.stringify({ type: 'ping' }));
    const msg = await waitForMessage(ws);

    assert.strictEqual(msg.type, 'pong');
    assert.strictEqual(typeof msg.timestamp, 'number');

    ws.close();
    await sleep(100);
  });

  // =========================================================================
  // 5. GPS TELEMETRY SANITY & SPOOFING BOUNDARY CHECKS
  // =========================================================================
  it('GW-09: Rejects Null Island GPS coordinates (0, 0)', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 0,
          longitude: 0,
          speed: 45,
          heading: 180,
          altitude: 50,
          accuracy: 10,
          timestamp: Date.now(),
        },
      })
    );

    const msg = await waitForMessage(ws);
    assert.strictEqual(msg.type, 'telemetry:rejected');
    assert.strictEqual(msg.code, 'NULL_ISLAND_COORDINATES');

    ws.close();
    await sleep(100);
  });

  it('GW-10: Rejects out-of-range geodetic latitude (> 90 degrees)', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 95.5,
          longitude: 77.5946,
          speed: 30,
          heading: 0,
          altitude: 100,
          accuracy: 5,
          timestamp: Date.now(),
        },
      })
    );

    const msg = await waitForMessage(ws);
    assert.strictEqual(msg.type, 'telemetry:rejected');
    assert.strictEqual(msg.code, 'SCHEMA_VALIDATION_ERROR');

    ws.close();
    await sleep(100);
  });

  it('GW-11: Rejects future timestamp beyond acceptable clock drift', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9716,
          longitude: 77.5946,
          speed: 30,
          heading: 0,
          altitude: 100,
          accuracy: 5,
          timestamp: Date.now() + 10 * 60 * 1000, // 10 minutes in future
        },
      })
    );

    const msg = await waitForMessage(ws);
    assert.strictEqual(msg.type, 'telemetry:rejected');
    assert.strictEqual(msg.code, 'FUTURE_TIMESTAMP');

    ws.close();
    await sleep(100);
  });

  it('GW-12: Rejects impossible land vehicle speed (> 350 km/h)', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9716,
          longitude: 77.5946,
          speed: 450,
          heading: 0,
          altitude: 100,
          accuracy: 5,
          timestamp: Date.now(),
        },
      })
    );

    const msg = await waitForMessage(ws);
    assert.strictEqual(msg.type, 'telemetry:rejected');
    assert.strictEqual(msg.code, 'SCHEMA_VALIDATION_ERROR');

    ws.close();
    await sleep(100);
  });

  it('GW-13: Rejects teleportation / spoofing jump between consecutive GPS fixes', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    const now = Date.now();
    // 1. Initial valid fix in Bangalore
    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9716,
          longitude: 77.5946,
          speed: 40,
          heading: 0,
          altitude: 900,
          accuracy: 5,
          timestamp: now,
        },
      })
    );
    const ack1 = await waitForMessage(ws);
    assert.strictEqual(ack1.type, 'telemetry:ack');

    // 2. Second fix 2 seconds later in Delhi (2000 km away!)
    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 28.7041,
          longitude: 77.1025,
          speed: 50,
          heading: 0,
          altitude: 200,
          accuracy: 5,
          timestamp: now + 2000,
        },
      })
    );
    const ack2 = await waitForMessage(ws);
    assert.strictEqual(ack2.type, 'telemetry:rejected');
    assert.strictEqual(ack2.code, 'TELEPORTATION_SPOOF_DETECTED');

    ws.close();
    await sleep(100);
  });

  // =========================================================================
  // 6. REDIS GEOADD & EPHEMERAL SNAPSHOT
  // =========================================================================
  it('GW-14: Indexes valid telemetry with Redis GEOADD and ephemeral snapshot cache', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    const now = Date.now();
    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 13.0827,
          longitude: 80.2707,
          speed: 55,
          heading: 120,
          altitude: 15,
          accuracy: 8,
          timestamp: now,
          tripId: testTrip.id,
        },
      })
    );

    const ack = await waitForMessage(ws);
    assert.strictEqual(ack.type, 'telemetry:ack');

    // Verify snapshot in Redis
    const snapshot = await app.redisManager.hgetall(`rider:pos:${testUser1.id}`);
    assert.strictEqual(snapshot.latitude, '13.0827');
    assert.strictEqual(snapshot.longitude, '80.2707');
    assert.strictEqual(snapshot.speed, '55');
    assert.strictEqual(snapshot.tripId, testTrip.id);

    ws.close();
    await sleep(100);
  });

  // =========================================================================
  // 7. WRITE-BEHIND BATCHING QUEUE PERSISTENCE INTO POSTGRESQL
  // =========================================================================
  it('GW-15: Write-Behind Queue persists downsampled breadcrumbs into PostgreSQL breadcrumbs table', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws);

    const now = Date.now();
    // Send 3 points with displacement
    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9716,
          longitude: 77.5946,
          speed: 35,
          heading: 45,
          altitude: 900,
          accuracy: 5,
          timestamp: now,
        },
      })
    );
    await waitForMessage(ws);

    // Second point with large displacement > 100m
    ws.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9728,
          longitude: 77.5958,
          speed: 40,
          heading: 45,
          altitude: 905,
          accuracy: 5,
          timestamp: now + 3000,
        },
      })
    );
    await waitForMessage(ws);

    // Flush write-behind queue to DB
    await app.writeBehindQueue.flush();

    // Verify persisted records in database
    const breadcrumbs = await db.getRecentBreadcrumbs(testUser1.id, 10);
    assert.ok(breadcrumbs.length >= 1, `Expected at least 1 breadcrumb, found ${breadcrumbs.length}`);
    assert.strictEqual(breadcrumbs[0].userId, testUser1.id);

    ws.close();
    await sleep(100);
  });

  // =========================================================================
  // =========================================================================
  // 8. GROUP CONVOY / TRIP ROOMS & REDIS PUBSUB FAN-OUT
  // =========================================================================
  it('GW-16: Fans out live rider GPS telemetry across convoy room members via Redis Pub/Sub', async () => {
    // Connect Rider 1 and Rider 2
    const ws1 = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws1, 'auth:success');

    const ws2 = await createWsClient(`${wsBaseUrl}?token=${tokenUser2}`);
    await waitForMessage(ws2, 'auth:success');

    // Both join the trip room
    ws1.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    const joinRes1 = await waitForMessage(ws1, 'trip:joined');
    assert.strictEqual(joinRes1.type, 'trip:joined');

    ws2.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    const joinRes2 = await waitForMessage(ws2, 'trip:joined');
    assert.strictEqual(joinRes2.type, 'trip:joined');

    // Rider 1 sends telemetry with tripId
    const now = Date.now();
    ws1.send(
      JSON.stringify({
        type: 'telemetry',
        data: {
          latitude: 12.9352,
          longitude: 77.6245,
          speed: 60,
          heading: 180,
          altitude: 880,
          accuracy: 4,
          timestamp: now,
          tripId: testTrip.id,
        },
      })
    );

    // Rider 1 receives ack
    const ack1 = await waitForMessage(ws1, 'telemetry:ack');
    assert.strictEqual(ack1.type, 'telemetry:ack');

    // Rider 2 should receive the fan-out broadcast via Pub/Sub!
    const broadcastMsg = await waitForMessage(ws2, 'telemetry:broadcast');
    assert.strictEqual(broadcastMsg.type, 'telemetry:broadcast');
    assert.strictEqual(broadcastMsg.tripId, testTrip.id);
    assert.strictEqual(broadcastMsg.userId, testUser1.id);
    assert.strictEqual(broadcastMsg.data.latitude, 12.9352);
    assert.strictEqual(broadcastMsg.data.longitude, 77.6245);

    ws1.close();
    ws2.close();
    await sleep(100);
  });

  // =========================================================================
  // 9. EMERGENCY BROADCAST & TEA-BREAK ALERTS
  // =========================================================================
  it('GW-17: Routes emergency SOS alert to all convoy members with high priority', async () => {
    const ws1 = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws1, 'auth:success');
    const ws2 = await createWsClient(`${wsBaseUrl}?token=${tokenUser2}`);
    await waitForMessage(ws2, 'auth:success');

    ws1.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    await waitForMessage(ws1, 'trip:joined');
    ws2.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    await waitForMessage(ws2, 'trip:joined');

    // Rider 2 triggers SOS alert
    ws2.send(
      JSON.stringify({
        type: 'emergency:broadcast',
        tripId: testTrip.id,
        alertType: 'SOS',
        details: 'Flat tire on highway milestone 42',
        location: {
          latitude: 12.9352,
          longitude: 77.6245,
        },
      })
    );

    // Rider 2 gets ack
    const ack = await waitForMessage(ws2, 'emergency:ack');
    assert.strictEqual(ack.type, 'emergency:ack');

    // Rider 1 receives the emergency alert
    const emergencyMsg = await waitForMessage(ws1, 'emergency:alert');
    assert.strictEqual(emergencyMsg.type, 'emergency:alert');
    assert.strictEqual(emergencyMsg.tripId, testTrip.id);
    assert.strictEqual(emergencyMsg.userId, testUser2.id);
    assert.strictEqual(emergencyMsg.alertType, 'SOS');
    assert.strictEqual(emergencyMsg.details, 'Flat tire on highway milestone 42');

    ws1.close();
    ws2.close();
    await sleep(100);
  });

  it('GW-18: Routes convoy tea-break alert across active riders', async () => {
    const ws1 = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws1, 'auth:success');
    const ws2 = await createWsClient(`${wsBaseUrl}?token=${tokenUser2}`);
    await waitForMessage(ws2, 'auth:success');

    ws1.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    await waitForMessage(ws1, 'trip:joined');
    ws2.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    await waitForMessage(ws2, 'trip:joined');

    // Rider 1 proposes tea break
    ws1.send(
      JSON.stringify({
        type: 'convoy:tea_break',
        tripId: testTrip.id,
        action: 'PROPOSED',
        proposedLocation: {
          latitude: 12.95,
          longitude: 77.65,
          name: 'Chai Point KM 54',
        },
      })
    );

    const ack = await waitForMessage(ws1, 'convoy:tea_break_ack');
    assert.strictEqual(ack.type, 'convoy:tea_break_ack');

    // Rider 2 receives the tea-break alert
    const alertMsg = await waitForMessage(ws2, 'convoy:tea_break_alert');
    assert.strictEqual(alertMsg.type, 'convoy:tea_break_alert');
    assert.strictEqual(alertMsg.tripId, testTrip.id);
    assert.strictEqual(alertMsg.userId, testUser1.id);
    assert.strictEqual(alertMsg.action, 'PROPOSED');
    assert.strictEqual(alertMsg.proposedLocation?.name, 'Chai Point KM 54');

    ws1.close();
    ws2.close();
    await sleep(100);
  });

  // =========================================================================
  // 10. GRACEFUL DISCONNECT & RESOURCE CLEANUP
  // =========================================================================
  it('GW-19: Cleans up rooms, presence, and downsampler state when rider disconnects', async () => {
    const ws = await createWsClient(`${wsBaseUrl}?token=${tokenUser1}`);
    await waitForMessage(ws, 'auth:success');

    ws.send(JSON.stringify({ type: 'trip:join', tripId: testTrip.id }));
    await waitForMessage(ws, 'trip:joined');

    assert.strictEqual(await app.presenceTracker.isUserOnline(testUser1.id), true);
    assert.strictEqual(app.roomManager.getRoomSocketCount(testTrip.id), 1);

    // Disconnect
    ws.close();
    await sleep(200);

    assert.strictEqual(await app.presenceTracker.isUserOnline(testUser1.id), false);
    assert.strictEqual(app.roomManager.getRoomSocketCount(testTrip.id), 0);
  });
});