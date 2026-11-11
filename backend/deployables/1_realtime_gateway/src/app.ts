import Fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { Socket } from 'net';
import { db } from '../../../shared/src/database/db';
import { config } from '../../../shared/src/config/env';
import { RedisClientManager, RedisManagerOptions } from '../pubsub/redis_client_manager';
import { PresenceTracker } from '../connections/presence';
import { ConnectionManager, ConnectionManagerOptions } from '../connections/connection_manager';
import { RoomManager } from '../pubsub/room_manager';
import { AlertRouter } from '../pubsub/alert_router';
import { TelemetryDownsampler, DownsamplerOptions } from '../ingest/downsampler';
import { WriteBehindQueue, WriteBehindQueueOptions } from '../ingest/write_behind_queue';
import { TelemetryIngestor } from '../ingest/telemetry_ingestor';
import {
  JoinTripSchema,
  LeaveTripSchema,
  EmergencyBroadcastSchema,
  TeaBreakSchema,
} from '../ingest/telemetry.schemas';
import { GatewayStats } from './types';

export interface GatewayAppOptions {
  redis?: RedisManagerOptions;
  connection?: ConnectionManagerOptions;
  downsampler?: DownsamplerOptions;
  queue?: WriteBehindQueueOptions;
}

export class RealtimeGatewayApp {
  public fastify: FastifyInstance;
  public wss: WebSocketServer;
  public redisManager: RedisClientManager;
  public presenceTracker: PresenceTracker;
  public connectionManager: ConnectionManager;
  public roomManager: RoomManager;
  public alertRouter: AlertRouter;
  public downsampler: TelemetryDownsampler;
  public writeBehindQueue: WriteBehindQueue;
  public telemetryIngestor: TelemetryIngestor;

  private isRunning = false;

  constructor(options: GatewayAppOptions = {}) {
    // 1. Initialize Fastify HTTP server
    this.fastify = Fastify({
      logger: false,
      trustProxy: true,
    });

    // 2. Initialize Redis Client Manager & Presence Tracker
    this.redisManager = new RedisClientManager(options.redis);
    this.presenceTracker = new PresenceTracker(this.redisManager);

    // 3. Initialize WebSocket Connection Manager
    this.connectionManager = new ConnectionManager(
      this.presenceTracker,
      options.connection
    );

    // 4. Initialize Group Convoy Room Manager & Alert Router
    this.roomManager = new RoomManager(this.redisManager);
    this.alertRouter = new AlertRouter(this.redisManager, this.roomManager);

    // 5. Initialize Ingest Pipeline: Downsampler, Queue, and Ingestor
    this.downsampler = new TelemetryDownsampler(options.downsampler);
    this.writeBehindQueue = new WriteBehindQueue(options.queue);
    this.telemetryIngestor = new TelemetryIngestor(
      this.redisManager,
      this.roomManager,
      this.downsampler,
      this.writeBehindQueue
    );

    // 6. Initialize WebSocket Server in manual upgrade mode
    this.wss = new WebSocketServer({ noServer: true });

    this.setupRoutes();
    this.setupWebSocketUpgrade();
    this.setupLifecycleHooks();
  }

  private setupRoutes(): void {
    this.fastify.register(cors, {
      origin: true,
      credentials: true,
    });

    this.fastify.get('/health', async () => {
      const stats: GatewayStats = {
        activeConnections: this.connectionManager.getTotalSocketCount(),
        activeUsers: this.connectionManager.getConnectedUserCount(),
        activeTrips: this.roomManager.getActiveTripsCount(),
        queueLength: this.writeBehindQueue.getQueueLength(),
        redisStatus: this.redisManager.getStatus(),
      };

      return {
        status: 'ok',
        service: 'rootu-realtime-gateway',
        timestamp: new Date().toISOString(),
        stats,
      };
    });
  }

  private setupWebSocketUpgrade(): void {
    const rawServer = this.fastify.server;

    rawServer.on('upgrade', async (req: IncomingMessage, socket: Socket, head: Buffer) => {
      const url = req.url || '';
      if (!url.startsWith('/ws')) {
        if (socket.writable) {
          socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
        }
        socket.destroy();
        return;
      }

      // Check if token was provided in handshake
      const token = this.connectionManager.extractTokenFromRequest(req);

      if (token) {
        try {
          const authUser = await this.connectionManager.authenticateToken(token);

          this.wss.handleUpgrade(req, socket, head, (ws) => {
            // Bind socket events synchronously to guarantee error/close handlers are immediately active
            this.bindSocketEvents(ws);
            this.connectionManager
              .registerConnection(ws, authUser.userId, authUser.phoneE164)
              .catch((err) => {
                console.error('[RealtimeGateway Handshake Register Error]:', err.message);
                ws.close(1011, 'Internal Error');
              });
          });
          return;
        } catch (err: any) {
          if (socket.writable) {
            socket.write(
              `HTTP/1.1 401 Unauthorized\r\nContent-Type: text/plain\r\n\r\n${err.message}`
            );
          }
          socket.destroy();
          return;
        }
      }

      // Allow upgrade for deferred in-socket auth message
      this.wss.handleUpgrade(req, socket, head, (ws) => {
        this.bindSocketEvents(ws);
        this.connectionManager.scheduleUnauthenticatedTimeout(ws);
      });
    });
  }

