import path from 'path';
import dotenv from 'dotenv';

// Robust multi-path .env resolution supporting execution from repo root or backend subdir
const envCandidates = [
  path.resolve(process.cwd(), '.env'),
  path.resolve(process.cwd(), 'backend', '.env'),
  path.resolve(__dirname, '../../../.env'),
  path.resolve(__dirname, '../../../../.env'),
];
for (const envPath of envCandidates) {
  dotenv.config({ path: envPath });
}


export interface AppConfig {
  env: string;
  port: number;
  host: string;
  jwt: {
    accessSecret: string;
    accessExpiresIn: string; // e.g. "15m"
    refreshSecret: string;
    refreshExpiresInStandard: string; // e.g. "1d"
    refreshExpiresInRemember: string; // e.g. "30d"
    verificationSecret: string;
    verificationExpiresIn: string; // e.g. "10m"
  };
  security: {
    bcryptRounds: number;
    otpLength: number;
    otpExpirySeconds: number; // 300s = 5 minutes
    otpCooldownSeconds: number; // 60s cooldown
    maxOtpVerifyAttempts: number; // 3 strikes before invalidation
    maxLoginAttempts: number; // 5 failed attempts
    lockoutDurationSeconds: number; // 900s = 15 minutes
    maxOtpRequestsPerPhonePerHour: number;
    maxOtpRequestsPerIpPerHour: number;
  };
  twilio: {
    accountSid: string;
    authToken: string;
    fromNumber: string;
    messagingServiceSid?: string;
    verifyServiceSid?: string;
    verifiedPhoneNumber?: string;
  };
  redis: {
    url: string;
  };
  database: {
    url?: string;
  };
}

export const config: AppConfig = {
  get env() {
    return process.env.NODE_ENV || 'development';
  },
  port: parseInt(process.env.PORT || '3000', 10),
  host: process.env.HOST || '0.0.0.0',
  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET || 'rootu-production-access-secret-minimum-32-chars-long!',
    accessExpiresIn: '15m',
    refreshSecret: process.env.JWT_REFRESH_SECRET || 'rootu-production-refresh-secret-minimum-32-chars-long!',
    refreshExpiresInStandard: '1d',
    refreshExpiresInRemember: '30d',
    verificationSecret: process.env.JWT_VERIFICATION_SECRET || 'rootu-verification-step-bypass-secret-32-chars!',
    verificationExpiresIn: '10m',
  },
  security: {
    bcryptRounds: parseInt(process.env.BCRYPT_ROUNDS || '12', 10),
    otpLength: 6,
    otpExpirySeconds: 300, // 5 minutes
    otpCooldownSeconds: 60, // 60 seconds
    maxOtpVerifyAttempts: 3, // 3 failed attempts invalidates OTP
    maxLoginAttempts: 5, // 5 failed logins triggers account lockout
    lockoutDurationSeconds: 900, // 15 minutes lockout
    maxOtpRequestsPerPhonePerHour: 5,
    maxOtpRequestsPerIpPerHour: 20,
  },
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID || '',
    authToken: process.env.TWILIO_AUTH_TOKEN || '',
    fromNumber: process.env.TWILIO_FROM_NUMBER || '',
    messagingServiceSid: process.env.TWILIO_MESSAGING_SERVICE_SID,
    verifyServiceSid: process.env.TWILIO_VERIFY_SERVICE_SID,
    verifiedPhoneNumber: process.env.TWILIO_VERIFIED_PHONE || '',
  },
  redis: {
    url: process.env.REDIS_URL || 'redis://127.0.0.1:6379',
  },
  database: {
    url: process.env.DATABASE_URL,
  },
};

