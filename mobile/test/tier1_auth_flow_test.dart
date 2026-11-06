import 'package:flutter_test/flutter_test.dart';
import 'package:rootu_mobile/features/auth/services/auth_api_service.dart';

void main() {
  group('AuthApiService Configuration & Session Management Tests', () {
    setUp(() {
      AuthApiService.clearSession();
      AuthApiService.customBaseUrl = null;
    });

    test('Default baseUrl resolves and customBaseUrl overrides dynamically', () {
      expect(AuthApiService.baseUrl, contains('/api/v1/auth'));
      expect(AuthApiService.isAuthenticated, false);

      AuthApiService.customBaseUrl = 'https://api.rootu.app/api/v1/auth';
      expect(AuthApiService.baseUrl, equals('https://api.rootu.app/api/v1/auth'));
    });

    test('Token management correctly reflects authenticated session state', () {
      expect(AuthApiService.isAuthenticated, false);
      expect(AuthApiService.accessToken, isNull);
      expect(AuthApiService.refreshToken, isNull);

      AuthApiService.setTokens(
        accessToken: 'mock_jwt_access_token_15m',
        refreshToken: 'mock_refresh_token_string_48b',
      );

      expect(AuthApiService.isAuthenticated, true);
      expect(AuthApiService.accessToken, equals('mock_jwt_access_token_15m'));
      expect(AuthApiService.refreshToken, equals('mock_refresh_token_string_48b'));

      AuthApiService.clearSession();
      expect(AuthApiService.isAuthenticated, false);
      expect(AuthApiService.accessToken, isNull);
      expect(AuthApiService.refreshToken, isNull);
    });

    test('Password complexity verification rule validation', () {
      bool validatePassword(String pwd) {
        if (pwd.length < 8) return false;
        final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
        final hasLower = pwd.contains(RegExp(r'[a-z]'));
        final hasDigit = pwd.contains(RegExp(r'\d'));
        final hasSpecial = pwd.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{};\x27:"\\|,.<>\/?]'));
        return hasUpper && hasLower && hasDigit && hasSpecial;
      }

      // Valid passwords
      expect(validatePassword('StrongPass123!'), isTrue);
      expect(validatePassword('R00tU#Ride2026'), isTrue);

      // Invalid passwords
      expect(validatePassword('short1!'), isFalse); // < 8 chars
      expect(validatePassword('nouppercase123!'), isFalse); // no uppercase
      expect(validatePassword('NOLOWERCASE123!'), isFalse); // no lowercase
      expect(validatePassword('NoNumberSymbol!'), isFalse); // no number
      expect(validatePassword('NoSpecial12345'), isFalse); // no symbol
    });
  });
}
