import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/auth_api_service.dart';
import '../home/home_screen.dart';

enum OtpFlowType {
  registration,
  forgotPassword,
}

class OtpVerificationScreen extends StatefulWidget {
  final String mobileNumber;
  final OtpFlowType flowType;
  final String? fullName;
  final String? password;
  final String? confirmPassword;
  final bool acceptTerms;
  final int initialCooldownSeconds;

  const OtpVerificationScreen({
    super.key,
    required this.mobileNumber,
    this.flowType = OtpFlowType.registration,
    this.fullName,
    this.password,
    this.confirmPassword,
    this.acceptTerms = false,
    this.initialCooldownSeconds = 60,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  late int _resendCountdown;
  Timer? _timer;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;
  String? _verificationToken;

  @override
  void initState() {
    super.initState();
    _resendCountdown = widget.initialCooldownSeconds;
    _startCountdown();
    _otpController.addListener(_onOtpChanged);
  }

  void _onOtpChanged() {
    if (_verificationToken != null) {
      setState(() {
        _verificationToken = null;
      });
    }
  }

  void _startCountdown([int? seconds]) {
    setState(() => _resendCountdown = seconds ?? _resendCountdown);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        if (mounted) setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _otpController.removeListener(_onOtpChanged);
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits of your verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.flowType == OtpFlowType.registration) {
        String token = _verificationToken ?? '';
        if (token.isEmpty) {
          final verifyRes = await AuthApiService.verifyRegistrationOtp(widget.mobileNumber, otp);
          if (!verifyRes.success) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = verifyRes.message;
            });
            return;
          }
          token = verifyRes.data!;
          _verificationToken = token;
        }

        if (widget.fullName != null && widget.password != null) {
          final createRes = await AuthApiService.completeRegistration(
            verificationToken: token,
            phone: widget.mobileNumber,
            fullName: widget.fullName!,
            password: widget.password!,
            confirmPassword: widget.confirmPassword ?? widget.password!,
            acceptTerms: widget.acceptTerms,
          );

          if (!mounted) return;
          setState(() => _isLoading = false);

          if (createRes.success) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          } else {
            setState(() => _errorMessage = createRes.message);
          }
        } else {
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).pop(token);
        }
      } else {
        final verifyRes = await AuthApiService.verifyForgotPasswordOtp(widget.mobileNumber, otp);
        if (!mounted) return;
        setState(() => _isLoading = false);

        if (verifyRes.success) {
          Navigator.of(context).pop(verifyRes.data);
        } else {
          setState(() => _errorMessage = verifyRes.message);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'An error occurred: $e';
      });
    }
  }

  Future<void> _handleResend() async {
    if (_resendCountdown > 0 || _isLoading) return;

    _verificationToken = null;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final res = widget.flowType == OtpFlowType.registration
          ? await AuthApiService.sendRegistrationOtp(widget.mobileNumber)
          : await AuthApiService.sendForgotPasswordOtp(widget.mobileNumber);

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (res.success) {
        final cooldown = res.data ?? 60;
        _startCountdown(cooldown);
        setState(() => _infoMessage = 'A new verification code has been dispatched.');
      } else {
        if (res.retryAfterSeconds != null) {
          _startCountdown(res.retryAfterSeconds!);
        }
        setState(() => _errorMessage = res.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to resend code: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Verification'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter Verification Code',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a 6-digit code to ${widget.mobileNumber.isEmpty ? "your mobile" : widget.mobileNumber}',
                style: const TextStyle(
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

              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: '6-Digit OTP',
                  hintText: '123456',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => _handleVerify(),
              ),
              const SizedBox(height: 16),

              Center(
                child: _resendCountdown > 0
                    ? Text(
                        'Resend code in ${_formatTimer(_resendCountdown)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      )
                    : TextButton(
                        onPressed: _isLoading ? null : _handleResend,
                        child: const Text("Didn't receive code? Resend OTP"),
                      ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerify,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify & Proceed'),
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Change Mobile Number'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
