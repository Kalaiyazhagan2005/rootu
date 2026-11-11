import dns from 'dns';
dns.setDefaultResultOrder('ipv4first');
import { RealtimeGatewayApp } from './app';
import { db } from '../../../shared/src/database/db';
import { config } from '../../../shared/src/config/env';

export async function startServer(): Promise<RealtimeGatewayApp> {
  const app = new RealtimeGatewayApp();

  let isShuttingDown = false;

  const handleGracefulShutdown = async (signal: string) => {
    if (isShuttingDown) return;
    isShuttingDown = true;

    console.log(`[RootU Realtime Gateway] Received ${signal}. Initiating graceful shutdown...`);

    const shutdownTimeout = setTimeout(() => {
      console.error('[RootU Realtime Gateway] Graceful shutdown timed out after 10s. Forcing exit.');
      process.exit(1);
    }, 10000);

    try {
      await app.stop();
      await db.close();
      clearTimeout(shutdownTimeout);
      console.log('[RootU Realtime Gateway] Graceful shutdown completed cleanly.');
      process.exit(0);
    } catch (err: any) {
      console.error('[RootU Realtime Gateway] Error during graceful shutdown:', err.message);
      clearTimeout(shutdownTimeout);
      process.exit(1);
    }
  };

  process.on('SIGINT', () => handleGracefulShutdown('SIGINT'));
  process.on('SIGTERM', () => handleGracefulShutdown('SIGTERM'));

  process.on('unhandledRejection', (reason) => {
    console.error('[RootU Realtime Gateway] Unhandled Rejection:', reason);
  });

  process.on('uncaughtException', (err) => {
    console.error('[RootU Realtime Gateway] Uncaught Exception:', err);
    handleGracefulShutdown('uncaughtException');
  });

  try {
    const address = await app.start(config.gatewayPort, config.host);
    console.log(`[RootU Realtime Gateway] Server listening on ${address} (WebSocket path: /ws)`);
    return app;
  } catch (err: any) {
    console.error('[RootU Realtime Gateway] Failed to start server:', err.message);
    process.exit(1);
  }
}

if (require.main === module) {
  startServer();
}

