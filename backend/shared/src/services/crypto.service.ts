import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import { config } from '../config/env';

export class CryptoService {
  private static readonly OTP_PEPPER = 'rootu-secure-otp-pepper-constant-salt-2026';

  /**
   * Precomputed 12-round bcrypt hash used to equalize execution time on non-existent accounts,
   * neutralizing timing attack enumeration (OWASP ASVS compliance).
   */
  public static readonly DUMMY_BCRYPT_HASH =
    '$2a$12$e8vE9V9qQ4aV2N0m3C8PZuH4Gf0F2N9m3C8PZuH4Gf0F2N9m3C8PZ';

  /**
   * Generates a cryptographically secure 6-digit numeric OTP.
   * Uses crypto.randomInt() to prevent PRNG predictability attacks.
   */
  public static generateSecureOtp(length: number = config.security.otpLength): string {
    const max = Math.pow(10, length);
    const randomValue = crypto.randomInt(0, max);
    return randomValue.toString().padStart(length, '0');
  }

  /**
   * Creates a cryptographic hash of an OTP before storing in Redis/database.
   * Plaintext OTPs are NEVER stored anywhere.
   */
  public static hashOtp(otp: string, phoneE164: string): string {
    return crypto
      .createHmac('sha256', this.OTP_PEPPER)
      .update(`${phoneE164}:${otp}`)
      .digest('hex');
  }

  /**
   * Verifies a candidate OTP against a stored hash using timing-safe comparison.
   * Guarantees length parity before timingSafeEqual to avoid unhandled RangeErrors.
   */
  public static verifyOtpHash(candidateOtp: string, phoneE164: string, expectedHash: string): boolean {
    const candidateHash = this.hashOtp(candidateOtp, phoneE164);
    const candBuf = Buffer.from(candidateHash, 'hex');
    const expBuf = Buffer.from(expectedHash, 'hex');
    if (candBuf.length === 0 || expBuf.length === 0 || candBuf.length !== expBuf.length) {
      return false;
    }
    return crypto.timingSafeEqual(candBuf, expBuf);
  }

  /**
   * Hashes a password using bcrypt with a work factor of 12 (OWASP compliant).
   */
  public static async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, config.security.bcryptRounds);
  }

  /**
   * Compares a plaintext password against a stored bcrypt hash.
   */
  public static async comparePassword(password: string, hash: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }

  /**
   * Executes a dummy bcrypt verification against a precomputed 12-round hash.
   * Ensures identical response timing (~200ms) whether the account exists or not.
   */
  public static async dummyPasswordCompare(password: string): Promise<boolean> {
    return bcrypt.compare(password, this.DUMMY_BCRYPT_HASH);
  }

  /**
   * Hashes a refresh token using SHA-256 for secure database storage.
   */
  public static hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  /**
   * Generates a cryptographically random token string for refresh tokens.
   */
  public static generateRandomToken(bytes: number = 32): string {
    return crypto.randomBytes(bytes).toString('hex');
  }
}


