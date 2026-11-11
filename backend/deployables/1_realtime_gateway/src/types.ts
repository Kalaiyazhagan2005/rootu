import { WebSocket } from 'ws';

export interface TelemetryPayload {
  latitude: number;
  longitude: number;
  speed: number; // in km/h
  heading: number; // 0 - 360 degrees
  altitude: number; // in meters
  accuracy: number; // in meters
  timestamp: number; // epoch ms
  tripId?: string;
}

export type ClientMessageType =
  | 'auth'
  | 'telemetry'
  | 'trip:join'
  | 'trip:leave'
  | 'emergency:broadcast'
  | 'convoy:tea_break'
  | 'ping'
  | 'pong';

export interface ClientAuthMessage {
  type: 'auth';
  token: string;
}

export interface ClientTelemetryMessage {
  type: 'telemetry';
  data: TelemetryPayload;
}

export interface ClientTripJoinMessage {
  type: 'trip:join';
  tripId: string;
}

export interface ClientTripLeaveMessage {
  type: 'trip:leave';
  tripId: string;
}

export interface ClientEmergencyMessage {
  type: 'emergency:broadcast';
  tripId: string;
  alertType: 'SOS' | 'CRASH' | 'PANIC';
  details?: string;
  location: {
    latitude: number;
    longitude: number;
  };
}

export interface ClientTeaBreakMessage {
  type: 'convoy:tea_break';
  tripId: string;
  action: 'PROPOSED' | 'STARTED' | 'RESUMED';
  proposedLocation?: {
    latitude: number;
    longitude: number;
    name?: string;
  };
}

export interface ClientPingMessage {
  type: 'ping';
}

export interface ClientPongMessage {
  type: 'pong';
}

export type IncomingClientMessage =
  | ClientAuthMessage
  | ClientTelemetryMessage
  | ClientTripJoinMessage
  | ClientTripLeaveMessage
  | ClientEmergencyMessage
  | ClientTeaBreakMessage
  | ClientPingMessage
  | ClientPongMessage;

export interface ClientContext {
  socket: WebSocket;
  userId: string;
  phoneE164: string;
  isAlive: boolean;
  lastPingMs: number;
  authenticatedAt: number;
  joinedTrips: Set<string>;
  lastTelemetry?: {
    latitude: number;
    longitude: number;
    timestamp: number;
  };
}

export interface GatewayStats {
  activeConnections: number;
  activeUsers: number;
  activeTrips: number;
  queueLength: number;
  redisStatus: 'ready' | 'connecting' | 'fallback' | 'closed';
}

