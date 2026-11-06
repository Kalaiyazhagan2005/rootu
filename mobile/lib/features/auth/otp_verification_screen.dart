import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'services/auth_api_service.dart';
import 'widgets/auth_header.dart';
import 'widgets/primary_button.dart';
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
  static const int _otpLength = 6;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  late int _resendCountdown;
  Timer? _timer;
  bool _isLoading = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_otpLength, (_) => TextEditingController());
    _focusNodes = List.generate(_otpLength, (_) => FocusNode());
    for (int i = 0; i < _otpLength; i++) {
      final index = i;
      _focusNodes[index].onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _controllers[index].text.isEmpty &&
            index > 0) {
          _focusNodes[index - 1].requestFocus();
          _controllers[index - 1].clear();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
    _resendCountdown = widget.initialCooldownSeconds;
    _startCountdown();
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

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _enteredOtp => _controllers.map((c) => c.text.trim()).join();

  Future<void> _handleVerify() async {
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });

    final otp = _enteredOtp;
    if (otp.length < _otpLength) {
      setState(() => _errorMessage = 'Please enter all 6 digits of your verification code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.flowType == OtpFlowType.registration) {
        // Step 1: Verify OTP on production backend
        final verifyRes = await AuthApiService.verifyRegistrationOtp(widget.mobileNumber, otp);
        if (!verifyRes.success) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = verifyRes.message;
          });
          return;
        }

        final verificationToken = verifyRes.data!;

        // Step 2: If credentials are provided, finalize registration
        if (widget.fullName != null && widget.password != null) {
          final createRes = await AuthApiService.completeRegistration(
            verificationToken: verificationToken,
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
          Navigator.of(context).pop(verificationToken);
        }
      } else {
        // Forgot password OTP verification
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
                    'OTP Verification',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'We sent a 6-digit code to ${widget.mobileNumber.isEmpty ? "your mobile" : widget.mobileNumber}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.inputFill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.inputBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, size: 14, color: AppTheme.primaryGreen),
                              SizedBox(width: 4),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // 6-Digit Box Input Row with auto-advance and backspace navigation
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final boxWidth = (constraints.maxWidth - (5 * 8)) / 6;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(_otpLength, (index) {
                          return SizedBox(
                            width: boxWidth.clamp(42.0, 52.0),
                            height: 60,
                            child: TextFormField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryDark,
                              ),
                              decoration: InputDecoration(
                                counterText: '',
                                filled: true,
                                fillColor: _controllers[index].text.isNotEmpty
                                    ? const Color(0xFFEDF5EC)
                                    : AppTheme.inputFill,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: _controllers[index].text.isNotEmpty
                                        ? AppTheme.primaryGreen
                                        : AppTheme.inputBorder,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                    color: AppTheme.primaryGreen,
                                    width: 2,
                                  ),
                                ),
                              ),
                              onChanged: (val) {
                                if (val.length > 1) {
                                  final digits = val.replaceAll(RegExp(r'\D'), '');
                                  if (digits.length >= 2 && index == 0) {
                                    // Multi-digit paste or SMS autofill into first box
                                    for (int i = 0; i < digits.length && i < _otpLength; i++) {
                                      _controllers[i].text = digits[i];
                                    }
                                    final targetIdx = digits.length.clamp(0, _otpLength - 1);
                                    _focusNodes[targetIdx].requestFocus();
                                    setState(() {});
                                    if (_enteredOtp.length == _otpLength) {
                                      _handleVerify();
                                    }
                                    return;
                                  } else {
                                    // User typed over an existing character: keep the newest digit
                                    _controllers[index].text = val.substring(val.length - 1);
                                    if (index < _otpLength - 1) {
                                      _focusNodes[index + 1].requestFocus();
                                    }
                                    setState(() {});
                                    if (_enteredOtp.length == _otpLength) {
                                      _handleVerify();
                                    }
                                    return;
                                  }
                                }

                                setState(() {});
                                if (val.isNotEmpty && index < _otpLength - 1) {
                                  _focusNodes[index + 1].requestFocus();
                                } else if (val.isEmpty && index > 0) {
                                  _focusNodes[index - 1].requestFocus();
                                }
                                if (_enteredOtp.length == _otpLength) {
                                  _handleVerify();
                                }
                              },
                            ),

                          );
                        }),
                      );
                    },
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.errorRed,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  if (_infoMessage != null) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        _infoMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.primaryGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Resend countdown
                  Center(
                    child: _resendCountdown > 0
                        ? RichText(
                            text: TextSpan(
                              text: 'Resend code in ',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              children: [
                                TextSpan(
                                  text: '0:${_resendCountdown.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: AppTheme.primaryDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: _handleResend,
                            child: const Text(
                              "Didn't receive code? Resend OTP",
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.primaryGreen,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),

                  // Verify Button
                  PrimaryButton(
                    text: 'Verify & Proceed',
                    isLoading: _isLoading,
                    onPressed: _handleVerify,
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
