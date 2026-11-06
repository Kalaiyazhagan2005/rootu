# RootU

Travel safety and convoy coordination platform for mobile users across India.

## What it does

RootU provides real-time location tracking, route planning, geofence alarms, safe ride monitoring, and convoy coordination. Users authenticate via mobile number with OTP verification.

## Project structure

```
backend/          Node.js API server (Fastify + TypeScript)
mobile/           Flutter/Android mobile client
infrastructure/   Deployment configuration (placeholder)
```

### Backend

The backend is a Fastify HTTP server with PostgreSQL for persistent storage and Redis for caching and pub/sub.

**Auth endpoints** (`/api/v1/auth/`):
- `POST /register/send-otp` - Send OTP to mobile number
- `POST /register/verify-otp` - Verify OTP and get verification token
- `POST /register/complete` - Create account with password
- `POST /login` - Authenticate with mobile number and password
- `POST /refresh` - Rotate access and refresh tokens
- `POST /logout` - Revoke refresh token
- `POST /forgot-password/send-otp` - Send password reset OTP
- `POST /forgot-password/verify-otp` - Verify reset OTP
- `POST /forgot-password/reset` - Set new password
- `GET /me` - Get authenticated user profile

**Security measures:**
- Bcrypt password hashing (12 rounds)
- JWT access and refresh token rotation
- Atomic single-use verification tokens
- OTP brute-force protection (3 attempts)
- Account lockout after 5 failed logins
- Rate limiting per IP and per phone number
- Anti-enumeration timing-safe responses

### Mobile

Flutter application targeting Android and iOS. Features include map-based navigation with GPS Kalman filtering, route search via Nominatim, trip alarms, and the auth screens (login, registration, OTP verification, forgot password).

## Requirements

- Node.js 22+
- PostgreSQL 16+
- Redis 7+
- Flutter 3.0+
- Android SDK (for mobile builds)

## Setup

1. Copy `backend/.env.example` to `backend/.env` and fill in your credentials.
2. Install backend dependencies: `cd backend && npm install`
3. Run database migrations: `npm run migrate`
4. Start the server: `npm start`

## Testing

```
cd backend
npm test          # Run security and resilience test suites
npm run test:live # Run live E2E tests against real database and Twilio
```

## License

Private. All rights reserved.