  private bindSocketEvents(socket: WebSocket): void {
    socket.on('message', async (data: any) => {
      try {
        await this.handleClientMessage(socket, data);
      } catch (err: any) {
        console.error('[RealtimeGateway Message Handler Unhandled Error]:', err.message);
        this.connectionManager.sendSafe(socket, {
          type: 'error',
          code: 'INTERNAL_SERVER_ERROR',
          message: 'An internal error occurred while processing message',
        });
      }
    });

    socket.on('pong', () => {
      this.connectionManager.handlePong(socket);
    });

    socket.on('close', async () => {
      await this.connectionManager.handleDisconnect(socket);
    });

    socket.on('error', async (err) => {
      console.error('[RealtimeGateway Socket Error]:', err.message);
      await this.connectionManager.handleDisconnect(socket);
    });
  }

  private async handleClientMessage(socket: WebSocket, raw: any): Promise<void> {
    let message: any;
    try {
      const text = typeof raw === 'string' ? raw : raw.toString('utf8');
      message = JSON.parse(text);
    } catch (err) {
      this.connectionManager.sendSafe(socket, {
        type: 'error',
        code: 'INVALID_JSON',
        message: 'Message must be valid JSON string',
      });
      return;
    }

    if (!message || typeof message.type !== 'string') {
      this.connectionManager.sendSafe(socket, {
        type: 'error',
        code: 'INVALID_MESSAGE_FORMAT',
        message: 'Message must have a valid "type" field',
      });
      return;
    }

    // Handle deferred in-socket authentication
    if (message.type === 'auth') {
      const existingContext = this.connectionManager.getContext(socket);
      if (existingContext) {
        this.connectionManager.sendSafe(socket, {
          type: 'auth:error',
          code: 'ALREADY_AUTHENTICATED',
          message: 'Connection is already authenticated',
        });
        return;
      }

      if (!message.token || typeof message.token !== 'string') {
        this.connectionManager.sendSafe(socket, {
          type: 'auth:error',
          code: 'INVALID_TOKEN',
          message: 'Auth message must include a valid JWT token string',
        });
        return;
      }

      try {
        const authUser = await this.connectionManager.authenticateToken(message.token);
        await this.connectionManager.registerConnection(
          socket,
          authUser.userId,
          authUser.phoneE164
        );
      } catch (err: any) {
        this.connectionManager.sendSafe(socket, {
          type: 'auth:error',
          code: 'UNAUTHORIZED',
          message: err.message,
        });
        socket.close(4401, 'Unauthorized');
      }
      return;
    }

    // Enforce authentication boundary: all subsequent message types require valid auth context
    const context = this.connectionManager.getContext(socket);
    if (!context) {
      this.connectionManager.sendSafe(socket, {
        type: 'auth:error',
        code: 'UNAUTHENTICATED',
        message: 'You must authenticate before sending messages',
      });
      return;
    }

    switch (message.type) {
      case 'ping': {
        this.connectionManager.handlePong(socket);
        this.connectionManager.sendSafe(socket, {
          type: 'pong',
          timestamp: Date.now(),
        });
        break;
      }

      case 'pong': {
        this.connectionManager.handlePong(socket);
        break;
      }

      case 'telemetry': {
        const result = await this.telemetryIngestor.ingest(message.data, context);
        if (!result.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'telemetry:rejected',
            code: result.code,
            error: result.error,
          });
        } else {
          this.connectionManager.sendSafe(socket, {
            type: 'telemetry:ack',
            timestamp: message.data?.timestamp || Date.now(),
            persisted: result.persisted,
          });
        }
        break;
      }

