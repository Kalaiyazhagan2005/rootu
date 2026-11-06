import { config } from '../config/env';
import { db, UserRecord } from '../database/db';
import { CryptoService } from './crypto.service';
import { PhoneService } from './phone.service';
import { TokenService } from './token.service';
import { SmsGateway, LiveSmsDispatcher, TwilioSmsGateway } from './sms_provider';


export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number; // in seconds
}

export interface UserResponse {
  id: string;
  phoneE164: string;
  fullName: string;
  createdAt: Date;
}

export class AuthService {
  private smsGateway: SmsGateway;

  constructor(smsGateway?: SmsGateway) {
    this.smsGateway = smsGateway || new LiveSmsDispatcher();
  }


  public setSmsGateway(gateway: SmsGateway) {
    this.smsGateway = gateway;
  }

  // ==========================================
  // 1. REGISTRATION OTP FLOW
  // ==========================================

  public async sendRegistrationOtp(rawPhone: string): Promise<{ success: boolean; message: string; cooldownSeconds: number }> {
    const phoneE164 = PhoneService.normalizeToE164(rawPhone);

    // Check if phone number is already registered
    const existingUser = await db.findUserByPhone(phoneE164);
    if (existingUser) {
      throw { status: 409, message: 'A user with this mobile number is already registered. Please log in.' };
    }

    // Check server-side 60s cooldown timer
    const existingOtp = await db.getOtp(phoneE164, 'registration');
    const now = Date.now();
    if (existingOtp && existingOtp.cooldownUntil > now) {
      const remainingSeconds = Math.ceil((existingOtp.cooldownUntil - now) / 1000);
      throw {
        status: 429,
        message: `Please wait ${remainingSeconds} seconds before requesting a new verification code.`,
        retryAfter: remainingSeconds,
      };
    }

    // Anti-SMS Toll Fraud: Enforce hourly rate limit per phone number
    const rateLimit = await db.checkAndRecordOtpRateLimit(
      phoneE164,
      config.security.maxOtpRequestsPerPhonePerHour
    );
    if (!rateLimit.allowed) {
      throw {
        status: 429,
        message: `Too many verification code requests for this mobile number. Please try again in ${Math.ceil(rateLimit.retryAfterSeconds / 60)} minutes.`,
        retryAfter: rateLimit.retryAfterSeconds,
      };
    }

    // Generate cryptographically secure OTP (crypto.randomInt)
    let otp = CryptoService.generateSecureOtp(config.security.otpLength);

    // Dispatch via SMS gateway
    const sendResult = await this.smsGateway.sendOtp(phoneE164, otp, 'registration');
    const sent = typeof sendResult === 'boolean' ? sendResult : sendResult?.success;
    if (!sent && (this.smsGateway as any).isConfigured?.()) {
      throw {
        status: 502,
        message: 'SMS verification code could not be delivered by the telecom gateway. Please verify your mobile number or try again later.',
      };
    }

    if (typeof sendResult === 'object' && sendResult?.dispatchedOtp) {
      otp = sendResult.dispatchedOtp;
    }

    const otpHash = CryptoService.hashOtp(otp, phoneE164);

    // Save hashed OTP with strict expiration and cooldown window
    await db.setOtp({
      phoneE164,
      otpHash,
      purpose: 'registration',
      attempts: 0,
      maxAttempts: config.security.maxOtpVerifyAttempts,
      expiresAt: now + config.security.otpExpirySeconds * 1000,
      cooldownUntil: now + config.security.otpCooldownSeconds * 1000,
      createdAt: now,
    });

    // Never leak OTP in JSON response
    return {
      success: true,
      message: 'Verification code sent successfully to your mobile number.',
      cooldownSeconds: config.security.otpCooldownSeconds,
    };
  }

