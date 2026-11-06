import crypto from 'crypto';
import { Pool } from 'pg';
import { config } from '../config/env';

export interface UserRecord {
  id: string;
  phoneE164: string;
  fullName: string;
  passwordHash: string;
  termsAcceptedAt: Date;
  isActive: boolean;
  passwordChangedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface RefreshTokenRecord {
  id: string;
  userId: string;
  tokenHash: string;
  deviceInfo?: string;
  ipAddress?: string;
  expiresAt: Date;
  revokedAt: Date | null;
  createdAt: Date;
}

export interface OtpRecord {
  phoneE164: string;
  otpHash: string;
  purpose: 'registration' | 'forgot_password';
  attempts: number;
  maxAttempts: number;
  expiresAt: number; // epoch ms
  cooldownUntil: number; // epoch ms
  createdAt: number;
}

export interface LoginAttemptRecord {
  phoneE164: string;
  failedCount: number;
  lockedUntil: number | null; // epoch ms
  lastAttemptAt: number;
}

/**
 * Enterprise Production PostgreSQL Database Store with In-Memory Test Fallback.
 * Ensures strict ACID transactions, parameterized SQL injection immunity,
 * and high-concurrency session security.
 */
export class DatabaseStore {
  private pool: Pool | null = null;

  // In-memory fallback structures
  private usersByPhone = new Map<string, UserRecord>();
  private usersById = new Map<string, UserRecord>();
  private refreshTokens = new Map<string, RefreshTokenRecord>(); // key: tokenHash
  private otps = new Map<string, OtpRecord>(); // key: `${phoneE164}:${purpose}`
  private loginAttempts = new Map<string, LoginAttemptRecord>(); // key: phoneE164
  private consumedVerificationTokens = new Map<string, number>(); // key: jti, value: expiresAt ms
  private otpRequestsByPhone = new Map<string, number[]>(); // key: phoneE164, value: timestamps ms

  constructor() {
    if (config.database.url) {
      try {
        this.pool = new Pool({
          connectionString: config.database.url,
          max: 20,
          idleTimeoutMillis: 30000,
          connectionTimeoutMillis: 5000,
        });
        this.pool.on('error', (err) => {
          console.error('[PostgreSQL Pool Background Error]:', err);
        });
      } catch (err) {
        console.error('[PostgreSQL Pool Init Failed, using memory store]:', err);
        this.pool = null;
      }
    }
  }

  public getPool(): Pool | null {
    return this.pool;
  }

  // --- User Operations ---

