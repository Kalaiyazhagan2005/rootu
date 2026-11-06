import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthApiResponse<T> {
  final bool success;
  final T? data;
  final String message;
  final int? retryAfterSeconds;
  final int? statusCode;

  AuthApiResponse({
    required this.success,
    this.data,
    required this.message,
    this.retryAfterSeconds,
    this.statusCode,
  });
}

class AuthApiService {
  static String? customBaseUrl;

  // 10.0.2.2 for Android emulator, 127.0.0.1 for desktop/web/iOS simulator
  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) return customBaseUrl!;
    if (kIsWeb) return 'http://127.0.0.1:3000/api/v1/auth';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000/api/v1/auth';
    return 'http://127.0.0.1:3000/api/v1/auth';
  }


  static String? _accessToken;
  static String? _refreshToken;

  static String? get accessToken => _accessToken;
  static String? get refreshToken => _refreshToken;
  static bool get isAuthenticated => _accessToken != null && _accessToken!.isNotEmpty;

  static void setTokens({String? accessToken, String? refreshToken}) {
    if (accessToken != null) _accessToken = accessToken;
    if (refreshToken != null) _refreshToken = refreshToken;
  }

  static void clearSession() {
    _accessToken = null;
    _refreshToken = null;
  }

  static Future<AuthApiResponse<int>> sendRegistrationOtp(String phone) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: json['cooldownSeconds'] as int? ?? 60,
          message: json['message'] ?? 'OTP sent',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          retryAfterSeconds: json['retryAfter'] as int?,
          message: json['error'] ?? 'Failed to send OTP',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<String>> verifyRegistrationOtp(String phone, String otp) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: json['verificationToken'] as String,
          message: json['message'] ?? 'Verified',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          message: json['error'] ?? 'Verification failed',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<Map<String, dynamic>>> completeRegistration({
    required String verificationToken,
    required String phone,
    required String fullName,
    required String password,
    required String confirmPassword,
    required bool acceptTerms,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'verificationToken': verificationToken,
          'phone': phone,
          'fullName': fullName,
          'password': password,
          'confirmPassword': confirmPassword,
          'acceptTerms': acceptTerms,
        }),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 201) {
        _accessToken = json['tokens']?['accessToken'];
        _refreshToken = json['tokens']?['refreshToken'];
        return AuthApiResponse(
          success: true,
          data: json,
          message: 'Account created successfully',
          statusCode: 201,
        );
      } else {
        final details = json['details'] != null ? (json['details'] as List).join(', ') : json['error'];
        return AuthApiResponse(
          success: false,
          message: details ?? 'Registration failed',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<Map<String, dynamic>>> login({
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'password': password,
          'rememberMe': rememberMe,
        }),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _accessToken = json['tokens']?['accessToken'];
        _refreshToken = json['tokens']?['refreshToken'];
        return AuthApiResponse(
          success: true,
          data: json,
          message: 'Logged in successfully',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          message: json['error'] ?? 'Login failed',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<int>> sendForgotPasswordOtp(String phone) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/forgot-password/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: json['cooldownSeconds'] as int? ?? 60,
          message: json['message'] ?? 'OTP sent if registered',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          retryAfterSeconds: json['retryAfter'] as int?,
          message: json['error'] ?? 'Failed to send reset code',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<String>> verifyForgotPasswordOtp(String phone, String otp) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/forgot-password/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: json['verificationToken'] as String,
          message: json['message'] ?? 'Code verified',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          message: json['error'] ?? 'Verification failed',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<bool>> resetPassword({
    required String verificationToken,
    required String phone,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/forgot-password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'verificationToken': verificationToken,
          'phone': phone,
          'newPassword': newPassword,
          'confirmNewPassword': confirmNewPassword,
        }),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: true,
          message: json['message'] ?? 'Password reset successfully',
          statusCode: 200,
        );
      } else {
        final details = json['details'] != null ? (json['details'] as List).join(', ') : json['error'];
        return AuthApiResponse(
          success: false,
          message: details ?? 'Password reset failed',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<bool>> logout() async {
    try {
      final token = _refreshToken;
      clearSession();
      if (token != null) {
        await http.post(
          Uri.parse('$baseUrl/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': token}),
        );
      }
      return AuthApiResponse(success: true, data: true, message: 'Logged out successfully', statusCode: 200);
    } catch (e) {
      clearSession();
      return AuthApiResponse(success: true, data: true, message: 'Logged out');
    }
  }

  static Future<AuthApiResponse<Map<String, dynamic>>> getProfile() async {
    try {
      if (_accessToken == null) {
        return AuthApiResponse(success: false, message: 'Not authenticated', statusCode: 401);
      }
      final res = await http.get(
        Uri.parse('$baseUrl/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_accessToken',
        },
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return AuthApiResponse(
          success: true,
          data: json['user'] as Map<String, dynamic>,
          message: 'Profile fetched',
          statusCode: 200,
        );
      } else {
        return AuthApiResponse(
          success: false,
          message: json['error'] ?? 'Failed to fetch profile',
          statusCode: res.statusCode,
        );
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }

  static Future<AuthApiResponse<bool>> refreshTokens() async {
    try {
      if (_refreshToken == null) {
        return AuthApiResponse(success: false, message: 'No refresh token available', statusCode: 401);
      }
      final res = await http.post(
        Uri.parse('$baseUrl/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );
      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _accessToken = json['accessToken'];
        _refreshToken = json['refreshToken'];
        return AuthApiResponse(success: true, data: true, message: 'Tokens refreshed', statusCode: 200);
      } else {
        clearSession();
        return AuthApiResponse(success: false, message: json['error'] ?? 'Session expired', statusCode: res.statusCode);
      }
    } catch (e) {
      return AuthApiResponse(success: false, message: 'Network error: $e');
    }
  }
}