      case 'trip:join': {
        const parse = JoinTripSchema.safeParse(message);
        if (!parse.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'VALIDATION_ERROR',
            message: parse.error.issues[0].message,
          });
          return;
        }

        const res = await this.roomManager.joinTrip(parse.data.tripId, context);
        if (!res.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'trip:join_error',
            tripId: parse.data.tripId,
            error: res.error,
          });
          return;
        }

        await this.alertRouter.subscribeTripAlerts(parse.data.tripId);

        this.connectionManager.sendSafe(socket, {
          type: 'trip:joined',
          tripId: parse.data.tripId,
          activeRiders: res.activeRiders,
        });
        break;
      }

      case 'trip:leave': {
        const parse = LeaveTripSchema.safeParse(message);
        if (!parse.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'VALIDATION_ERROR',
            message: parse.error.issues[0].message,
          });
          return;
        }

        await this.roomManager.leaveTrip(parse.data.tripId, context);
        this.connectionManager.sendSafe(socket, {
          type: 'trip:left',
          tripId: parse.data.tripId,
        });
        break;
      }

      case 'emergency:broadcast': {
        const parse = EmergencyBroadcastSchema.safeParse(message);
        if (!parse.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'VALIDATION_ERROR',
            message: parse.error.issues[0].message,
          });
          return;
        }

        const isMember =
          context.joinedTrips.has(parse.data.tripId) ||
          (await db.isTripMember(parse.data.tripId, context.userId));
        if (!isMember) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'FORBIDDEN',
            message: 'You are not an authorized member of this trip convoy',
          });
          return;
        }

        await this.alertRouter.routeEmergency({
          tripId: parse.data.tripId,
          userId: context.userId,
          alertType: parse.data.alertType,
          details: parse.data.details,
          location: parse.data.location,
          timestamp: Date.now(),
        });

        this.connectionManager.sendSafe(socket, {
          type: 'emergency:ack',
          tripId: parse.data.tripId,
        });
        break;
      }

      case 'convoy:tea_break': {
        const parse = TeaBreakSchema.safeParse(message);
        if (!parse.success) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'VALIDATION_ERROR',
            message: parse.error.issues[0].message,
          });
          return;
        }

        const isMember =
          context.joinedTrips.has(parse.data.tripId) ||
          (await db.isTripMember(parse.data.tripId, context.userId));
        if (!isMember) {
          this.connectionManager.sendSafe(socket, {
            type: 'error',
            code: 'FORBIDDEN',
            message: 'You are not an authorized member of this trip convoy',
          });
          return;
        }

        await this.alertRouter.routeTeaBreak({
          tripId: parse.data.tripId,
          userId: context.userId,
          action: parse.data.action,
          proposedLocation: parse.data.proposedLocation,
          timestamp: Date.now(),
        });

        this.connectionManager.sendSafe(socket, {
          type: 'convoy:tea_break_ack',
          tripId: parse.data.tripId,
        });
        break;
      }

      default: {
        this.connectionManager.sendSafe(socket, {
          type: 'error',
          code: 'UNKNOWN_MESSAGE_TYPE',
          message: `Unrecognized message type: ${message.type}`,
        });
        break;
      }
    }
  }

  private setupLifecycleHooks(): void {
    // Unsubscribe Redis alert channels when all local sockets leave a trip room
    this.roomManager.onRoomEmpty(async (tripId) => {
      await this.alertRouter.unsubscribeTripAlerts(tripId);
    });

    // When a connection disconnects, leave all active convoy rooms and clear downsampler caches if user has no remaining sockets
    this.connectionManager.onDisconnect(async (context) => {
      await this.roomManager.leaveAllTrips(context.socket, context);
      if (!this.connectionManager.isUserConnected(context.userId)) {
        this.telemetryIngestor.cleanupUser(context.userId);
      }
    });
  }

  public async start(port?: number, host?: string): Promise<string> {
    if (this.isRunning) {
      return `http://${host || config.host}:${port || config.gatewayPort}`;
    }

    // 1. Initialize Redis Client Manager
    await this.redisManager.initialize();

    // 2. Start Write-Behind Queue flush loop
    this.writeBehindQueue.start();

    // 3. Start Connection Manager heartbeat reaper
    this.connectionManager.start();

    // 4. Start Fastify listening on designated port
    const listenPort = port !== undefined ? port : config.gatewayPort;
    const listenHost = host || config.host;

    const address = await this.fastify.listen({
      port: listenPort,
      host: listenHost,
    });

    this.isRunning = true;
    return address;
  }

  public async stop(): Promise<void> {
    if (!this.isRunning) return;
    this.isRunning = false;

    // 1. Close all active WebSockets gracefully
    await this.connectionManager.closeAll(1001, 'Gateway Shutting Down');

    // 2. Flush write-behind queue to DB completely
    await this.writeBehindQueue.flushAndStop();

    // 3. Stop Fastify HTTP server
    await this.fastify.close();

    // 4. Disconnect Redis clients
    await this.redisManager.disconnect();
  }
}