  public async verifyRegistrationOtp(
    rawPhone: string,
    candidateOtp: string
  ): Promise<{ success: boolean; verificationToken: string; message: string }> {
    const phoneE164 = PhoneService.normalizeToE164(rawPhone);

    const otpRecord = await db.getOtp(phoneE164, 'registration');
    if (!otpRecord) {
      throw {
        status: 400,
        message: 'Invalid or expired verification code. Please request a new code.',
      };
    }

    // Timing-safe verification against stored hash
    const isValid = CryptoService.verifyOtpHash(candidateOtp, phoneE164, otpRecord.otpHash);

    if (!isValid) {
      const attempts = await db.incrementOtpAttempt(phoneE164, 'registration');
      if (attempts >= otpRecord.maxAttempts) {
        throw {
          status: 400,
          message: 'Too many failed verification attempts. This code has been invalidated for security. Please request a new code.',
        };
      }
      const remaining = otpRecord.maxAttempts - attempts;
      throw {
        status: 400,
        message: `Invalid verification code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`,
      };
    }

    // Atomically burn OTP immediately upon success to eliminate replay and concurrent race attacks
    const burned = await db.burnOtp(phoneE164, 'registration');
    if (!burned) {
      throw {
        status: 400,
        message: 'Invalid or expired verification code. Please request a new code.',
      };
    }

    // Issue short-lived server-signed verification token cryptographically bound to phone number
    const verificationToken = TokenService.signVerificationToken(phoneE164, 'registration');

    return {
      success: true,
      verificationToken,
      message: 'Mobile number verified successfully. You may now complete account registration.',
    };
  }

  public async completeRegistration(data: {
    verificationToken: string;
    phone: string;
    fullName: string;
    password: string;
    acceptTerms: boolean;
    deviceInfo?: string;
    ipAddress?: string;
  }): Promise<{ user: UserResponse; tokens: AuthTokens }> {
    const phoneE164 = PhoneService.normalizeToE164(data.phone);

    // Cryptographic validation of verification token (prevents step-bypass and phone swapping)
    let tokenPayload: any;
    try {
      tokenPayload = TokenService.verifyVerificationToken(data.verificationToken, phoneE164, 'registration');
    } catch (err: any) {
      throw {
        status: 401,
        message: 'Step-verification failed: Invalid or expired phone verification token.',
      };
    }

    // Single-use token enforcement: Atomic consumption prevents verification token replay attacks
    const claimed = await db.consumeVerificationTokenOnce(tokenPayload.jti);
    if (!claimed) {
      throw {
        status: 401,
        message: 'Step-verification failed: Verification token has already been used.',
      };
    }

    // Double check that user wasn't registered in the interim
    const existing = await db.findUserByPhone(phoneE164);
    if (existing) {
      throw { status: 409, message: 'A user with this mobile number already exists.' };
    }

    // Hash password with bcrypt work factor 12 (OWASP standard)
    const passwordHash = await CryptoService.hashPassword(data.password);

    // Create user in database
    const user = await db.createUser({
      phoneE164,
      fullName: data.fullName.trim(),
      passwordHash,
      termsAcceptedAt: new Date(),
    });

    // Reset any prior failed login attempts / lockouts from pre-registration hammering
    await db.resetFailedLogins(phoneE164);

    // Issue initial session tokens (default 30-day refresh on initial registration)
    const tokens = await this.issueSessionTokens(user.id, user.phoneE164, true, data.deviceInfo, data.ipAddress);


    return {
      user: this.sanitizeUser(user),
      tokens,
    };
  }


  // ==========================================
  // 2. LOGIN FLOW
  // ==========================================

