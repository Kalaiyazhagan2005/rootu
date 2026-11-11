import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rootu_mobile/features/auth/login_screen.dart';
import 'package:rootu_mobile/features/auth/registration_screen.dart';
import 'package:rootu_mobile/features/auth/otp_verification_screen.dart';
import 'package:rootu_mobile/features/auth/forgot_password_screen.dart';

void main() {
  group('Auth Screens Wireframe & Form Interaction Tests', () {
    testWidgets('LoginScreen renders wireframe elements and handles input validation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      // Verify basic wireframe structure
      expect(find.text('Login'), findsNWidgets(2)); // AppBar and Button
      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Mobile & Password
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);

      // Submit empty form to trigger validation error
      final loginBtn = find.widgetWithText(ElevatedButton, 'Login');
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter both mobile number and password'), findsOneWidget);

      // Enter short mobile and password to trigger phone validation
      await tester.enterText(find.byType(TextField).at(0), '123');
      await tester.enterText(find.byType(TextField).at(1), 'Secret123!');
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid mobile number'), findsOneWidget);

      // Enter valid mobile and password
      await tester.enterText(find.byType(TextField).at(0), '9876543210');
      await tester.pump();

      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Secret123!'), findsOneWidget);

      // Toggle remember me checkbox
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    });

    testWidgets('RegistrationScreen renders wireframe fields and performs validation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegistrationScreen(),
        ),
      );

      // Verify fields
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4)); // Name, Phone, Pwd, ConfirmPwd
      expect(find.byType(Checkbox), findsOneWidget); // Terms checkbox
      final regBtn = find.widgetWithText(ElevatedButton, 'Register');
      expect(regBtn, findsOneWidget);

      // Attempt submit empty
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      expect(find.text('All fields are required'), findsOneWidget);

      // Short full name (< 2 chars)
      await tester.enterText(find.byType(TextField).at(0), 'J');
      await tester.enterText(find.byType(TextField).at(1), '9876543210');
      await tester.enterText(find.byType(TextField).at(2), 'Pass123!');
      await tester.enterText(find.byType(TextField).at(3), 'Pass123!');
      await tester.ensureVisible(regBtn);
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      expect(find.text('Full name must be at least 2 characters'), findsOneWidget);

      // Short phone (< 5 chars)
      await tester.enterText(find.byType(TextField).at(0), 'John Doe');
      await tester.enterText(find.byType(TextField).at(1), '123');
      await tester.ensureVisible(regBtn);
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid mobile number'), findsOneWidget);

      // Enter fields with mismatched passwords
      await tester.enterText(find.byType(TextField).at(1), '9876543210');
      await tester.enterText(find.byType(TextField).at(2), 'Pass123!');
      await tester.enterText(find.byType(TextField).at(3), 'Different123!');
      await tester.ensureVisible(regBtn);
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);

      // Matching passwords but weak
      await tester.enterText(find.byType(TextField).at(3), 'Pass123!');
      await tester.ensureVisible(regBtn);
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      // Terms not accepted
      expect(find.text('You must accept the Terms & Privacy Policy to continue'), findsOneWidget);

      // Excessively long password (> 72 chars)
      final termsBox = find.byType(Checkbox);
      await tester.ensureVisible(termsBox);
      await tester.tap(termsBox);
      await tester.pump();

      final longPwd = 'A' * 70 + '1!a'; // 73 chars
      await tester.enterText(find.byType(TextField).at(2), longPwd);
      await tester.enterText(find.byType(TextField).at(3), longPwd);
      await tester.ensureVisible(regBtn);
      await tester.tap(regBtn);
      await tester.pumpAndSettle();
      expect(find.text('Password cannot exceed 72 characters'), findsOneWidget);
    });

    testWidgets('OtpVerificationScreen displays phone, 6-digit textfield, and countdown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpVerificationScreen(
            mobileNumber: '9876543210',
            initialCooldownSeconds: 60,
          ),
        ),
      );

      expect(find.text('Enter Verification Code'), findsOneWidget);
      expect(find.textContaining('9876543210'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Verify & Proceed'), findsOneWidget);

      // Verifies accurate timer format: 60s formats as "1:00", not "0:60"
      expect(find.text('Resend code in 1:00'), findsOneWidget);

      // Attempt verify with short OTP
      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify & Proceed'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter all 6 digits of your verification code'), findsOneWidget);
    });

    testWidgets('ForgotPasswordScreen renders mobile, OTP, new password fields and reset button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ForgotPasswordScreen(),
        ),
      );

      expect(find.text('Reset Password'), findsNWidgets(3)); // AppBar, Header, Button
      expect(find.byType(TextField), findsNWidgets(4)); // Phone, OTP, New Password, Confirm New Password
      expect(find.widgetWithText(ElevatedButton, 'Send OTP'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Reset Password'), findsOneWidget);
      expect(find.text('Back to Login'), findsOneWidget);

      // Tap Send OTP without mobile
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter your registered mobile number'), findsOneWidget);

      // Tap Send OTP with short mobile
      await tester.enterText(find.byType(TextField).at(0), '12');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid mobile number'), findsOneWidget);

      // Tap Reset Password without valid fields
      await tester.enterText(find.byType(TextField).at(0), '9876543210');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a valid 6-digit verification code'), findsOneWidget);

      // Enter OTP, mismatched passwords
      await tester.enterText(find.byType(TextField).at(1), '123456');
      await tester.enterText(find.byType(TextField).at(2), 'NewPass123!');
      await tester.enterText(find.byType(TextField).at(3), 'MismatchPass123!');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match'), findsOneWidget);
    });
  });
}
