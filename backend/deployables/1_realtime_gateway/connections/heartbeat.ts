import { WebSocket } from 'ws';
import { ClientContext } from '../src/types';

export interface HeartbeatOptions {
  intervalMs?: number;
}

export interface ConnectionProvider {
  getAllContexts(): IterableIterator<ClientContext>;
  handleZombieConnection(context: ClientContext): void;
  refreshPresence?(userId: string): Promise<void> | void;
}

export class HeartbeatReaper {
  private timer: NodeJS.Timeout | null = null;
  private readonly intervalMs: number;

  constructor(
    private provider: ConnectionProvider,
    options: HeartbeatOptions = {}
  ) {
    this.intervalMs = options.intervalMs || 30000;
  }

  public start(): void {
    if (this.timer) return;

    this.timer = setInterval(() => {
      this.reapStaleConnections();
    }, this.intervalMs);

    if (this.timer.unref) {
      this.timer.unref();
    }
  }

  public reapStaleConnections(): void {
    const contexts = this.provider.getAllContexts();

    for (const ctx of contexts) {
      if (!ctx.isAlive) {
        // Socket failed to respond to previous ping in time -> zombie reaper
        this.provider.handleZombieConnection(ctx);
        continue;
      }

      // Mark unalive pending client pong response
      ctx.isAlive = false;

      if (ctx.socket.readyState === WebSocket.OPEN) {
        try {
          ctx.socket.ping();
          ctx.socket.send(JSON.stringify({ type: 'ping' }));
        } catch (err) {
          this.provider.handleZombieConnection(ctx);
        }
      }
    }
  }

  public handlePong(context: ClientContext): void {
    context.isAlive = true;
    context.lastPingMs = Date.now();
    if (this.provider.refreshPresence) {
      this.provider.refreshPresence(context.userId);
    }
  }

  public stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}