  public async login(data: {
    phone: string;
    password: string;
    rememberMe?: boolean;
    deviceInfo?: string;
    ipAddress?: string;
  }): Promise<{ user: UserResponse; tokens: AuthTokens }> {
    const phoneE164 = PhoneService.normalizeToE164(data.phone);

    // Check account lockout status
    const loginAttempt = await db.getLoginAttempt(phoneE164);
    const now = Date.now();
    if (loginAttempt?.lockedUntil && loginAttempt.lockedUntil > now) {
      const remainingSeconds = Math.ceil((loginAttempt.lockedUntil - now) / 1000);
      const remainingMinutes = Math.ceil(remainingSeconds / 60);
      throw {
        status: 423,
        message: `Account is temporarily locked due to repeated failed login attempts. Please try again in ${remainingMinutes} minute${remainingMinutes === 1 ? '' : 's'}.`,
        retryAfter: remainingSeconds,
      };
    }

    const user = await db.findUserByPhone(phoneE164);

    // Generic error to prevent account enumeration scraping
    const genericAuthError = {
      status: 401,
      message: 'Invalid mobile number or password.',
    };

    if (!user) {
      // Execute dummy password verification against 12-round bcrypt hash to ensure identical response timing (~200ms)
      await CryptoService.dummyPasswordCompare(data.password);
      const attemptResult = await db.recordFailedLogin(
        phoneE164,
        config.security.maxLoginAttempts,
        config.security.lockoutDurationSeconds * 1000
      );

      if (attemptResult.isLocked) {
        const lockoutMinutes = Math.ceil(config.security.lockoutDurationSeconds / 60);
        throw {
          status: 423,
          message: `Too many failed login attempts. Your account has been temporarily locked for ${lockoutMinutes} minutes.`,
          retryAfter: config.security.lockoutDurationSeconds,
        };
      }

      throw genericAuthError;
    }

    // Verify password hash
    const isPasswordCorrect = await CryptoService.comparePassword(data.password, user.passwordHash);
    if (!isPasswordCorrect) {
      const attemptResult = await db.recordFailedLogin(
        phoneE164,
        config.security.maxLoginAttempts,
        config.security.lockoutDurationSeconds * 1000
      );

      if (attemptResult.isLocked) {
        const lockoutMinutes = Math.ceil(config.security.lockoutDurationSeconds / 60);
        throw {
          status: 423,
          message: `Too many failed login attempts. Your account has been temporarily locked for ${lockoutMinutes} minutes.`,
          retryAfter: config.security.lockoutDurationSeconds,
        };
      }

      throw genericAuthError;
    }

    // Check if user account is active / suspended (checked AFTER password check to eliminate enumeration oracle)
    if (!user.isActive) {
      throw {
        status: 403,
        message: 'This account has been deactivated. Please contact RootU support.',
      };
    }


    // Reset failed login counter on success
    await db.resetFailedLogins(phoneE164);

    // Issue access and rotating refresh tokens
    const tokens = await this.issueSessionTokens(
      user.id,
      user.phoneE164,
      Boolean(data.rememberMe),
      data.deviceInfo,
      data.ipAddress
    );

    return {
      user: this.sanitizeUser(user),
      tokens,
    };
  }

  // ==========================================
  // 3. REFRESH TOKEN ROTATION & BREACH DETECTION
  // ==========================================

  public async refreshTokens(
    rawRefreshToken: string,
    deviceInfo?: string,
    ipAddress?: string
  ): Promise<AuthTokens> {
    const tokenHash = CryptoService.hashToken(rawRefreshToken);
    const rotation = await db.rotateRefreshToken(tokenHash);

    if (rotation.status === 'not_found' || !rotation.record) {
      throw { status: 401, message: 'Invalid refresh token.' };
    }

    // Check expiration
    if (new Date() > rotation.record.expiresAt) {
      throw { status: 401, message: 'Refresh token has expired. Please log in again.' };
    }

    // CRITICAL BREACH DETECTION: If a revoked token is used, assume token theft!
    // Invalidate all tokens for this user immediately!
    if (rotation.status === 'revoked') {
      await db.revokeAllUserTokens(rotation.record.userId);
      throw {
        status: 401,
        message: 'Security Alert: Compromised session detected. All active sessions have been terminated. Please log in again.',
      };
    }

    // Find user
    const user = await db.findUserById(rotation.record.userId);
    if (!user || !user.isActive) {
      throw { status: 401, message: 'User account is inactive or not found.' };
    }

    // Issue new pair (rotating token)
    return this.issueSessionTokens(user.id, user.phoneE164, true, deviceInfo, ipAddress);
  }


