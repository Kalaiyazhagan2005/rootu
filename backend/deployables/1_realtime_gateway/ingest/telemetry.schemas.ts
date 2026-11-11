import { z } from 'zod';

export const TelemetrySchema = z.object({
  latitude: z
    .number({ required_error: 'Latitude is required', invalid_type_error: 'Latitude must be a number' })
    .min(-90.0, 'Latitude must be between -90 and 90')
    .max(90.0, 'Latitude must be between -90 and 90'),
  longitude: z
    .number({ required_error: 'Longitude is required', invalid_type_error: 'Longitude must be a number' })
    .min(-180.0, 'Longitude must be between -180 and 180')
    .max(180.0, 'Longitude must be between -180 and 180'),
  speed: z
    .number({ required_error: 'Speed is required', invalid_type_error: 'Speed must be a number' })
    .min(0, 'Speed must be non-negative')
    .max(350, 'Speed exceeds physical limit for land vehicles'),
  heading: z
    .number({ required_error: 'Heading is required', invalid_type_error: 'Heading must be a number' })
    .min(0, 'Heading must be between 0 and 360')
    .max(360, 'Heading must be between 0 and 360'),
  altitude: z
    .number({ required_error: 'Altitude is required', invalid_type_error: 'Altitude must be a number' })
    .min(-500, 'Altitude below realistic minimum')
    .max(10000, 'Altitude exceeds realistic maximum'),
  accuracy: z
    .number({ required_error: 'Accuracy is required', invalid_type_error: 'Accuracy must be a number' })
    .min(0, 'Accuracy must be non-negative')
    .max(500, 'GPS accuracy uncertainty too high'),
  timestamp: z
    .number({ required_error: 'Timestamp is required', invalid_type_error: 'Timestamp must be epoch milliseconds' })
    .int('Timestamp must be integer epoch milliseconds'),
  tripId: z.string().uuid('Invalid Trip UUID').optional(),
});

export type ValidatedTelemetry = z.infer<typeof TelemetrySchema>;

export const JoinTripSchema = z.object({
  tripId: z.string().uuid('Invalid Trip UUID'),
});

export const LeaveTripSchema = z.object({
  tripId: z.string().uuid('Invalid Trip UUID'),
});

export const EmergencyBroadcastSchema = z.object({
  tripId: z.string().uuid('Invalid Trip UUID'),
  alertType: z.enum(['SOS', 'CRASH', 'PANIC']),
  details: z.string().max(500).optional(),
  location: z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
  }),
});

export const TeaBreakSchema = z.object({
  tripId: z.string().uuid('Invalid Trip UUID'),
  action: z.enum(['PROPOSED', 'STARTED', 'RESUMED']),
  proposedLocation: z
    .object({
      latitude: z.number().min(-90).max(90),
      longitude: z.number().min(-180).max(180),
      name: z.string().max(120).optional(),
    })
    .optional(),
});

