import { z } from 'zod';

// Strong password regex: min 8 chars, at least 1 uppercase, 1 lowercase, 1 number, 1 special character (max 72 chars to prevent bcrypt truncation)
const PASSWORD_REGEX = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]).{8,72}$/;

export const SendOtpSchema = z.object({
  phone: z.string().min(5, 'Phone number is too short').max(20, 'Phone number is too long'),
});

export const VerifyOtpSchema = z.object({
  phone: z.string().min(5).max(20),
  otp: z.string().regex(/^\d{6}$/, 'OTP must be a 6-digit numeric code'),
});

export const RegisterCompleteSchema = z.object({
  verificationToken: z.string().min(20, 'Missing or invalid verification token'),
  phone: z.string().min(5).max(20),
  fullName: z
    .string()
    .trim()
    .min(2, 'Full name must be at least 2 characters')
    .max(100, 'Full name cannot exceed 100 characters'),
  password: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .max(72, 'Password cannot exceed 72 characters')
    .regex(
      PASSWORD_REGEX,
      'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character'
    ),
  confirmPassword: z.string().min(1, 'Please confirm your password'),
  acceptTerms: z.literal(true, {
    errorMap: () => ({ message: 'You must accept the Terms and Privacy Policy to register' }),
  }),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});

export const LoginSchema = z.object({
  phone: z.string().min(5).max(20),
  password: z.string().min(1, 'Password is required'),
  rememberMe: z.boolean().optional().default(false),
});

export const RefreshTokenSchema = z.object({
  refreshToken: z.string().min(20, 'Refresh token is required'),
});

export const ForgotPasswordSendOtpSchema = z.object({
  phone: z.string().min(5).max(20),
});

export const ForgotPasswordResetSchema = z.object({
  verificationToken: z.string().min(20, 'Missing or invalid verification token'),
  phone: z.string().min(5).max(20),
  newPassword: z
    .string()
    .min(8, 'Password must be at least 8 characters')
    .max(72, 'Password cannot exceed 72 characters')
    .regex(
      PASSWORD_REGEX,
      'Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character'
    ),
  confirmNewPassword: z.string().min(1, 'Please confirm your new password'),
}).refine((data) => data.newPassword === data.confirmNewPassword, {
  message: 'Passwords do not match',
  path: ['confirmNewPassword'],
});

export const LogoutSchema = z.object({
  refreshToken: z.string().min(20, 'Invalid refresh token format').optional(),
});


