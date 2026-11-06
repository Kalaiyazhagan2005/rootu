import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'services/auth_api_service.dart';
import 'widgets/auth_header.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/primary_button.dart';
import 'otp_verification_screen.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _verificationToken;

  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  bool _validatePassword(String pwd) {
    if (pwd.length < 8) return false;
    final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
    final hasLower = pwd.contains(RegExp(r'[a-z]'));
    final hasDigit = pwd.contains(RegExp(r'\d'));
    final hasSpecial = pwd.contains(RegExp(r'[!@#$%^&*()_+\-=\[\]{};\x27:"\\|,.<>\/?]'));
    return hasUpper && hasLower && hasDigit && hasSpecial;
  }

  Future<void> _handleSendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter your registered mobile number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final res = await AuthApiService.sendForgotPasswordOtp(phone);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res.success) {
      final token = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            mobileNumber: phone,
            flowType: OtpFlowType.forgotPassword,
            initialCooldownSeconds: res.data ?? 60,
          ),
        ),
      );

      if (token != null && mounted) {
        setState(() {
          _verificationToken = token;
          _infoMessage = 'Mobile number verified. Please choose a new secure password.';
        });
      }
    } else {
      setState(() => _errorMessage = res.message);
    }
  }

  Future<void> _handleResetPassword() async {
    final phone = _phoneController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmNewPassword = _confirmNewPasswordController.text;

    if (_verificationToken == null) {
      setState(() => _errorMessage = 'Please verify your mobile number first');
      return;
    }

    if (newPassword.isEmpty || confirmNewPassword.isEmpty) {
      setState(() => _errorMessage = 'Please enter and confirm your new password');
      return;
    }

    if (newPassword != confirmNewPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (!_validatePassword(newPassword)) {
      setState(() => _errorMessage =
          'Password must have at least 8 characters, an uppercase letter, a lowercase letter, a number, and a special character');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final resetRes = await AuthApiService.resetPassword(
      verificationToken: _verificationToken!,
      phone: phone,
      newPassword: newPassword,
      confirmNewPassword: confirmNewPassword,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (resetRes.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resetRes.message),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      setState(() => _errorMessage = resetRes.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTokenAcquired = _verificationToken != null;

    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      body: SingleChildScrollView(
        child: Column(
          children: [
            AuthHeader(
              showBackArrow: true,
              onBack: () => Navigator.maybePop(context),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppTheme.cardWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x080F2D23),
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTokenAcquired ? 'Create New Password' : 'Reset Password',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isTokenAcquired
                        ? 'Enter a new secure password for your account'
                        : 'We will send a 6-digit OTP to verify your identity',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE8E8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.errorRed, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AppTheme.errorRed,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (_infoMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF5EC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _infoMessage!,
                              style: const TextStyle(
                                color: AppTheme.primaryGreen,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  CustomTextField(
                    label: 'Mobile Number',
                    hintText: '+91 98765 43210',
                    prefixIcon: Icons.phone_android_rounded,
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    readOnly: isTokenAcquired,
                    suffixIcon: isTokenAcquired
                        ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 20)
                        : null,
                    textInputAction: TextInputAction.done,
                  ),

                  const SizedBox(height: 16),

                  if (isTokenAcquired) ...[
                    CustomTextField(
                      label: 'New Password',
                      hintText: 'Min 8 chars, mixed case, number & symbol',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscurePassword,
                      controller: _newPasswordController,
                      textInputAction: TextInputAction.next,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'Confirm New Password',
                      hintText: 'Re-enter your new password',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscureConfirmPassword,
                      controller: _confirmNewPasswordController,
                      textInputAction: TextInputAction.done,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      text: 'Set New Password',
                      isLoading: _isLoading,
                      onPressed: _handleResetPassword,
                    ),
                  ] else ...[
                    PrimaryButton(
                      text: 'Send Verification OTP',
                      isLoading: _isLoading,
                      onPressed: _handleSendOtp,
                    ),
                  ],

                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      child: const Text(
                        'Back to Login',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