  public async findUserByPhone(phoneE164: string): Promise<UserRecord | null> {
    if (this.pool) {
      const res = await this.pool.query(
        `SELECT id, phone_e164, full_name, password_hash, terms_accepted_at, is_active, password_changed_at, created_at, updated_at
         FROM users WHERE phone_e164 = $1`,
        [phoneE164]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      return {
        id: row.id,
        phoneE164: row.phone_e164,
        fullName: row.full_name,
        passwordHash: row.password_hash,
        termsAcceptedAt: new Date(row.terms_accepted_at),
        isActive: Boolean(row.is_active),
        passwordChangedAt: row.password_changed_at ? new Date(row.password_changed_at) : undefined,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      };
    }

    const user = this.usersByPhone.get(phoneE164);
    return user ? { ...user } : null;
  }

  public async findUserById(id: string): Promise<UserRecord | null> {
    if (this.pool) {
      const res = await this.pool.query(
        `SELECT id, phone_e164, full_name, password_hash, terms_accepted_at, is_active, password_changed_at, created_at, updated_at
         FROM users WHERE id = $1`,
        [id]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      return {
        id: row.id,
        phoneE164: row.phone_e164,
        fullName: row.full_name,
        passwordHash: row.password_hash,
        termsAcceptedAt: new Date(row.terms_accepted_at),
        isActive: Boolean(row.is_active),
        passwordChangedAt: row.password_changed_at ? new Date(row.password_changed_at) : undefined,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      };
    }

    const user = this.usersById.get(id);
    return user ? { ...user } : null;
  }

  public async createUser(data: {
    phoneE164: string;
    fullName: string;
    passwordHash: string;
    termsAcceptedAt: Date;
  }): Promise<UserRecord> {
    if (this.pool) {
      try {
        const res = await this.pool.query(
          `INSERT INTO users (phone_e164, full_name, password_hash, terms_accepted_at, is_active, password_changed_at)
           VALUES ($1, $2, $3, $4, TRUE, NOW())
           RETURNING id, phone_e164, full_name, password_hash, terms_accepted_at, is_active, password_changed_at, created_at, updated_at`,
          [data.phoneE164, data.fullName, data.passwordHash, data.termsAcceptedAt]
        );
        const row = res.rows[0];
        return {
          id: row.id,
          phoneE164: row.phone_e164,
          fullName: row.full_name,
          passwordHash: row.password_hash,
          termsAcceptedAt: new Date(row.terms_accepted_at),
          isActive: Boolean(row.is_active),
          passwordChangedAt: row.password_changed_at ? new Date(row.password_changed_at) : undefined,
          createdAt: new Date(row.created_at),
          updatedAt: new Date(row.updated_at),
        };
      } catch (err: any) {
        if (err.code === '23505') {
          const conflictErr: any = new Error('A user with this mobile number already exists');
          conflictErr.status = 409;
          throw conflictErr;
        }
        throw err;
      }
    }

    if (this.usersByPhone.has(data.phoneE164)) {
      const err: any = new Error('A user with this mobile number already exists');
      err.status = 409;
      throw err;
    }

    const now = new Date();
    const user: UserRecord = {
      id: crypto.randomUUID(),
      phoneE164: data.phoneE164,
      fullName: data.fullName,
      passwordHash: data.passwordHash,
      termsAcceptedAt: data.termsAcceptedAt,
      isActive: true,
      passwordChangedAt: now,
      createdAt: now,
      updatedAt: now,
    };

    this.usersByPhone.set(user.phoneE164, user);
    this.usersById.set(user.id, user);
    return { ...user };
  }

  public async updatePassword(userId: string, newPasswordHash: string): Promise<void> {
    if (this.pool) {
      const res = await this.pool.query(
        `UPDATE users
         SET password_hash = $1, updated_at = NOW(), password_changed_at = NOW()
         WHERE id = $2`,
        [newPasswordHash, userId]
      );
      if (res.rowCount === 0) {
        throw new Error('User not found');
      }
      return;
    }

    const user = this.usersById.get(userId);
    if (!user) {
      throw new Error('User not found');
    }

    const now = new Date();
    user.passwordHash = newPasswordHash;
    user.updatedAt = now;
    user.passwordChangedAt = now;
    this.usersByPhone.set(user.phoneE164, user);
    this.usersById.set(user.id, user);
  }

  public async setUserActive(userIdOrPhone: string, isActive: boolean): Promise<void> {
    if (this.pool) {
      await this.pool.query(
        `UPDATE users
         SET is_active = $1, updated_at = NOW()
         WHERE id::text = $2 OR phone_e164 = $2`,
        [isActive, userIdOrPhone]
      );
      return;
    }

    const user = this.usersById.get(userIdOrPhone) || this.usersByPhone.get(userIdOrPhone);
    if (user) {
      user.isActive = isActive;
      user.updatedAt = new Date();
      this.usersByPhone.set(user.phoneE164, user);
      this.usersById.set(user.id, user);
    }
  }

  // --- Refresh Token & Session Management ---

  public async createRefreshToken(data: {
    userId: string;
    tokenHash: string;
    expiresAt: Date;
    deviceInfo?: string;
    ipAddress?: string;
  }): Promise<RefreshTokenRecord> {
    if (this.pool) {
      const res = await this.pool.query(
        `INSERT INTO refresh_tokens (user_id, token_hash, expires_at, device_info, ip_address)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, user_id, token_hash, device_info, ip_address, expires_at, revoked_at, created_at`,
        [data.userId, data.tokenHash, data.expiresAt, data.deviceInfo || null, data.ipAddress || null]
      );
      const row = res.rows[0];
      return {
        id: row.id,
        userId: row.user_id,
        tokenHash: row.token_hash,
        deviceInfo: row.device_info || undefined,
        ipAddress: row.ip_address || undefined,
        expiresAt: new Date(row.expires_at),
        revokedAt: row.revoked_at ? new Date(row.revoked_at) : null,
        createdAt: new Date(row.created_at),
      };
    }

    const record: RefreshTokenRecord = {
      id: crypto.randomUUID(),
      userId: data.userId,
      tokenHash: data.tokenHash,
      deviceInfo: data.deviceInfo,
      ipAddress: data.ipAddress,
      expiresAt: data.expiresAt,
      revokedAt: null,
      createdAt: new Date(),
    };

    this.refreshTokens.set(data.tokenHash, record);
    return { ...record };
  }

  public async findRefreshToken(tokenHash: string): Promise<RefreshTokenRecord | null> {
    if (this.pool) {
      const res = await this.pool.query(
        `SELECT id, user_id, token_hash, device_info, ip_address, expires_at, revoked_at, created_at
         FROM refresh_tokens WHERE token_hash = $1`,
        [tokenHash]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      return {
        id: row.id,
        userId: row.user_id,
        tokenHash: row.token_hash,
        deviceInfo: row.device_info || undefined,
        ipAddress: row.ip_address || undefined,
        expiresAt: new Date(row.expires_at),
        revokedAt: row.revoked_at ? new Date(row.revoked_at) : null,
        createdAt: new Date(row.created_at),
      };
    }

    const token = this.refreshTokens.get(tokenHash);
    return token ? { ...token } : null;
  }

  public async revokeRefreshToken(tokenHash: string): Promise<void> {
    if (this.pool) {
      await this.pool.query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1`,
        [tokenHash]
      );
      return;
    }

    const token = this.refreshTokens.get(tokenHash);
    if (token) {
      token.revokedAt = new Date();
    }
  }

  /**
   * Atomically rotates an active refresh token: marks it as revoked only if currently active.
   * Eliminates concurrent refresh token race conditions and precisely detects token replay/theft.
   */
  public async rotateRefreshToken(tokenHash: string): Promise<{
    status: 'active' | 'revoked' | 'not_found';
    record: RefreshTokenRecord | null;
  }> {
    if (this.pool) {
      const res = await this.pool.query(
        `UPDATE refresh_tokens
         SET revoked_at = NOW()
         WHERE token_hash = $1 AND revoked_at IS NULL
         RETURNING id, user_id, token_hash, device_info, ip_address, expires_at, revoked_at, created_at`,
        [tokenHash]
      );
      if (res.rowCount === 1) {
        const row = res.rows[0];
        return {
          status: 'active',
          record: {
            id: row.id,
            userId: row.user_id,
            tokenHash: row.token_hash,
            deviceInfo: row.device_info || undefined,
            ipAddress: row.ip_address || undefined,
            expiresAt: new Date(row.expires_at),
            revokedAt: new Date(row.revoked_at),
            createdAt: new Date(row.created_at),
          },
        };
      }

      const existing = await this.findRefreshToken(tokenHash);
      if (!existing) {
        return { status: 'not_found', record: null };
      }
      return { status: 'revoked', record: existing };
    }

    const token = this.refreshTokens.get(tokenHash);
    if (!token) return { status: 'not_found', record: null };
    if (token.revokedAt) return { status: 'revoked', record: { ...token } };

    token.revokedAt = new Date();
    return { status: 'active', record: { ...token } };
  }


  /**
   * CRITICAL SECURITY REQUIREMENT:
   * When password is reset or a security breach is detected,
   * immediately revoke ALL active refresh tokens for the user account.
   */
  public async revokeAllUserTokens(userId: string): Promise<number> {
    if (this.pool) {
      const res = await this.pool.query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId]
      );
      return res.rowCount || 0;
    }

    let count = 0;
    const now = new Date();
    for (const [_, token] of this.refreshTokens) {
      if (token.userId === userId && !token.revokedAt) {
        token.revokedAt = now;
        count++;
      }
    }
    return count;
  }

  // --- OTP Management ---

  public async setOtp(record: OtpRecord): Promise<void> {
    if (this.pool) {
      const client = await this.pool.connect();
      try {
        await client.query('BEGIN');
        await client.query(
          `DELETE FROM otps WHERE phone_e164 = $1 AND purpose = $2`,
          [record.phoneE164, record.purpose]
        );
        await client.query(
          `INSERT INTO otps (phone_e164, otp_hash, purpose, attempts, max_attempts, expires_at, cooldown_until, created_at)
           VALUES ($1, $2, $3, $4, $5, to_timestamp($6 / 1000.0), to_timestamp($7 / 1000.0), to_timestamp($8 / 1000.0))`,
          [
            record.phoneE164,
            record.otpHash,
            record.purpose,
            record.attempts,
            record.maxAttempts,
            record.expiresAt,
            record.cooldownUntil,
            record.createdAt,
          ]
        );
        await client.query('COMMIT');
      } catch (err) {
        await client.query('ROLLBACK');
        throw err;
      } finally {
        client.release();
      }
      return;
    }


    const key = `${record.phoneE164}:${record.purpose}`;
    this.otps.set(key, { ...record });
  }

  public async getOtp(phoneE164: string, purpose: 'registration' | 'forgot_password'): Promise<OtpRecord | null> {
    if (this.pool) {
      const res = await this.pool.query(
        `SELECT phone_e164, otp_hash, purpose, attempts, max_attempts,
                EXTRACT(EPOCH FROM expires_at) * 1000 AS expires_at,
                EXTRACT(EPOCH FROM cooldown_until) * 1000 AS cooldown_until,
                EXTRACT(EPOCH FROM created_at) * 1000 AS created_at
         FROM otps
         WHERE phone_e164 = $1 AND purpose = $2
         ORDER BY created_at DESC
         LIMIT 1`,
        [phoneE164, purpose]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      const expiresAt = Math.round(Number(row.expires_at));
      if (Date.now() > expiresAt) {
        await this.pool.query(
          `DELETE FROM otps WHERE phone_e164 = $1 AND purpose = $2`,
          [phoneE164, purpose]
        );
        return null;
      }
      return {
        phoneE164: row.phone_e164,
        otpHash: row.otp_hash,
        purpose: row.purpose,
        attempts: Number(row.attempts),
        maxAttempts: Number(row.max_attempts),
        expiresAt,
        cooldownUntil: Math.round(Number(row.cooldown_until)),
        createdAt: Math.round(Number(row.created_at)),
      };
    }

    const key = `${phoneE164}:${purpose}`;
    const record = this.otps.get(key);
    if (!record) return null;

    if (Date.now() > record.expiresAt) {
      this.otps.delete(key);
      return null;
    }

    return { ...record };
  }

  public async incrementOtpAttempt(phoneE164: string, purpose: 'registration' | 'forgot_password'): Promise<number> {
    if (this.pool) {
      const res = await this.pool.query(
        `UPDATE otps
         SET attempts = attempts + 1
         WHERE phone_e164 = $1 AND purpose = $2
         RETURNING attempts, max_attempts`,
        [phoneE164, purpose]
      );
      if (res.rows.length === 0) return 0;
      const attempts = Number(res.rows[0].attempts);
      const maxAttempts = Number(res.rows[0].max_attempts);
      if (attempts >= maxAttempts) {
        await this.pool.query(
          `DELETE FROM otps WHERE phone_e164 = $1 AND purpose = $2`,
          [phoneE164, purpose]
        );
      }
      return attempts;
    }

    const key = `${phoneE164}:${purpose}`;
    const record = this.otps.get(key);
    if (!record) return 0;

    record.attempts += 1;
    if (record.attempts >= record.maxAttempts) {
      this.otps.delete(key);
      return record.attempts;
    }

    return record.attempts;
  }

  public async deleteOtp(phoneE164: string, purpose: 'registration' | 'forgot_password'): Promise<void> {
    if (this.pool) {
      await this.pool.query(
        `DELETE FROM otps WHERE phone_e164 = $1 AND purpose = $2`,
        [phoneE164, purpose]
      );
      return;
    }

    const key = `${phoneE164}:${purpose}`;
    this.otps.delete(key);
  }

  /**
   * Atomically burns an OTP record and returns true if deleted.
   * If another concurrent request already burned it, returns false (eliminates race condition).
   */
  public async burnOtp(phoneE164: string, purpose: 'registration' | 'forgot_password'): Promise<boolean> {
    if (this.pool) {
      const res = await this.pool.query(
        `DELETE FROM otps WHERE phone_e164 = $1 AND purpose = $2 RETURNING id`,
        [phoneE164, purpose]
      );
      return (res.rowCount ?? 0) > 0;
    }

    const key = `${phoneE164}:${purpose}`;
    if (!this.otps.has(key)) return false;
    this.otps.delete(key);
    return true;
  }

  // --- Login Attempts & Lockout Management ---

  public async getLoginAttempt(phoneE164: string): Promise<LoginAttemptRecord | null> {
    const lockoutWindowMs = config.security.lockoutDurationSeconds * 1000;
    const now = Date.now();

    if (this.pool) {
      const res = await this.pool.query(
        `SELECT phone_e164, failed_count,
                EXTRACT(EPOCH FROM locked_until) * 1000 AS locked_until,
                EXTRACT(EPOCH FROM last_attempt_at) * 1000 AS last_attempt_at
         FROM login_attempts
         WHERE phone_e164 = $1`,
        [phoneE164]
      );
      if (res.rows.length === 0) return null;
      const row = res.rows[0];
      let lockedUntil: number | null = row.locked_until ? Math.round(Number(row.locked_until)) : null;
      let failedCount = Number(row.failed_count);
      const lastAttemptAt = Math.round(Number(row.last_attempt_at));

      if ((lockedUntil && now > lockedUntil) || (!lockedUntil && now - lastAttemptAt > lockoutWindowMs)) {
        failedCount = 0;
        lockedUntil = null;
        await this.pool.query(
          `UPDATE login_attempts SET failed_count = 0, locked_until = NULL WHERE phone_e164 = $1`,
          [phoneE164]
        );
      }

      return {
        phoneE164: row.phone_e164,
        failedCount,
        lockedUntil,
        lastAttemptAt,
      };
    }

    const record = this.loginAttempts.get(phoneE164);
    if (!record) return null;

    if ((record.lockedUntil && now > record.lockedUntil) || (!record.lockedUntil && now - record.lastAttemptAt > lockoutWindowMs)) {
      record.failedCount = 0;
      record.lockedUntil = null;
    }

    return { ...record };
  }


  public async recordFailedLogin(
    phoneE164: string,
    maxAttempts: number,
    lockoutDurationMs: number
  ): Promise<{ failedCount: number; isLocked: boolean; lockUntilMs: number | null }> {
    if (this.pool) {
      const now = Date.now();
      const existing = await this.getLoginAttempt(phoneE164);
      let failedCount = (existing ? existing.failedCount : 0) + 1;
      let lockedUntil: number | null = null;
      let isLocked = false;

      if (failedCount >= maxAttempts) {
        lockedUntil = now + lockoutDurationMs;
        isLocked = true;
      }

      await this.pool.query(
        `INSERT INTO login_attempts (phone_e164, failed_count, locked_until, last_attempt_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (phone_e164) DO UPDATE
         SET failed_count = EXCLUDED.failed_count,
             locked_until = EXCLUDED.locked_until,
             last_attempt_at = NOW()`,
        [
          phoneE164,
          failedCount,
          lockedUntil ? new Date(lockedUntil) : null,
        ]
      );

      return {
        failedCount,
        isLocked,
        lockUntilMs: lockedUntil,
      };
    }

    let record = this.loginAttempts.get(phoneE164);
    const now = Date.now();

    if (!record) {
      record = {
        phoneE164,
        failedCount: 0,
        lockedUntil: null,
        lastAttemptAt: now,
      };
      this.loginAttempts.set(phoneE164, record);
    }

    if (record.lockedUntil && now > record.lockedUntil) {
      record.failedCount = 0;
      record.lockedUntil = null;
    }

    record.failedCount += 1;
    record.lastAttemptAt = now;

    if (record.failedCount >= maxAttempts) {
      record.lockedUntil = now + lockoutDurationMs;
      return {
        failedCount: record.failedCount,
        isLocked: true,
        lockUntilMs: record.lockedUntil,
      };
    }

    return {
      failedCount: record.failedCount,
      isLocked: false,
      lockUntilMs: null,
    };
  }

  public async resetFailedLogins(phoneE164: string): Promise<void> {
    if (this.pool) {
      await this.pool.query(`DELETE FROM login_attempts WHERE phone_e164 = $1`, [phoneE164]);
      return;
    }
    this.loginAttempts.delete(phoneE164);
  }

  // --- Step-Bypass & Replay Defense: Single-Use Verification Token Tracking ---

  public async isVerificationTokenConsumed(jti: string): Promise<boolean> {
    if (this.pool) {
      const res = await this.pool.query(
        `SELECT jti, EXTRACT(EPOCH FROM expires_at) * 1000 AS expires_at
         FROM consumed_verification_tokens WHERE jti = $1`,
        [jti]
      );
      if (res.rows.length === 0) return false;
      const expiresAt = Math.round(Number(res.rows[0].expires_at));
      if (Date.now() > expiresAt) {
        await this.pool.query(`DELETE FROM consumed_verification_tokens WHERE jti = $1`, [jti]);
        return false;
      }
      return true;
    }

    const expiresAt = this.consumedVerificationTokens.get(jti);
    if (!expiresAt) return false;
    if (Date.now() > expiresAt) {
      this.consumedVerificationTokens.delete(jti);
      return false;
    }
    return true;
  }

  public async consumeVerificationToken(jti: string, ttlMs: number = 600000): Promise<void> {
    if (this.pool) {
      const expiresAt = new Date(Date.now() + ttlMs);
      await this.pool.query(
        `INSERT INTO consumed_verification_tokens (jti, expires_at)
         VALUES ($1, $2)
         ON CONFLICT (jti) DO NOTHING`,
        [jti, expiresAt]
      );
      return;
    }

    this.consumedVerificationTokens.set(jti, Date.now() + ttlMs);
  }

  /**
   * Atomically claims and consumes a single-use verification token in one operation.
   * Completely eliminates TOCTOU (Time-Of-Check to Time-Of-Use) race conditions under high concurrency.
   * Returns true if successfully consumed for the first time.
   * Returns false if already consumed or replayed.
   */
  public async consumeVerificationTokenOnce(jti: string, ttlMs: number = 600000): Promise<boolean> {
    if (this.pool) {
      await this.pool.query(`DELETE FROM consumed_verification_tokens WHERE expires_at < NOW()`);
      const expiresAt = new Date(Date.now() + ttlMs);
      const res = await this.pool.query(
        `INSERT INTO consumed_verification_tokens (jti, expires_at)
         VALUES ($1, $2)
         ON CONFLICT (jti) DO NOTHING
         RETURNING jti`,
        [jti, expiresAt]
      );
      return (res.rowCount ?? 0) === 1;
    }

    const now = Date.now();
    const existing = this.consumedVerificationTokens.get(jti);
    if (existing && now <= existing) {
      return false;
    }

    this.consumedVerificationTokens.set(jti, now + ttlMs);
    return true;
  }


  // --- Anti-SMS Toll Fraud & Pumping Rate Limiter (Per Phone Hourly Cap) ---

  public async checkAndRecordOtpRateLimit(
    phoneE164: string,
    maxPerHour: number
  ): Promise<{ allowed: boolean; retryAfterSeconds: number }> {
    if (this.pool) {
      await this.pool.query(`DELETE FROM otp_requests WHERE requested_at < NOW() - INTERVAL '1 hour'`);

      const res = await this.pool.query(
        `SELECT COUNT(*)::int AS count, MIN(EXTRACT(EPOCH FROM requested_at) * 1000) AS oldest_ms
         FROM otp_requests
         WHERE phone_e164 = $1 AND requested_at > NOW() - INTERVAL '1 hour'`,
        [phoneE164]
      );

      const count = Number(res.rows[0]?.count || 0);
      const oldestMs = res.rows[0]?.oldest_ms ? Math.round(Number(res.rows[0].oldest_ms)) : Date.now();

      if (count >= maxPerHour) {
        const retryAfter = Math.ceil((oldestMs + 3600 * 1000 - Date.now()) / 1000);
        return { allowed: false, retryAfterSeconds: Math.max(1, retryAfter) };
      }

      await this.pool.query(
        `INSERT INTO otp_requests (phone_e164, requested_at) VALUES ($1, NOW())`,
        [phoneE164]
      );
      return { allowed: true, retryAfterSeconds: 0 };
    }

    const now = Date.now();
    const oneHourAgo = now - 3600 * 1000;
    const history = (this.otpRequestsByPhone.get(phoneE164) || []).filter((t) => t > oneHourAgo);

    if (history.length >= maxPerHour) {
      const oldestInWindow = history[0];
      const retryAfter = Math.ceil((oldestInWindow + 3600 * 1000 - now) / 1000);
      return { allowed: false, retryAfterSeconds: Math.max(1, retryAfter) };
    }

    history.push(now);
    this.otpRequestsByPhone.set(phoneE164, history);
    return { allowed: true, retryAfterSeconds: 0 };
  }

  public async clearAll(): Promise<void> {
    if (this.pool) {
      try {
        await this.pool.query(`
          TRUNCATE TABLE
            users,
            refresh_tokens,
            otps,
            login_attempts,
            consumed_verification_tokens,
            otp_requests
          CASCADE;
        `);
      } catch (err) {
        console.error('[PostgreSQL TRUNCATE Failed]:', err);
      }
    }

    this.usersByPhone.clear();
    this.usersById.clear();
    this.refreshTokens.clear();
    this.otps.clear();
    this.loginAttempts.clear();
    this.consumedVerificationTokens.clear();
    this.otpRequestsByPhone.clear();
  }

  public async close(): Promise<void> {
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }
}

// Global Singleton Database Store
export const db = new DatabaseStore();