  // ==========================================
  // 4. FORGOT PASSWORD FLOW
  // ==========================================

  public async sendForgotPasswordOtp(rawPhone: string): Promise<{ success: boolean; message: string; cooldownSeconds: number }> {
    const phoneE164 = PhoneService.normalizeToE164(rawPhone);

    // Server-side 60s cooldown check
    const existingOtp = await db.getOtp(phoneE164, 'forgot_password');
    const now = Date.now();
    if (existingOtp && existingOtp.cooldownUntil > now) {
      const remainingSeconds = Math.ceil((existingOtp.cooldownUntil - now) / 1000);
      throw {
        status: 429,
        message: `Please wait ${remainingSeconds} seconds before requesting a new reset code.`,
        retryAfter: remainingSeconds,
      };
    }

    // Anti-SMS Toll Fraud: Enforce hourly rate limit per phone number
    const rateLimit = await db.checkAndRecordOtpRateLimit(
      phoneE164,
      config.security.maxOtpRequestsPerPhonePerHour
    );
    if (!rateLimit.allowed) {
      throw {
        status: 429,
        message: `Too many verification code requests for this mobile number. Please try again in ${Math.ceil(rateLimit.retryAfterSeconds / 60)} minutes.`,
        retryAfter: rateLimit.retryAfterSeconds,
      };
    }

    // Look up user
    const user = await db.findUserByPhone(phoneE164);

    // ANTI-ENUMERATION: Always return the exact same generic message whether user exists or not!
    const genericResponse = {
      success: true,
      message: 'If this mobile number is registered with RootU, a password reset code has been sent.',
      cooldownSeconds: config.security.otpCooldownSeconds,
    };

    if (!user) {
      // Place unregistered number on uniform cooldown so direct repetitive calls receive 429,
      // preventing attackers from distinguishing registered vs unregistered numbers.
      await db.setOtp({
        phoneE164,
        otpHash: 'dummy-enumeration-prevention-hash',
        purpose: 'forgot_password',
        attempts: 0,
        maxAttempts: config.security.maxOtpVerifyAttempts,
        expiresAt: now + config.security.otpExpirySeconds * 1000,
        cooldownUntil: now + config.security.otpCooldownSeconds * 1000,
        createdAt: now,
      });
      return genericResponse;
    }

    // Generate secure OTP
    let otp = CryptoService.generateSecureOtp(config.security.otpLength);

    const sendResult = await this.smsGateway.sendOtp(phoneE164, otp, 'forgot_password');
    const sent = typeof sendResult === 'boolean' ? sendResult : sendResult?.success;

    if (sent) {
      if (typeof sendResult === 'object' && sendResult?.dispatchedOtp) {
        otp = sendResult.dispatchedOtp;
      }
      const otpHash = CryptoService.hashOtp(otp, phoneE164);

      await db.setOtp({
        phoneE164,
        otpHash,
        purpose: 'forgot_password',
        attempts: 0,
        maxAttempts: config.security.maxOtpVerifyAttempts,
        expiresAt: now + config.security.otpExpirySeconds * 1000,
        cooldownUntil: now + config.security.otpCooldownSeconds * 1000,
        createdAt: now,
      });
    }

    return genericResponse;
  }

