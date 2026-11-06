import dns from 'dns';
dns.setDefaultResultOrder('ipv4first');
import Fastify, { FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { config } from '../../../shared/src/config/env';
import { authRoutes } from './routes/auth.routes';

export function buildApp(): FastifyInstance {
  const app = Fastify({
    logger: config.env === 'development',
    trustProxy: true,
  });

  // CORS configuration
  app.register(cors, {
    origin: true,
    credentials: true,
  });

  // Anti-DDoS and SMS Pumping IP Rate Limiter
  const isTest = process.env.NODE_ENV === 'test' || config.env === 'test';
  app.register(rateLimit, {
    max: isTest ? 10000 : config.security.maxOtpRequestsPerIpPerHour * 5,
    timeWindow: '1 hour',
    allowList: isTest ? ['127.0.0.1'] : [],
  });


  // Health check endpoint
  app.get('/health', async () => {
    return {
      status: 'ok',
      service: 'rootu-core-api',
      timestamp: new Date().toISOString(),
    };
  });

  // Register Auth Routes
  app.register(authRoutes, { prefix: '/api/v1/auth' });

  return app;
}

export async function startServer() {
  const app = buildApp();
  try {
    const address = await app.listen({
      port: config.port,
      host: config.host,
    });
    console.log(`[RootU Core API] Server listening on ${address}`);
  } catch (err) {
    console.error('[RootU Core API] Failed to start server:', err);
    process.exit(1);
  }
}

// Start if executed directly
if (require.main === module) {
  startServer();
}

