import { WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { URL } from 'url';
import { TokenService } from '../../../shared/src/services/token.service';
import { db } from '../../../shared/src/database/db';
import { ClientContext } from '../src/types';
import { PresenceTracker } from './presence';
import { ConnectionProvider, HeartbeatReaper } from './heartbeat';

export interface ConnectionManagerOptions {
  heartbeatIntervalMs?: number;
  authTimeoutMs?: number;
}

export type DisconnectHandler = (context: ClientContext) => Promise<void> | void;

export class ConnectionManager implements ConnectionProvider {
  private socketsByUserId = new Map<string, Set<WebSocket>>();
  private contextBySocket = new Map<WebSocket, ClientContext>();
  private pendingAuthTimeouts = new Map<WebSocket, NodeJS.Timeout>();
  private disconnectHandlers = new Set<DisconnectHandler>();
  private reaper: HeartbeatReaper;
  private readonly authTimeoutMs: number;

  constructor(
    private presenceTracker: PresenceTracker,
    options: ConnectionManagerOptions = {}
  ) {
    this.authTimeoutMs = options.authTimeoutMs || 5000;
    this.reaper = new HeartbeatReaper(this, {
      intervalMs: options.heartbeatIntervalMs || 30000,
    });
  }

  public start(): void {
    this.reaper.start();
  }

  public stop(): void {
    this.reaper.stop();
    for (const [_, timer] of this.pendingAuthTimeouts) {
      clearTimeout(timer);
    }
    this.pendingAuthTimeouts.clear();
  }

  public onDisconnect(handler: DisconnectHandler): void {
    this.disconnectHandlers.add(handler);
  }

  public extractTokenFromRequest(req: IncomingMessage): string | null {
    try {
      // 1. Check query parameter ?token=...
      const reqUrl = req.url || '';
      const parsedUrl = new URL(reqUrl, 'http://localhost');
      const tokenQuery = parsedUrl.searchParams.get('token');
      if (tokenQuery) return tokenQuery;

      // 2. Check Authorization header: Bearer <token>
      const authHeader = req.headers['authorization'];
      if (authHeader && authHeader.startsWith('Bearer ')) {
        return authHeader.slice(7).trim();
      }

      // 3. Check Sec-WebSocket-Protocol header
      const subprotocol = req.headers['sec-websocket-protocol'];
      if (subprotocol) {
        const protocols = subprotocol.split(',').map((p) => p.trim());
        const authProtocol = protocols.find((p) => p.startsWith('bearer.'));
        if (authProtocol) {
          return authProtocol.slice(7);
        }
      }
    } catch (err) {
      // Ignore URL parsing errors
    }
    return null;
  }

  public async authenticateToken(token: string): Promise<{ userId: string; phoneE164: string }> {
    const payload = TokenService.verifyAccessToken(token);

    const user = await db.findUserById(payload.userId);
    if (!user) {
      throw new Error('User not found');
    }

    if (!user.isActive) {
      throw new Error('User account is deactivated');
    }

    if (user.passwordChangedAt) {
      const tokenIssuedAt = payload.issuedAtMs || (payload.iat ? payload.iat * 1000 : 0);
      const passwordChangedTime = new Date(user.passwordChangedAt).getTime();
      // Allow 1000ms clock skew window
      if (tokenIssuedAt + 1000 < passwordChangedTime) {
        throw new Error('Token revoked due to subsequent password reset');
      }
    }

    return {
      userId: user.id,
      phoneE164: user.phoneE164,
    };
  }

  public async registerConnection(
    socket: WebSocket,
    userId: string,
    phoneE164: string
  ): Promise<ClientContext> {
    // Clear any pending unauthenticated disconnect timer
    this.clearAuthTimeout(socket);

    const context: ClientContext = {
      socket,
      userId,
      phoneE164,
      isAlive: true,
      lastPingMs: Date.now(),
      authenticatedAt: Date.now(),
      joinedTrips: new Set<string>(),
    };

    this.contextBySocket.set(socket, context);

    let userSockets = this.socketsByUserId.get(userId);
    if (!userSockets) {
      userSockets = new Set();
      this.socketsByUserId.set(userId, userSockets);
    }
    userSockets.add(socket);

    await this.presenceTracker.setUserOnline(userId);

    this.sendSafe(socket, {
      type: 'auth:success',
      userId,
      phoneE164,
      timestamp: Date.now(),
    });

    return context;
  }

  public scheduleUnauthenticatedTimeout(socket: WebSocket): void {
    const timer = setTimeout(() => {
      if (!this.contextBySocket.has(socket)) {
        this.sendSafe(socket, {
          type: 'auth:error',
          code: 'AUTH_TIMEOUT',
          message: 'Authentication timeout: token was not provided within allowed window',
        });
        socket.close(4401, 'Authentication Timeout');
      }
    }, this.authTimeoutMs);

    if (timer.unref) {
      timer.unref();
    }
    this.pendingAuthTimeouts.set(socket, timer);
  }

  private clearAuthTimeout(socket: WebSocket): void {
    const timer = this.pendingAuthTimeouts.get(socket);
    if (timer) {
      clearTimeout(timer);
      this.pendingAuthTimeouts.delete(socket);
    }
  }

  public async handleDisconnect(socket: WebSocket): Promise<void> {
    this.clearAuthTimeout(socket);

    const context = this.contextBySocket.get(socket);
    if (!context) return;

    this.contextBySocket.delete(socket);

    const userSockets = this.socketsByUserId.get(context.userId);
    if (userSockets) {
      userSockets.delete(socket);
      if (userSockets.size === 0) {
        this.socketsByUserId.delete(context.userId);
        await this.presenceTracker.setUserOffline(context.userId);
      }
    }

    // Trigger disconnect handlers (room leave, cleanup)
    for (const handler of this.disconnectHandlers) {
      try {
        await handler(context);
      } catch (err) {
        console.error('[ConnectionManager DisconnectHandler Error]:', err);
      }
    }
  }

  public handleZombieConnection(context: ClientContext): void {
    try {
      context.socket.terminate();
    } catch (err) {
      // Ignored
    }
    this.handleDisconnect(context.socket).catch((err) => {
      console.error('[ConnectionManager Zombie Disconnect Error]:', err);
    });
  }

  public async refreshPresence(userId: string): Promise<void> {
    await this.presenceTracker.refreshUserPresence(userId);
  }

  public handlePong(socket: WebSocket): void {
    const ctx = this.contextBySocket.get(socket);
    if (ctx) {
      this.reaper.handlePong(ctx);
    }
  }

  public getContext(socket: WebSocket): ClientContext | undefined {
    return this.contextBySocket.get(socket);
  }

  public getAllContexts(): IterableIterator<ClientContext> {
    return this.contextBySocket.values();
  }

  public getSocketsForUser(userId: string): WebSocket[] {
    const sockets = this.socketsByUserId.get(userId);
    return sockets ? Array.from(sockets) : [];
  }

  public isUserConnected(userId: string): boolean {
    const sockets = this.socketsByUserId.get(userId);
    return Boolean(sockets && sockets.size > 0);
  }

  public getConnectedUserCount(): number {
    return this.socketsByUserId.size;
  }

  public getTotalSocketCount(): number {
    return this.contextBySocket.size;
  }

  public sendSafe(socket: WebSocket, message: any): boolean {
    if (socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    try {
      socket.send(typeof message === 'string' ? message : JSON.stringify(message));
      return true;
    } catch (err) {
      console.error('[ConnectionManager sendSafe Error]:', err);
      return false;
    }
  }

  public sendToUser(userId: string, message: any): number {
    const sockets = this.socketsByUserId.get(userId);
    if (!sockets) return 0;

    let sent = 0;
    for (const s of sockets) {
      if (this.sendSafe(s, message)) {
        sent++;
      }
    }
    return sent;
  }

  public broadcastToAll(message: any): number {
    let sent = 0;
    for (const ctx of this.contextBySocket.values()) {
      if (this.sendSafe(ctx.socket, message)) {
        sent++;
      }
    }
    return sent;
  }

  public async closeAll(code: number = 1001, reason: string = 'Server Going Away'): Promise<void> {
    this.stop();

    const sockets = Array.from(this.contextBySocket.keys());
    for (const socket of sockets) {
      try {
        socket.close(code, reason);
      } catch (err) {
        // Ignored
      }
    }

    // Await all disconnect cleanup
    for (const socket of sockets) {
      await this.handleDisconnect(socket);
    }
  }
}

