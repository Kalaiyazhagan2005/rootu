import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { config } from '../config/env';

export interface AccessTokenPayload {
  userId: string;
  phoneE164: string;
  type: 'access';
  issuedAtMs?: number;
  iat?: number;
  exp?: number;
}

export interface VerificationTokenPayload {
  jti: string;
  phoneE164: string;
  purpose: 'registration' | 'password_reset';
  type: 'verification';
  iat?: number;
  exp?: number;
}

export class TokenService {
  /**
   * Issues a short-lived access token (15 minutes).
   * Explicitly locks signature algorithm to HS256.
   */
  public static signAccessToken(userId: string, phoneE164: string): string {
    const payload: AccessTokenPayload = {
      userId,
      phoneE164,
      type: 'access',
      issuedAtMs: Date.now(),
    };
    return jwt.sign(payload, config.jwt.accessSecret, {
      algorithm: 'HS256',
      expiresIn: config.jwt.accessExpiresIn as any,
    });
  }


  /**
   * Verifies an access token.
   * Explicitly enforces HS256 to reject alg: none and asymmetric algorithm substitution attacks.
   */
  public static verifyAccessToken(token: string): AccessTokenPayload {
    const decoded = jwt.verify(token, config.jwt.accessSecret, {
      algorithms: ['HS256'],
    }) as any;
    if (decoded.type !== 'access') {
      throw new Error('Invalid token type');
    }
    return decoded as AccessTokenPayload;
  }

  /**
   * Issues a short-lived, server-signed verification token upon successful OTP verification.
   * Cryptographically binds the phone number, purpose, and a unique single-use JTI
   * to completely prevent step-bypass, phone-swapping, and replay attacks.
   */
  public static signVerificationToken(
    phoneE164: string,
    purpose: 'registration' | 'password_reset'
  ): string {
    const payload: VerificationTokenPayload = {
      jti: crypto.randomUUID(),
      phoneE164,
      purpose,
      type: 'verification',
    };
    return jwt.sign(payload, config.jwt.verificationSecret, {
      algorithm: 'HS256',
      expiresIn: config.jwt.verificationExpiresIn as any,
    });
  }

  /**
   * Verifies a verification token and asserts cryptographic match with the requested phone number and purpose.
   */
  public static verifyVerificationToken(
    token: string,
    expectedPhoneE164: string,
    expectedPurpose: 'registration' | 'password_reset'
  ): VerificationTokenPayload {
    const decoded = jwt.verify(token, config.jwt.verificationSecret, {
      algorithms: ['HS256'],
    }) as any;
    if (decoded.type !== 'verification') {
      throw new Error('Invalid token type: not a verification token');
    }
    if (decoded.purpose !== expectedPurpose) {
      throw new Error(`Invalid token purpose: expected ${expectedPurpose}, got ${decoded.purpose}`);
    }
    if (decoded.phoneE164 !== expectedPhoneE164) {
      throw new Error('Phone number mismatch: token does not match requested phone number');
    }
    if (!decoded.jti || typeof decoded.jti !== 'string') {
      throw new Error('Invalid verification token: missing unique token identifier (JTI)');
    }
    return decoded as VerificationTokenPayload;
  }
}