  public async verifyForgotPasswordOtp(
    rawPhone: string,
    candidateOtp: string
  ): Promise<{ success: boolean; verificationToken: string; message: string }> {
    const phoneE164 = PhoneService.normalizeToE164(rawPhone);

    const otpRecord = await db.getOtp(phoneE164, 'forgot_password');
    if (!otpRecord) {
      throw {
        status: 400,
        message: 'Invalid or expired password reset code. Please request a new code.',
      };
    }

    const isValid = CryptoService.verifyOtpHash(candidateOtp, phoneE164, otpRecord.otpHash);

    if (!isValid) {
      const attempts = await db.incrementOtpAttempt(phoneE164, 'forgot_password');
      if (attempts >= otpRecord.maxAttempts) {
        throw {
          status: 400,
          message: 'Too many failed verification attempts. This code has been invalidated. Please request a new code.',
        };
      }
      const remaining = otpRecord.maxAttempts - attempts;
      throw {
        status: 400,
        message: `Invalid reset code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`,
      };
    }

    // Atomically burn OTP immediately upon success to eliminate replay and concurrent race attacks
    const burned = await db.burnOtp(phoneE164, 'forgot_password');
    if (!burned) {
      throw {
        status: 400,
        message: 'Invalid or expired password reset code. Please request a new code.',
      };
    }

    // Issue short-lived verification token bound to password_reset
    const verificationToken = TokenService.signVerificationToken(phoneE164, 'password_reset');

    return {
      success: true,
      verificationToken,
      message: 'Code verified successfully. You may now set a new password.',
    };
  }

  public async resetPassword(data: {
    verificationToken: string;
    phone: string;
    newPassword: string;
  }): Promise<{ success: boolean; message: string }> {
    const phoneE164 = PhoneService.normalizeToE164(data.phone);

    // Cryptographic validation of verification token
    let tokenPayload: any;
    try {
      tokenPayload = TokenService.verifyVerificationToken(data.verificationToken, phoneE164, 'password_reset');
    } catch (err: any) {
      throw {
        status: 401,
        message: 'Password reset authorization failed: Invalid or expired token.',
      };
    }

    const user = await db.findUserByPhone(phoneE164);
    if (!user) {
      throw { status: 404, message: 'User account not found.' };
    }

    // Single-use token enforcement: Atomic consumption prevents verification token replay attacks
    const claimed = await db.consumeVerificationTokenOnce(tokenPayload.jti);
    if (!claimed) {
      throw {
        status: 401,
        message: 'Password reset authorization failed: Verification token has already been used.',
      };
    }

    // Hash new password with bcrypt work factor 12
    const newPasswordHash = await CryptoService.hashPassword(data.newPassword);
    await db.updatePassword(user.id, newPasswordHash);


    // CRITICAL SECURITY REQUIREMENT:
    // When password is reset, immediately revoke ALL existing active sessions and refresh tokens!
    const revokedCount = await db.revokeAllUserTokens(user.id);

    // Reset any failed login counters
    await db.resetFailedLogins(phoneE164);

    return {
      success: true,
      message: `Password reset successfully. ${revokedCount} active session${revokedCount === 1 ? '' : 's'} logged out. Please log in with your new password.`,
    };
  }


  // ==========================================
  // 5. LOGOUT
  // ==========================================

  public async logout(rawRefreshToken: string): Promise<{ success: boolean; message: string }> {
    if (rawRefreshToken) {
      const tokenHash = CryptoService.hashToken(rawRefreshToken);
      await db.revokeRefreshToken(tokenHash);
    }
    return { success: true, message: 'Logged out successfully.' };
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  private async issueSessionTokens(
    userId: string,
    phoneE164: string,
    rememberMe: boolean,
    deviceInfo?: string,
    ipAddress?: string
  ): Promise<AuthTokens> {
    const accessToken = TokenService.signAccessToken(userId, phoneE164);
    const rawRefreshToken = CryptoService.generateRandomToken(48);
    const tokenHash = CryptoService.hashToken(rawRefreshToken);

    const expiryDays = rememberMe ? 30 : 1;
    const expiresAt = new Date(Date.now() + expiryDays * 24 * 60 * 60 * 1000);

    await db.createRefreshToken({
      userId,
      tokenHash,
      expiresAt,
      deviceInfo,
      ipAddress,
    });

    return {
      accessToken,
      refreshToken: rawRefreshToken,
      expiresIn: 900, // 15 minutes in seconds
    };
  }

  private sanitizeUser(user: UserRecord): UserResponse {
    return {
      id: user.id,
      phoneE164: user.phoneE164,
      fullName: user.fullName,
      createdAt: user.createdAt,
    };
  }
}

// Global Singleton Auth Service
export const authService = new AuthService();

