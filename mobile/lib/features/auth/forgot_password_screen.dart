import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_api_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmNewPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _verificationToken;

  bool _isSendingOtp = false;
  bool _isResetting = false;
  int _cooldownSeconds = 0;
  Timer? _timer;

  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onCredentialChanged);
    _otpController.addListener(_onCredentialChanged);
  }

  void _onCredentialChanged() {
    if (_verificationToken != null) {
      setState(() {
        _verificationToken = null;
      });
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onCredentialChanged);
    _otpController.removeListener(_onCredentialChanged);
    _timer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmNewPasswordController.dispose();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    setState(() => _cooldownSeconds = seconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds > 0) {
        if (mounted) setState(() => _cooldownSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatCooldown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '$m:${s.toString().padLeft(2, '0')}';
    }
    return '${s}s';
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

    if (phone.length < 5 || phone.length > 20) {
      setState(() => _errorMessage = 'Please enter a valid mobile number');
      return;
    }

    _verificationToken = null;
    setState(() {
      _isSendingOtp = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final res = await AuthApiService.sendForgotPasswordOtp(phone);
      if (!mounted) return;
      setState(() => _isSendingOtp = false);

      if (res.success) {
        final cd = res.data ?? 60;
        _startCooldown(cd);
        setState(() {
          _infoMessage = 'Verification code sent to $phone';
        });
      } else {
        if (res.retryAfterSeconds != null) {
          _startCooldown(res.retryAfterSeconds!);
        }
        setState(() => _errorMessage = res.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
        _errorMessage = 'An error occurred: $e';
      });
    }
  }

  Future<void> _handleResetPassword() async {
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmNewPassword = _confirmNewPasswordController.text;

    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter your mobile number');
      return;
    }

    if (phone.length < 5 || phone.length > 20) {
      setState(() => _errorMessage = 'Please enter a valid mobile number');
      return;
    }

    if (otp.isEmpty || otp.length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-digit verification code');
      return;
    }

    if (newPassword.isEmpty || confirmNewPassword.isEmpty) {
      setState(() => _errorMessage = 'Please enter and confirm your new password');
      return;
    }

    if (newPassword.length > 72) {
      setState(() => _errorMessage = 'Password cannot exceed 72 characters');
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
      _isResetting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      // Verify OTP first if token not already acquired
      String token = _verificationToken ?? '';
      if (token.isEmpty) {
        final verifyRes = await AuthApiService.verifyForgotPasswordOtp(phone, otp);
        if (!verifyRes.success) {
          if (!mounted) return;
          setState(() {
            _isResetting = false;
            _errorMessage = verifyRes.message;
          });
          return;
        }
        token = verifyRes.data!;
        _verificationToken = token;
      }

      final resetRes = await AuthApiService.resetPassword(
        verificationToken: token,
        phone: phone,
        newPassword: newPassword,
        confirmNewPassword: confirmNewPassword,
      );

      if (!mounted) return;
      setState(() => _isResetting = false);

      if (resetRes.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resetRes.message),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = resetRes.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResetting = false;
        _errorMessage = 'An error occurred: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isSendingOtp || _isResetting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reset Password',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your registered mobile number, OTP, and new password',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_infoMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _infoMessage!,
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number',
                        hintText: 'Enter mobile number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: (_cooldownSeconds > 0 || isLoading) ? null : _handleSendOtp,
                      child: _isSendingOtp
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _cooldownSeconds > 0 ? _formatCooldown(_cooldownSeconds) : 'Send OTP',
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '6-Digit OTP',
                  hintText: 'Enter 6-digit OTP',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.security),
                  counterText: '',
                  suffixIcon: _verificationToken != null
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _newPasswordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  hintText: 'Min 8 chars, mixed case, number & symbol',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _confirmNewPasswordController,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleResetPassword(),
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  hintText: 'Re-enter your new password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handleResetPassword,
                  child: _isResetting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset Password'),
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  },
                  child: const Text('Back to Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
