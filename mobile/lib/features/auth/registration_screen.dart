import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'services/auth_api_service.dart';
import 'widgets/auth_header.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/primary_button.dart';
import 'otp_verification_screen.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _acceptTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty || phone.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'All fields are required');
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (!_validatePassword(password)) {
      setState(() => _errorMessage =
          'Password must have at least 8 characters, an uppercase letter, a lowercase letter, a number, and a special character');
      return;
    }

    if (!_acceptTerms) {
      setState(() => _errorMessage = 'You must accept the Terms & Privacy Policy to continue');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await AuthApiService.sendRegistrationOtp(phone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res.success) {
      final cooldown = res.data ?? 60;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            mobileNumber: phone,
            flowType: OtpFlowType.registration,
            fullName: fullName,
            password: password,
            confirmPassword: confirmPassword,
            acceptTerms: _acceptTerms,
            initialCooldownSeconds: cooldown,
          ),
        ),
      );
    } else {
      setState(() => _errorMessage = res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Join RootU to connect with riders and plan safe group trips',
                    style: TextStyle(
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

                  CustomTextField(
                    label: 'Full Name',
                    hintText: 'Enter your full name',
                    prefixIcon: Icons.person_outline_rounded,
                    controller: _fullNameController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Mobile Number',
                    hintText: '+91 98765 43210',
                    prefixIcon: Icons.phone_android_rounded,
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    label: 'Password',
                    hintText: 'Min 8 chars, mixed case, number & symbol',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    controller: _passwordController,
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
                    label: 'Confirm Password',
                    hintText: 'Re-enter your password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: _obscureConfirmPassword,
                    controller: _confirmPasswordController,
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
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _acceptTerms,
                          activeColor: AppTheme.primaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          onChanged: (val) => setState(() => _acceptTerms = val ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'I agree to the RootU Terms of Service & Privacy Policy',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  PrimaryButton(
                    text: 'Continue to Verification',
                    isLoading: _isLoading,
                    onPressed: _handleSendOtp,
                  ),
                  const SizedBox(height: 20),

                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      child: RichText(
                        text: const TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          children: [
                            TextSpan(
                              text: 'Log in',
                              style: TextStyle(
                                color: AppTheme.primaryGreen,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
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
