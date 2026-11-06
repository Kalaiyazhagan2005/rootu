process.env.NODE_ENV = 'test';
import { describe, it, beforeEach, after } from 'node:test';
import assert from 'node:assert';
import { buildApp } from '../deployables/2_core_api/src/server';
import { db } from '../shared/src/database/db';
import { authService } from '../shared/src/services/auth.service';
import { LiveSmsDispatcher, TwilioSmsGateway } from '../shared/src/services/sms_provider';
import { CryptoService } from '../shared/src/services/crypto.service';
import { PhoneService } from '../shared/src/services/phone.service';

describe('RootU Authentication & Security Test Suite (OWASP / security.txt Compliance)', () => {
  const app = buildApp();

  beforeEach(async () => {
    await db.clearAll();
    LiveSmsDispatcher.clearTransmissionLog();
    authService.setSmsGateway(new LiveSmsDispatcher());
  });

  after(async () => {
    await db.close();
    await app.close();
  });



  // =========================================================================
  // 1. MULTI-STEP FLOW & STEP-BYPASS PREVENTION
  // =========================================================================
  it('SEC-01: Blocks step-bypass attacks (calling /register/complete without valid token)', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken: 'unverified.signature.unauthorized.token.payload.v1',
        phone: '+919876543210',
        fullName: 'Test Rider',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });

    assert.strictEqual(res.statusCode, 401);
    const body = JSON.parse(res.payload);
    assert.match(body.error, /Step-verification failed/i);
  });

  it('SEC-02: Blocks phone-number swapping attack in registration', async () => {
    // 1. Attacker verifies phone (+919876543210)
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone: '+919876543210' },
    });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode('+919876543210')!;

    const verifyRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone: '+919876543210', otp },
    });
    const { verificationToken } = JSON.parse(verifyRes.payload);

    // 2. Attacker attempts to swap payload phone to victim (+919999999999) using their token
    const swapRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone: '+919999999999', // Swapped victim's phone!
        fullName: 'Attacker Impersonator',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });

    assert.strictEqual(swapRes.statusCode, 401);
    const body = JSON.parse(swapRes.payload);
    assert.match(body.error, /Step-verification failed/i);
  });

  // =========================================================================
  // 2. OTP BRUTE-FORCE PROTECTION & EXPIRATION
  // =========================================================================
  it('SEC-03: Invalidates OTP after 3 failed brute-force attempts', async () => {
    const phone = '+919876543210';
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone },
    });
    const realOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;

    // Strike 1
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: '000000' },
    });
    assert.strictEqual(res1.statusCode, 400);
    assert.match(JSON.parse(res1.payload).error, /2 attempts remaining/i);

    // Strike 2
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: '111111' },
    });
    assert.strictEqual(res2.statusCode, 400);
    assert.match(JSON.parse(res2.payload).error, /1 attempt remaining/i);

    // Strike 3 - Invalidation threshold
    const res3 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: '222222' },
    });
    assert.strictEqual(res3.statusCode, 400);
    assert.match(JSON.parse(res3.payload).error, /invalidated for security/i);

    // Real OTP must now fail (burned)
    const res4 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: realOtp },
    });
    assert.strictEqual(res4.statusCode, 400);
    assert.match(JSON.parse(res4.payload).error, /Invalid or expired/i);
  });

  it('SEC-04: Prevents OTP replay attacks (burns OTP immediately upon first use)', async () => {
    const phone = '+919876543210';
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone },
    });
    const realOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;

    // First verification succeeds
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: realOtp },
    });
    assert.strictEqual(res1.statusCode, 200);

    // Replay attempt fails immediately
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone, otp: realOtp },
    });
    assert.strictEqual(res2.statusCode, 400);
    assert.match(JSON.parse(res2.payload).error, /Invalid or expired/i);
  });

  // =========================================================================
  // 3. SERVER-SIDE COOLDOWN & RATE LIMITING
  // =========================================================================
  it('SEC-05: Enforces strict 60-second cooldown on OTP requests (rejects SMS pumping)', async () => {
    const phone = '+919876543210';

    // 1st request succeeds
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone },
    });
    assert.strictEqual(res1.statusCode, 200);

    // Immediate 2nd request is blocked by server (not just frontend)
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone },
    });
    assert.strictEqual(res2.statusCode, 429);
    const body2 = JSON.parse(res2.payload);
    assert.match(body2.error, /Please wait \d+ seconds/i);
    assert.ok(body2.retryAfter > 0 && body2.retryAfter <= 60);
  });

  // =========================================================================
  // 4. PHONE NUMBER NORMALIZATION (E.164)
  // =========================================================================
  it('SEC-06: Normalizes varied phone formats to consistent E.164 format', async () => {
    const variations = [
      '98765 43210',
      '+91 98765-43210',
      '9876543210',
      '+919876543210',
    ];

    for (const raw of variations) {
      const normalized = PhoneService.normalizeToE164(raw);
      assert.strictEqual(normalized, '+919876543210');
    }
  });

  // =========================================================================
  // 5. ACCOUNT ENUMERATION MITIGATION
  // =========================================================================
  it('SEC-07: Mitigates account enumeration on login (returns generic message for both wrong phone and wrong password)', async () => {
    // 1. Wrong phone
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: {
        phone: '+919111122222',
        password: 'Password123!',
      },
    });
    assert.strictEqual(res1.statusCode, 401);
    assert.strictEqual(JSON.parse(res1.payload).error, 'Invalid mobile number or password.');

    // 2. Register valid user
    const phone = '+919876543210';
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const verifyRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(verifyRes.payload);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Valid Rider',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });

    // 3. Valid phone, but wrong password -> MUST return exact same generic message!
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: {
        phone,
        password: 'WrongPassword999!',
      },
    });
    assert.strictEqual(res2.statusCode, 401);
    assert.strictEqual(JSON.parse(res2.payload).error, 'Invalid mobile number or password.');
  });

  it('SEC-08: Mitigates account enumeration on forgot password (returns generic success regardless of phone existence)', async () => {
    // Non-registered number
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/send-otp',
      payload: { phone: '+919999900000' },
    });

    assert.strictEqual(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.match(body.message, /If this mobile number is registered with RootU/i);
    // Did NOT dispatch SMS to non-registered phone
    assert.strictEqual(LiveSmsDispatcher.getLatestDispatchedCode('+919999900000'), undefined);
  });

  // =========================================================================
  // 6. LOGIN RATE LIMITS & ACCOUNT LOCKOUT
  // =========================================================================
  it('SEC-09: Locks account after 5 consecutive failed login attempts', async () => {
    const phone = '+919876543210';

    // Register user
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const verifyRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(verifyRes.payload);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Target Account',
        password: 'CorrectPassword123!',
        confirmPassword: 'CorrectPassword123!',
        acceptTerms: true,
      },
    });

    // 4 failed attempts -> 401
    for (let i = 1; i <= 4; i++) {
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/login',
        payload: { phone, password: 'BadPassword!' },
      });
      assert.strictEqual(res.statusCode, 401);
    }

    // 5th failed attempt -> 423 Locked!
    const res5 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'BadPassword!' },
    });
    assert.strictEqual(res5.statusCode, 423);
    assert.match(JSON.parse(res5.payload).error, /locked/i);

    // Even with the CORRECT password, login is blocked while locked
    const resCorrect = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'CorrectPassword123!' },
    });
    assert.strictEqual(resCorrect.statusCode, 423);
    assert.match(JSON.parse(resCorrect.payload).error, /temporarily locked/i);
  });

  // =========================================================================
  // 7. PASSWORD RESET REVOKES ALL SESSIONS
  // =========================================================================
  it('SEC-10: Password reset immediately revokes all existing active refresh tokens & sessions', async () => {
    const phone = '+919876543210';

    // 1. Register user
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp1 = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes1 = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp: otp1 } });
    const { verificationToken: regToken } = JSON.parse(vRes1.payload);
    const regRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken: regToken,
        phone,
        fullName: 'Session User',
        password: 'OldPassword123!',
        confirmPassword: 'OldPassword123!',
        acceptTerms: true,
      },
    });
    const sessionToken1 = JSON.parse(regRes.payload).tokens.refreshToken;

    // 2. Login from second device
    const loginRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'OldPassword123!', rememberMe: true },
    });
    const sessionToken2 = JSON.parse(loginRes.payload).tokens.refreshToken;

    // Both refresh tokens are currently valid
    const refRes1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: sessionToken1 },
    });
    assert.strictEqual(refRes1.statusCode, 200);

    // 3. User performs forgot password reset
    // Advance cooldown for test
    await db.deleteOtp(phone, 'forgot_password');
    await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/send-otp', payload: { phone } });
    const resetOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;

    const vRes2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/verify-otp',
      payload: { phone, otp: resetOtp },
    });
    const { verificationToken: resetToken } = JSON.parse(vRes2.payload);

    const resetRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/reset',
      payload: {
        verificationToken: resetToken,
        phone,
        newPassword: 'BrandNewPassword123!',
        confirmNewPassword: 'BrandNewPassword123!',
      },
    });
    assert.strictEqual(resetRes.statusCode, 200);

    // 4. Verification: ALL prior refresh tokens must now be revoked!
    const testRevokedRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken: sessionToken2 },
    });
    assert.strictEqual(testRevokedRes.statusCode, 401);
  });

  // =========================================================================
  // 8. STRICT VALIDATION & LEAK PREVENTION
  // =========================================================================
  it('SEC-11: Validates password complexity strictly (rejects weak passwords)', async () => {
    const weakPasswords = [
      'short1!',           // too short
      'nouppercase123!',   // no uppercase
      'NOLOWERCASE123!',   // no lowercase
      'NoNumberSymbol!',   // no number
      'NoSpecial12345',    // no symbol
    ];

    for (const pwd of weakPasswords) {
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register/complete',
        payload: {
          verificationToken: 'unverified_token_signature_string',
          phone: '+919876543210',
          fullName: 'Test User',
          password: pwd,
          confirmPassword: pwd,
          acceptTerms: true,
        },
      });
      assert.strictEqual(res.statusCode, 400);
      const body = JSON.parse(res.payload);
      assert.match(body.details.join(' '), /password/i);
    }
  });

  it('SEC-12: Zero data leakage (never exposes OTP or password hashes in API responses)', async () => {
    // Send OTP response
    const otpRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone: '+919876543210' },
    });
    const otpBody = JSON.parse(otpRes.payload);
    assert.strictEqual(otpBody.otp, undefined);
    assert.strictEqual(otpBody.code, undefined);

    // Complete registration response
    const otp = LiveSmsDispatcher.getLatestDispatchedCode('+919876543210')!;
    const vRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/verify-otp',
      payload: { phone: '+919876543210', otp },
    });
    const { verificationToken } = JSON.parse(vRes.payload);

    const regRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone: '+919876543210',
        fullName: 'Clean User',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });

    const regBody = JSON.parse(regRes.payload);
    assert.strictEqual(regBody.user.passwordHash, undefined);
    assert.strictEqual(regBody.user.password, undefined);
  });

  // =========================================================================
  // 9. PRODUCTION TWILIO SMS GATEWAY INTEGRATION
  // =========================================================================
  it('SEC-13: Twilio SMS Gateway instantiates and verifies configuration parameters', async () => {
    // 1. Missing credentials returns isConfigured() === false
    const unconfiguredGateway = new TwilioSmsGateway('', '', '');
    assert.strictEqual(unconfiguredGateway.isConfigured(), false);

    // 2. Full credentials configure properly
    const configuredGateway = new TwilioSmsGateway('ACtest123', 'token123', '+1234567890');
    assert.strictEqual(configuredGateway.isConfigured(), true);

    // 3. Messaging Service SID also fulfills configuration
    const msgServiceGateway = new TwilioSmsGateway('ACtest123', 'token123', '', 'MGtest123');
    assert.strictEqual(msgServiceGateway.isConfigured(), true);

    // 4. Dispatch with missing credentials safely fails without throwing
    const res = await unconfiguredGateway.sendOtp('+919876543210', '123456', 'registration');
    assert.strictEqual(res, false);
  });

  it('SEC-14: Malformed or unparseable phone numbers return 400 Bad Request', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone: '0000000000' },
    });
    assert.strictEqual(res.statusCode, 400);
    const body = JSON.parse(res.payload);
    assert.match(body.error, /invalid phone number|normalization failed/i);
  });

  // =========================================================================
  // 10. REPLAY DEFENSE, ENUMERATION RESILIENCE & LIFECYCLE CONTROLS
  // =========================================================================
  it('SEC-15: Blocks single-use verification token replay attacks on password reset', async () => {
    const phone = '+919876543210';

    // 1. Register account
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const regOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes1 = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp: regOtp } });
    const { verificationToken: regToken } = JSON.parse(vRes1.payload);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken: regToken,
        phone,
        fullName: 'Replay Target',
        password: 'OriginalPassword123!',
        confirmPassword: 'OriginalPassword123!',
        acceptTerms: true,
      },
    });

    // 2. Request and verify password reset OTP
    await db.deleteOtp(phone, 'forgot_password');
    await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/send-otp', payload: { phone } });
    const resetOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes2 = await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/verify-otp', payload: { phone, otp: resetOtp } });
    const { verificationToken: resetToken } = JSON.parse(vRes2.payload);

    // 3. Legitimate reset using verification token succeeds
    const firstReset = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/reset',
      payload: {
        verificationToken: resetToken,
        phone,
        newPassword: 'FirstNewPassword123!',
        confirmNewPassword: 'FirstNewPassword123!',
      },
    });
    assert.strictEqual(firstReset.statusCode, 200);

    // 4. Attacker attempts to REPLAY the exact same verification token
    const replayReset = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/reset',
      payload: {
        verificationToken: resetToken, // REPLAY!
        phone,
        newPassword: 'AttackerPassword999!',
        confirmNewPassword: 'AttackerPassword999!',
      },
    });
    assert.strictEqual(replayReset.statusCode, 401);
    const body = JSON.parse(replayReset.payload);
    assert.match(body.error, /already been used/i);
  });

  it('SEC-16: Enforces hourly rate limiting per phone number against SMS toll fraud', async () => {
    const phone = '+919876543210';

    // 5 requests within an hour succeed
    for (let i = 1; i <= 5; i++) {
      await db.deleteOtp(phone, 'registration');
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/register/send-otp',
        payload: { phone },
      });
      assert.strictEqual(res.statusCode, 200);
    }

    // 6th request within the 1-hour window is strictly blocked by hourly rate limit
    await db.deleteOtp(phone, 'registration');
    const res6 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/send-otp',
      payload: { phone },
    });
    assert.strictEqual(res6.statusCode, 429);
    const body6 = JSON.parse(res6.payload);
    assert.match(body6.error, /Too many verification code requests/i);
  });

  it('SEC-17: Prevents account enumeration via forgot-password cooldown discrepancy', async () => {
    const unregisteredPhone = '+919999900000';

    // 1st request returns 200 with generic success message
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/send-otp',
      payload: { phone: unregisteredPhone },
    });
    assert.strictEqual(res1.statusCode, 200);

    // Immediate 2nd request for unregistered number MUST return 429 cooldown,
    // matching registered numbers to eliminate timing/cooldown enumeration oracle
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/send-otp',
      payload: { phone: unregisteredPhone },
    });
    assert.strictEqual(res2.statusCode, 429);
    const body2 = JSON.parse(res2.payload);
    assert.match(body2.error, /Please wait \d+ seconds/i);
  });

  it('SEC-18: Account lockout returns uniform 423 status on 5th strike for both existing and non-existing accounts', async () => {
    const unregisteredPhone = '+919999911111';

    // 4 failed attempts -> 401
    for (let i = 1; i <= 4; i++) {
      const res = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/login',
        payload: { phone: unregisteredPhone, password: 'BadPassword123!' },
      });
      assert.strictEqual(res.statusCode, 401);
    }

    // 5th failed attempt -> 423 Locked!
    const res5 = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone: unregisteredPhone, password: 'BadPassword123!' },
    });
    assert.strictEqual(res5.statusCode, 423);
    assert.match(JSON.parse(res5.payload).error, /locked/i);
  });

  it('SEC-19: Blocks deactivated / inactive user accounts from authenticating', async () => {
    const phone = '+919876543210';

    // 1. Register user
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(vRes.payload);
    const regRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Inactive Rider',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });
    const { accessToken, refreshToken } = JSON.parse(regRes.payload).tokens;

    // 2. Admin deactivates account in database
    await db.setUserActive(phone, false);


    // 3. Login attempt must be rejected with 403 Forbidden
    const loginRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'Password123!' },
    });
    assert.strictEqual(loginRes.statusCode, 403);
    assert.match(JSON.parse(loginRes.payload).error, /deactivated/i);

    // 4. Token refresh must be rejected
    const refreshRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refreshToken },
    });
    assert.strictEqual(refreshRes.statusCode, 401);

    // 5. Access to /me must be rejected with 403
    const meRes = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    assert.strictEqual(meRes.statusCode, 403);
  });

  it('SEC-20: Rejects access tokens issued prior to password reset', async () => {
    const phone = '+919876543210';

    // 1. Register user
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp1 = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes1 = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp: otp1 } });
    const { verificationToken: regToken } = JSON.parse(vRes1.payload);
    const regRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken: regToken,
        phone,
        fullName: 'Session Expiry User',
        password: 'OldPassword123!',
        confirmPassword: 'OldPassword123!',
        acceptTerms: true,
      },
    });
    const oldAccessToken = JSON.parse(regRes.payload).tokens.accessToken;

    // Access token is valid before reset
    const meRes1 = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me',
      headers: { authorization: `Bearer ${oldAccessToken}` },
    });
    assert.strictEqual(meRes1.statusCode, 200);

    // 2. Perform password reset (with small delay to ensure iat < passwordChangedAt)
    await new Promise((resolve) => setTimeout(resolve, 1100));
    await db.deleteOtp(phone, 'forgot_password');
    await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/send-otp', payload: { phone } });
    const resetOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes2 = await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/verify-otp', payload: { phone, otp: resetOtp } });
    const { verificationToken: resetToken } = JSON.parse(vRes2.payload);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/forgot-password/reset',
      payload: {
        verificationToken: resetToken,
        phone,
        newPassword: 'BrandNewPassword123!',
        confirmNewPassword: 'BrandNewPassword123!',
      },
    });

    // 3. Old access token MUST now be rejected with 401
    const meRes2 = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me',
      headers: { authorization: `Bearer ${oldAccessToken}` },
    });
    assert.strictEqual(meRes2.statusCode, 401);
    assert.match(JSON.parse(meRes2.payload).error, /Session invalidated due to password reset/i);
  });

  it('SEC-21: Blocks concurrent race-condition replay attacks on verification tokens (atomic claim)', async () => {
    const phone = '+919876543210';
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(vRes.payload);

    // Register user first so they exist
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Race Tester',
        password: 'Password123!',
        confirmPassword: 'Password123!',
        acceptTerms: true,
      },
    });

    // Obtain forgot-password token
    await db.deleteOtp(phone, 'forgot_password');
    await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/send-otp', payload: { phone } });
    const fpOtp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const fpVRes = await app.inject({ method: 'POST', url: '/api/v1/auth/forgot-password/verify-otp', payload: { phone, otp: fpOtp } });
    const { verificationToken: fpToken } = JSON.parse(fpVRes.payload);

    // Launch two parallel resets simultaneously with the identical verification token
    const [res1, res2] = await Promise.all([
      app.inject({
        method: 'POST',
        url: '/api/v1/auth/forgot-password/reset',
        payload: {
          verificationToken: fpToken,
          phone,
          newPassword: 'FirstParallelPassword1!',
          confirmNewPassword: 'FirstParallelPassword1!',
        },
      }),
      app.inject({
        method: 'POST',
        url: '/api/v1/auth/forgot-password/reset',
        payload: {
          verificationToken: fpToken,
          phone,
          newPassword: 'SecondParallelPassword2!',
          confirmNewPassword: 'SecondParallelPassword2!',
        },
      }),
    ]);

    // Exactly one must succeed (200) and the other must fail with 401 replay error
    const statuses = [res1.statusCode, res2.statusCode].sort();
    assert.deepStrictEqual(statuses, [200, 401], 'Concurrent race condition allowed multiple uses of single-use token!');
  });

  it('SEC-22: Logout endpoint validates input schema and rejects malformed payloads', async () => {
    // 1. Valid logout with string token
    const validRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: '1111222233334444555566667777888899990000' },
    });
    assert.strictEqual(validRes.statusCode, 200);

    // 2. Malformed non-string token payload rejected with 400 Validation Error
    const invalidRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      payload: { refreshToken: 12345 },
    });
    assert.strictEqual(invalidRes.statusCode, 400);
  });

  it('SEC-23: Inactive accounts reject wrong password with 401 instead of 403 (eliminates inactive account oracle)', async () => {
    const phone = '+919876543210';
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(vRes.payload);
    await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Inactive Oracle Rider',
        password: 'CorrectPassword123!',
        confirmPassword: 'CorrectPassword123!',
        acceptTerms: true,
      },
    });

    // Deactivate account
    await db.setUserActive(phone, false);

    // Wrong password -> MUST return 401 "Invalid mobile number or password." (NOT 403 deactivated)
    const wrongPwdRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'WrongPassword999!' },
    });
    assert.strictEqual(wrongPwdRes.statusCode, 401);
    assert.strictEqual(JSON.parse(wrongPwdRes.payload).error, 'Invalid mobile number or password.');

    // Correct password -> returns 403 deactivated
    const correctPwdRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'CorrectPassword123!' },
    });
    assert.strictEqual(correctPwdRes.statusCode, 403);
    assert.match(JSON.parse(correctPwdRes.payload).error, /deactivated/i);
  });

  // =========================================================================
  // 12. HARDENED BOUNDARY & CONCURRENCY CHECKS
  // =========================================================================
  it('SEC-24: Rejects passwords longer than 72 characters to eliminate bcrypt silent truncation vulnerabilities', async () => {
    const longPassword = 'A'.repeat(73) + 'Aa1!';
    const regRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken: 'dummy.token',
        phone: '+919876543210',
        fullName: 'Bcrypt Boundary Test',
        password: longPassword,
        confirmPassword: longPassword,
        acceptTerms: true,
      },
    });

    assert.strictEqual(regRes.statusCode, 400);
    const body = JSON.parse(regRes.payload);
    assert.match(body.details.join(' '), /cannot exceed 72 characters/i);
  });

  it('SEC-25: Registration automatically clears pre-registration lockout state so real user can log in immediately', async () => {
    const phone = '+919876543210';
    // Attacker brute-forces 5 times before user registers, causing lockout
    for (let i = 0; i < 5; i++) {
      await app.inject({
        method: 'POST',
        url: '/api/v1/auth/login',
        payload: { phone, password: 'WrongPassword123!' },
      });
    }

    // Assert that the phone is locked out
    const lockedRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'AnyPassword123!' },
    });
    assert.strictEqual(lockedRes.statusCode, 423);

    // Now real user registers
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;
    const vRes = await app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } });
    const { verificationToken } = JSON.parse(vRes.payload);

    const compRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register/complete',
      payload: {
        verificationToken,
        phone,
        fullName: 'Real Registered Rider',
        password: 'ValidSecurePassword123!',
        confirmPassword: 'ValidSecurePassword123!',
        acceptTerms: true,
      },
    });
    assert.strictEqual(compRes.statusCode, 201);

    // Real user logs in immediately with valid credentials — lockout must have been purged!
    const loginRes = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { phone, password: 'ValidSecurePassword123!' },
    });
    assert.strictEqual(loginRes.statusCode, 200, 'User should not be locked out after completing registration!');
  });

  it('SEC-26: Atomically burns OTP to prevent concurrent double-verification race conditions', async () => {
    const phone = '+919876543210';
    await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    const otp = LiveSmsDispatcher.getLatestDispatchedCode(phone)!;

    // Simulate 2 concurrent verification requests fired simultaneously
    const [res1, res2] = await Promise.all([
      app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } }),
      app.inject({ method: 'POST', url: '/api/v1/auth/register/verify-otp', payload: { phone, otp } }),
    ]);

    const statuses = [res1.statusCode, res2.statusCode].sort();
    assert.deepStrictEqual(statuses, [200, 400], 'Exactly one concurrent verification must succeed; second must be rejected');
  });

  it('SEC-27: Sets standard RFC-compliant Retry-After header on 429 and 423 responses', async () => {
    const phone = '+919876543210';
    // Send 1st OTP
    const res1 = await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    assert.strictEqual(res1.statusCode, 200);

    // Rapid 2nd OTP trigger within 60s cooldown -> 429 with Retry-After header
    const res2 = await app.inject({ method: 'POST', url: '/api/v1/auth/register/send-otp', payload: { phone } });
    assert.strictEqual(res2.statusCode, 429);
    assert.ok(res2.headers['retry-after'], 'Missing Retry-After HTTP header on 429 response');
    const retrySeconds = parseInt(res2.headers['retry-after'] as string, 10);
    assert.ok(retrySeconds > 0 && retrySeconds <= 60);
  });
});


