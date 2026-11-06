-- =========================================================================
-- ROOTU DATABASE INITIAL SCHEMA MIGRATION (001)
-- Target: PostgreSQL 16+ with PostGIS support
-- System of Record: Users, Auth Sessions, Convoys, Alarms, Safe Ride
-- =========================================================================

-- Enable UUID extension (built-in in Postgres 13+)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    terms_accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_e164);

-- 2. REFRESH TOKENS & ACTIVE SESSIONS
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL,
    device_info TEXT,
    ip_address VARCHAR(45),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);

-- 3. OTPS (HASHED STORAGE, STRICT EXPIRATION)
CREATE TABLE IF NOT EXISTS otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 VARCHAR(20) NOT NULL,
    otp_hash VARCHAR(64) NOT NULL,
    purpose VARCHAR(32) NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,
    expires_at TIMESTAMPTZ NOT NULL,
    cooldown_until TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otps_phone_purpose ON otps(phone_e164, purpose);

-- 4. LOGIN ATTEMPTS (BRUTE-FORCE & LOCKOUT PROTECTION)
CREATE TABLE IF NOT EXISTS login_attempts (
    phone_e164 VARCHAR(20) PRIMARY KEY,
    failed_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,
    last_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4b. CONSUMED VERIFICATION TOKENS (PREVENTS STEP-BYPASS & REPLAY ATTACKS)
CREATE TABLE IF NOT EXISTS consumed_verification_tokens (
    jti VARCHAR(64) PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_consumed_tokens_expiry ON consumed_verification_tokens(expires_at);

-- 4c. OTP REQUESTS RATE LIMIT (ANTI-SMS TOLL FRAUD HOURLY CAP)
CREATE TABLE IF NOT EXISTS otp_requests (
    id BIGSERIAL PRIMARY KEY,
    phone_e164 VARCHAR(20) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_otp_requests_phone_time ON otp_requests(phone_e164, requested_at DESC);

-- 5. CONVOYS & TRIPS
CREATE TABLE IF NOT EXISTS trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(120) NOT NULL,
    join_code VARCHAR(16) UNIQUE NOT NULL,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trip_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    role VARCHAR(20) NOT NULL DEFAULT 'RIDER',
    UNIQUE (trip_id, user_id)
);

-- 6. GEOFENCE ALARMS
CREATE TABLE IF NOT EXISTS geofence_alarms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    place_name VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION NOT NULL DEFAULT 1000.0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geofences_user ON geofence_alarms(user_id);

-- 7. SAFE RIDE SESSIONS (DEAD-MAN'S SWITCH / SWIPE-UP TEA BREAK)
CREATE TABLE IF NOT EXISTS safe_ride_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE',
    last_checkin_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    next_checkin_due_at TIMESTAMPTZ NOT NULL,
    emergency_contacts JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. GPS BREADCRUMBS (TIME-SERIES RIDER TRAILS)
CREATE TABLE IF NOT EXISTS breadcrumbs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    bearing_degrees DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_breadcrumbs_user_time ON breadcrumbs(user_id, recorded_at DESC);

