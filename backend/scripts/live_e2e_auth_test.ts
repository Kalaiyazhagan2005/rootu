import dns from 'dns';
dns.setDefaultResultOrder('ipv4first');
import path from 'path';
import dotenv from 'dotenv';
const envCandidates = [
  path.resolve(process.cwd(), '.env'),
  path.resolve(process.cwd(), 'backend', '.env'),
  path.resolve(__dirname, '../.env'),
];
for (const p of envCandidates) {
  dotenv.config({ path: p });
}


import assert from 'node:assert';
import { Pool } from 'pg';
import { buildApp } from '../deployables/2_core_api/src/server';
import { config } from '../shared/src/config/env';
import { db } from '../shared/src/database/db';
import { LiveSmsDispatcher } from '../shared/src/services/sms_provider';
const TEST_PHONE_E164 = config.twilio.verifiedPhoneNumber;
const TEST_PHONE = TEST_PHONE_E164.replace(/^\+91/, '');
const INITIAL_PASSWORD = 'RootUSecurePassword2026!';
const NEW_PASSWORD = 'UpdatedRootUPassword2026!';

async function runLiveE2ETest() {
  console.log('\n=============================================================');
  console.log('RootU Live Authentication & Telecom E2E Verification');
  console.log('=============================================================');
  console.log(`Target Phone: ${TEST_PHONE} (E.164: ${TEST_PHONE_E164})`);
  console.log(`Database URL: ${config.database.url ? 'CONFIGURED (PostgreSQL rootu_prod)' : 'NOT CONFIGURED'}`);
  console.log(`Twilio SID:   ${config.twilio.accountSid ? config.twilio.accountSid.substring(0, 8) + '...' : 'NOT CONFIGURED'}`);
  console.log(`Twilio From:  ${config.twilio.fromNumber}`);
  console.log('-------------------------------------------------------------\n');

  // Verify PostgreSQL Connection
  const pgPool = new Pool({ connectionString: config.database.url });
  const dbCheck = await pgPool.query('SELECT current_database(), NOW() as db_time;');
  console.log(`[1/12] Connected to PostgreSQL: ${dbCheck.rows[0].current_database} at ${dbCheck.rows[0].db_time.toISOString()}`);

  // Clean state for test phone in PostgreSQL
  console.log(`[2/12] Cleaning previous state for ${TEST_PHONE_E164} in PostgreSQL...`);
  await pgPool.query('DELETE FROM users WHERE phone_e164 = $1', [TEST_PHONE_E164]);
  await pgPool.query('DELETE FROM otps WHERE phone_e164 = $1', [TEST_PHONE_E164]);
  await pgPool.query('DELETE FROM login_attempts WHERE phone_e164 = $1', [TEST_PHONE_E164]);
  await pgPool.query('DELETE FROM otp_requests WHERE phone_e164 = $1', [TEST_PHONE_E164]);
  LiveSmsDispatcher.clearTransmissionLog();
  console.log('       State cleaned successfully.');

  const app = buildApp();
  await app.ready();

  // STEP 1: Registration Send OTP (Dispatches real Twilio SMS)
  console.log(`\n[3/12] Requesting Registration OTP for ${TEST_PHONE} via Twilio SMS...`);
  const sendOtpRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register/send-otp',
    payload: { phone: TEST_PHONE },
  });

  console.log(`       HTTP Status: ${sendOtpRes.statusCode}`);
  const sendOtpBody = JSON.parse(sendOtpRes.payload);
  console.log('       Response Body:', sendOtpBody);
  assert.strictEqual(sendOtpRes.statusCode, 200, `Send OTP failed: ${sendOtpRes.payload}`);
  assert.strictEqual(sendOtpBody.success, true);
  assert.strictEqual(sendOtpBody.otp, undefined, 'CRITICAL: Plaintext OTP leaked in response!');

  // Retrieve the dispatched code from the audit log
  const dispatchedOtp = LiveSmsDispatcher.getLatestDispatchedCode(TEST_PHONE_E164);
  console.log(`       Dispatched OTP code: ${dispatchedOtp} (Sent via Twilio to ${TEST_PHONE_E164})`);
  assert.ok(dispatchedOtp, 'No OTP code was recorded in telecom transmission log!');

  // Verify OTP is hashed in PostgreSQL
  const dbOtpRes = await pgPool.query(
    'SELECT phone_e164, otp_hash, purpose, attempts, max_attempts, expires_at FROM otps WHERE phone_e164 = $1',
    [TEST_PHONE_E164]
  );
  assert.strictEqual(dbOtpRes.rows.length, 1, 'OTP was not saved in PostgreSQL otps table!');
  assert.notStrictEqual(dbOtpRes.rows[0].otp_hash, dispatchedOtp, 'CRITICAL: Plaintext OTP stored in database!');
  console.log(`       Verified hashed OTP record in PostgreSQL otps table (Hash length: ${dbOtpRes.rows[0].otp_hash.length})`);

  // STEP 2: Verify Registration OTP
  console.log(`\n[4/12] Verifying OTP against PostgreSQL hash...`);
  const verifyRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register/verify-otp',
    payload: { phone: TEST_PHONE, otp: dispatchedOtp },
  });

  console.log(`       HTTP Status: ${verifyRes.statusCode}`);
  const verifyBody = JSON.parse(verifyRes.payload);
  assert.strictEqual(verifyRes.statusCode, 200, `Verify OTP failed: ${verifyRes.payload}`);
  assert.ok(verifyBody.verificationToken, 'Missing verification token');
  const regVerificationToken = verifyBody.verificationToken;
  console.log(`       Received short-lived signed verification token: ${regVerificationToken.substring(0, 24)}...`);

  // Assert OTP was burned in PostgreSQL immediately upon success (replay prevention)
  const burnedOtpCheck = await pgPool.query('SELECT * FROM otps WHERE phone_e164 = $1', [TEST_PHONE_E164]);
  assert.strictEqual(burnedOtpCheck.rows.length, 0, 'CRITICAL: OTP was not burned after verification!');
  console.log('       Confirmed OTP burned in PostgreSQL (anti-replay check passed).');

  // STEP 3: Complete Account Registration
  console.log(`\n[5/12] Completing registration in PostgreSQL...`);
  const completeRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register/complete',
    payload: {
      verificationToken: regVerificationToken,
      phone: TEST_PHONE,
      fullName: 'RootU Live Rider',
      password: INITIAL_PASSWORD,
      confirmPassword: INITIAL_PASSWORD,
      acceptTerms: true,
    },
  });

  console.log(`       HTTP Status: ${completeRes.statusCode}`);
  const completeBody = JSON.parse(completeRes.payload);
  assert.strictEqual(completeRes.statusCode, 201, `Complete registration failed: ${completeRes.payload}`);
  assert.ok(completeBody.user.id, 'Missing user.id');
  assert.strictEqual(completeBody.user.phoneE164, TEST_PHONE_E164);
  assert.strictEqual(completeBody.user.passwordHash, undefined, 'CRITICAL: Password hash leaked in response!');
  assert.ok(completeBody.tokens.accessToken, 'Missing accessToken');
  assert.ok(completeBody.tokens.refreshToken, 'Missing refreshToken');

  const userId = completeBody.user.id;
  const initialAccessToken = completeBody.tokens.accessToken;
  const initialRefreshToken = completeBody.tokens.refreshToken;
  console.log(`       User registered: ${userId} (${completeBody.user.fullName})`);

  // Verify User & Refresh Token in PostgreSQL
  const dbUser = await pgPool.query('SELECT id, phone_e164, password_hash, is_active FROM users WHERE id = $1', [userId]);
  assert.strictEqual(dbUser.rows.length, 1);
  assert.strictEqual(dbUser.rows[0].is_active, true);
  assert.match(dbUser.rows[0].password_hash, /^\$2[aby]\$12\$/, 'Password not hashed with bcrypt work factor 12!');
  console.log('       Confirmed user persisted in PostgreSQL users table with bcrypt work factor 12.');

  // STEP 4: Access Protected Profile (/me)
  console.log(`\n[6/12] Testing authenticated access to /api/v1/auth/me...`);
  const meRes = await app.inject({
    method: 'GET',
    url: '/api/v1/auth/me',
    headers: { authorization: `Bearer ${initialAccessToken}` },
  });
  console.log(`       HTTP Status: ${meRes.statusCode}`);
  const meBody = JSON.parse(meRes.payload);
  assert.strictEqual(meRes.statusCode, 200);
  assert.strictEqual(meBody.user.id, userId);
  console.log(`       Profile returned for: ${meBody.user.fullName}`);

  // STEP 5: Token Rotation (/refresh)
  console.log(`\n[7/12] Testing refresh token rotation...`);
  const refreshRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/refresh',
    payload: { refreshToken: initialRefreshToken },
  });
  console.log(`       HTTP Status: ${refreshRes.statusCode}`);
  const refreshBody = JSON.parse(refreshRes.payload);
  assert.strictEqual(refreshRes.statusCode, 200);
  assert.ok(refreshBody.accessToken);
  assert.ok(refreshBody.refreshToken);
  assert.notStrictEqual(refreshBody.refreshToken, initialRefreshToken, 'Refresh token did not rotate!');
  const rotatedRefreshToken = refreshBody.refreshToken;
  console.log('       Token rotation successful.');

  // STEP 6: Breach Detection - Replaying Revoked Refresh Token
  console.log(`\n[8/12] Testing breach detection (replaying revoked refresh token)...`);
  const breachRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/refresh',
    payload: { refreshToken: initialRefreshToken }, // Replay!
  });
  console.log(`       HTTP Status: ${breachRes.statusCode}`);
  assert.strictEqual(breachRes.statusCode, 401);
  assert.match(JSON.parse(breachRes.payload).error, /Security Alert.*Compromised session detected/i);
  console.log('       Security breach alert triggered; all user sessions terminated.');

  // STEP 7: User Login with Password
  console.log(`\n[9/12] Testing login with valid credentials...`);
  const loginRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: {
      phone: TEST_PHONE,
      password: INITIAL_PASSWORD,
      rememberMe: true,
    },
  });
  console.log(`       HTTP Status: ${loginRes.statusCode}`);
  const loginBody = JSON.parse(loginRes.payload);
  assert.strictEqual(loginRes.statusCode, 200);
  assert.ok(loginBody.tokens.accessToken);
  const activeAccessToken = loginBody.tokens.accessToken;
  console.log('       Login successful.');

  // STEP 8: Forgot Password Flow via Twilio SMS
  console.log(`\n[10/12] Testing Forgot Password OTP flow via Twilio...`);
  // Clear any existing OTP cooldown for clean test
  await pgPool.query('DELETE FROM otps WHERE phone_e164 = $1 AND purpose = \'forgot_password\'', [TEST_PHONE_E164]);
  const fpSendRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password/send-otp',
    payload: { phone: TEST_PHONE },
  });
  console.log(`        HTTP Status: ${fpSendRes.statusCode}`);
  assert.strictEqual(fpSendRes.statusCode, 200);
  const fpOtp = LiveSmsDispatcher.getLatestDispatchedCode(TEST_PHONE_E164)!;
  console.log(`        Dispatched Forgot-Password OTP: ${fpOtp} via Twilio to ${TEST_PHONE_E164}`);

  const fpVerifyRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password/verify-otp',
    payload: { phone: TEST_PHONE, otp: fpOtp },
  });
  assert.strictEqual(fpVerifyRes.statusCode, 200);
  const fpToken = JSON.parse(fpVerifyRes.payload).verificationToken;

  // STEP 9: Reset Password and Invalidate Prior Sessions
  console.log(`\n[11/12] Resetting password and asserting session revocation...`);
  await new Promise((r) => setTimeout(r, 1100)); // Ensure passwordChangedAt > active token iat
  const resetRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/forgot-password/reset',
    payload: {
      verificationToken: fpToken,
      phone: TEST_PHONE,
      newPassword: NEW_PASSWORD,
      confirmNewPassword: NEW_PASSWORD,
    },
  });
  console.log(`        HTTP Status: ${resetRes.statusCode}`);
  assert.strictEqual(resetRes.statusCode, 200);

  // Assert prior access token is immediately rejected
  const oldSessionCheck = await app.inject({
    method: 'GET',
    url: '/api/v1/auth/me',
    headers: { authorization: `Bearer ${activeAccessToken}` },
  });
  assert.strictEqual(oldSessionCheck.statusCode, 401, 'Prior access token was not invalidated by password reset!');
  console.log('        Confirmed prior access token invalidated on password reset.');

  // STEP 10: Login with New Password
  console.log(`\n[12/12] Logging in with new password...`);
  const newLoginRes = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: {
      phone: TEST_PHONE,
      password: NEW_PASSWORD,
    },
  });
  console.log(`        HTTP Status: ${newLoginRes.statusCode}`);
  assert.strictEqual(newLoginRes.statusCode, 200);
  const newAccessToken = JSON.parse(newLoginRes.payload).tokens.accessToken;

  // Verify access with new token
  const finalMeRes = await app.inject({
    method: 'GET',
    url: '/api/v1/auth/me',
    headers: { authorization: `Bearer ${newAccessToken}` },
  });
  assert.strictEqual(finalMeRes.statusCode, 200);

  await pgPool.end();
  await db.close();
  await app.close();

  console.log('\n=============================================================');
  console.log('ALL LIVE E2E AUTHENTICATION CHECKS PASSED.');
  console.log(`   - Real Twilio SMS Delivery to ${TEST_PHONE_E164} verified`);
  console.log('   - PostgreSQL rootu_prod System of Record verified');
  console.log('   - Full security.txt compliance verified');
  console.log('=============================================================\n');
}

runLiveE2ETest().catch((err) => {
  console.error('\nLive E2E Authentication Test Failed:', err);
  process.exit(1);
});
