import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_config.dart';

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

  /// Production-ready single source of truth for the Auth API URL.
  /// Defined in AppConfig; can be set at build-time with `--dart-define=API_BASE_URL=...`
  static String get baseUrl => customBaseUrl ?? AppConfig.authBaseUrl;

  static const Duration requestTimeout = Duration(seconds: 10);

  static Future<http.Response> _post(String endpoint, Map<String, dynamic> body, {Map<String, String>? extraHeaders}) {
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json', ...?extraHeaders},
      body: jsonEncode(body),
    ).timeout(requestTimeout);
  }

  static Future<http.Response> _get(String endpoint, {Map<String, String>? headers}) {
    return http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    ).timeout(requestTimeout);
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
      final res = await _post('/register/send-otp', {'phone': phone});
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<String>> verifyRegistrationOtp(String phone, String otp) async {
    try {
      final res = await _post('/register/verify-otp', {'phone': phone, 'otp': otp});
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
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
      final res = await _post('/register/complete', {
        'verificationToken': verificationToken,
        'phone': phone,
        'fullName': fullName,
        'password': password,
        'confirmPassword': confirmPassword,
        'acceptTerms': acceptTerms,
      });
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<Map<String, dynamic>>> login({
    required String phone,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final res = await _post('/login', {
        'phone': phone,
        'password': password,
        'rememberMe': rememberMe,
      });
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<int>> sendForgotPasswordOtp(String phone) async {
    try {
      final res = await _post('/forgot-password/send-otp', {'phone': phone});
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<String>> verifyForgotPasswordOtp(String phone, String otp) async {
    try {
      final res = await _post('/forgot-password/verify-otp', {'phone': phone, 'otp': otp});
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<bool>> resetPassword({
    required String verificationToken,
    required String phone,
    required String newPassword,
    required String confirmNewPassword,
  }) async {
    try {
      final res = await _post('/forgot-password/reset', {
        'verificationToken': verificationToken,
        'phone': phone,
        'newPassword': newPassword,
        'confirmNewPassword': confirmNewPassword,
      });
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<bool>> logout() async {
    try {
      final token = _refreshToken;
      clearSession();
      if (token != null) {
        await _post('/logout', {'refreshToken': token});
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
      final res = await _get(
        '/me',
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }

  static Future<AuthApiResponse<bool>> refreshTokens() async {
    try {
      if (_refreshToken == null) {
        return AuthApiResponse(success: false, message: 'No refresh token available', statusCode: 401);
      }
      final res = await _post('/refresh', {'refreshToken': _refreshToken});
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
      return AuthApiResponse(success: false, message: 'Cannot reach server. Ensure backend is running.');
    }
  }
}
