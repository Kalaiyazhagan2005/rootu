import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { authService } from '../../../../shared/src/services/auth.service';
import { TokenService } from '../../../../shared/src/services/token.service';
import { db } from '../../../../shared/src/database/db';
import {
  SendOtpSchema,
  VerifyOtpSchema,
  RegisterCompleteSchema,
  LoginSchema,
  RefreshTokenSchema,
  ForgotPasswordSendOtpSchema,
  ForgotPasswordResetSchema,
  LogoutSchema,
} from '../../../../shared/src/models/auth.schemas';

export const authRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // -------------------------------------------------------------
  // 1. REGISTRATION: STEP 1 - SEND OTP
  // -------------------------------------------------------------
  fastify.post('/register/send-otp', async (request, reply) => {
    const parseResult = SendOtpSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.sendRegistrationOtp(parseResult.data.phone);
      return reply.status(200).send(result);
    } catch (err: any) {
      if (err.retryAfter) {
        reply.header('Retry-After', String(err.retryAfter));
      }
      return reply.status(err.status || 500).send({
        error: err.message || 'Failed to send verification code',
        retryAfter: err.retryAfter,
      });
    }
  });

  // -------------------------------------------------------------
  // 1. REGISTRATION: STEP 2 - VERIFY OTP (SEPARATE STEP)
  // -------------------------------------------------------------
  fastify.post('/register/verify-otp', async (request, reply) => {
    const parseResult = VerifyOtpSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.verifyRegistrationOtp(
        parseResult.data.phone,
        parseResult.data.otp
      );
      return reply.status(200).send(result);
    } catch (err: any) {
      return reply.status(err.status || 500).send({
        error: err.message || 'OTP verification failed',
      });
    }
  });

  // -------------------------------------------------------------
  // 1. REGISTRATION: STEP 3 - COMPLETE REGISTRATION
  // -------------------------------------------------------------
  fastify.post('/register/complete', async (request, reply) => {
    const parseResult = RegisterCompleteSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.completeRegistration({
        verificationToken: parseResult.data.verificationToken,
        phone: parseResult.data.phone,
        fullName: parseResult.data.fullName,
        password: parseResult.data.password,
        acceptTerms: parseResult.data.acceptTerms,
        deviceInfo: request.headers['user-agent'],
        ipAddress: request.ip,
      });
      return reply.status(201).send(result);
    } catch (err: any) {
      return reply.status(err.status || 500).send({
        error: err.message || 'Failed to complete registration',
      });
    }
  });

  // -------------------------------------------------------------
  // 2. LOGIN
  // -------------------------------------------------------------
  fastify.post('/login', async (request, reply) => {
    const parseResult = LoginSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.login({
        phone: parseResult.data.phone,
        password: parseResult.data.password,
        rememberMe: parseResult.data.rememberMe,
        deviceInfo: request.headers['user-agent'],
        ipAddress: request.ip,
      });
      return reply.status(200).send(result);
    } catch (err: any) {
      if (err.retryAfter) {
        reply.header('Retry-After', String(err.retryAfter));
      }
      return reply.status(err.status || 500).send({
        error: err.message || 'Authentication failed',
        retryAfter: err.retryAfter,
      });
    }
  });

  // -------------------------------------------------------------
  // 3. REFRESH TOKEN (WITH ROTATION)
  // -------------------------------------------------------------
  fastify.post('/refresh', async (request, reply) => {
    const parseResult = RefreshTokenSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.refreshTokens(
        parseResult.data.refreshToken,
        request.headers['user-agent'],
        request.ip
      );
      return reply.status(200).send(result);
    } catch (err: any) {
      return reply.status(err.status || 500).send({
        error: err.message || 'Refresh failed',
      });
    }
  });

  // -------------------------------------------------------------
  // 4. FORGOT PASSWORD: STEP 1 - SEND OTP
  // -------------------------------------------------------------
  fastify.post('/forgot-password/send-otp', async (request, reply) => {
    const parseResult = ForgotPasswordSendOtpSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.sendForgotPasswordOtp(parseResult.data.phone);
      return reply.status(200).send(result);
    } catch (err: any) {
      if (err.retryAfter) {
        reply.header('Retry-After', String(err.retryAfter));
      }
      return reply.status(err.status || 500).send({
        error: err.message || 'Failed to send reset code',
        retryAfter: err.retryAfter,
      });
    }
  });

  // -------------------------------------------------------------
  // 4. FORGOT PASSWORD: STEP 2 - VERIFY OTP
  // -------------------------------------------------------------
  fastify.post('/forgot-password/verify-otp', async (request, reply) => {
    const parseResult = VerifyOtpSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.verifyForgotPasswordOtp(
        parseResult.data.phone,
        parseResult.data.otp
      );
      return reply.status(200).send(result);
    } catch (err: any) {
      return reply.status(err.status || 500).send({
        error: err.message || 'OTP verification failed',
      });
    }
  });

  // -------------------------------------------------------------
  // 4. FORGOT PASSWORD: STEP 3 - RESET PASSWORD & REVOKE ALL SESSIONS
  // -------------------------------------------------------------
  fastify.post('/forgot-password/reset', async (request, reply) => {
    const parseResult = ForgotPasswordResetSchema.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    try {
      const result = await authService.resetPassword({
        verificationToken: parseResult.data.verificationToken,
        phone: parseResult.data.phone,
        newPassword: parseResult.data.newPassword,
      });
      return reply.status(200).send(result);
    } catch (err: any) {
      return reply.status(err.status || 500).send({
        error: err.message || 'Password reset failed',
      });
    }
  });

  // -------------------------------------------------------------
  // 5. LOGOUT
  // -------------------------------------------------------------
  fastify.post('/logout', async (request, reply) => {
    const parseResult = LogoutSchema.safeParse(request.body || {});
    if (!parseResult.success) {
      return reply.status(400).send({
        error: 'Validation Error',
        details: parseResult.error.errors.map((e) => e.message),
      });
    }

    const result = await authService.logout(parseResult.data.refreshToken || '');
    return reply.status(200).send(result);
  });

  // -------------------------------------------------------------
  // 6. PROTECTED USER PROFILE (ME)
  // -------------------------------------------------------------
  fastify.get('/me', async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return reply.status(401).send({ error: 'Missing or malformed authorization header' });
    }

    const token = authHeader.substring(7);
    try {
      const payload = TokenService.verifyAccessToken(token);
      const user = await db.findUserById(payload.userId);
      if (!user) {
        return reply.status(404).send({ error: 'User not found' });
      }

      if (!user.isActive) {
        return reply.status(403).send({ error: 'Account is deactivated' });
      }

      // Session Invalidation on Password Reset:
      // If access token was issued prior to password reset, reject it immediately
      if (user.passwordChangedAt) {
        const tokenIssuedAtMs = payload.issuedAtMs || (payload.iat ? payload.iat * 1000 : 0);
        if (tokenIssuedAtMs < user.passwordChangedAt.getTime()) {
          return reply.status(401).send({ error: 'Session invalidated due to password reset. Please log in again.' });
        }
      }


      // Return clean user object with password hash strictly stripped
      return reply.status(200).send({
        user: {
          id: user.id,
          phoneE164: user.phoneE164,
          fullName: user.fullName,
          createdAt: user.createdAt,
        },
      });
    } catch (err: any) {
      return reply.status(401).send({ error: 'Invalid or expired access token' });
    }
  });
};

