import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class AuthHeader extends StatelessWidget {
  final bool showBackArrow;
  final VoidCallback? onBack;

  const AuthHeader({
    super.key,
    this.showBackArrow = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final headerHeight = screenHeight * 0.28;

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // Background landscape artwork
          Positioned.fill(
            child: CustomPaint(
              painter: _LandscapePainter(),
            ),
          ),

          // Safe area content: Back button + RootU Brand Title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBackArrow)
                    GestureDetector(
                      onTap: onBack ?? () => Navigator.maybePop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 34),

                  const Spacer(),

                  // RootU Brand Logo & Tagline
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Styled Location Pin Icon with leaf/travel vibe
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDark,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryDark.withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.accentLightGreen,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RootU',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Plan • Explore • Travel Together',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary.withValues(alpha: 0.9),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LandscapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFEDF3EB);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Subtle mountain back layer
    final mountainBack = Paint()..color = const Color(0xFFD6E3D3);
    final pathBack = Path()
      ..moveTo(0, size.height * 0.45)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.25, size.width * 0.6, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.35, size.width, size.height * 0.42)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathBack, mountainBack);

    // Mountain front layer (Emerald forest tone)
    final mountainFront = Paint()..color = const Color(0xFFADC8A8);
    final pathFront = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.48, size.width * 0.75, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.9, size.height * 0.55, size.width, size.height * 0.68)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathFront, mountainFront);

    // Winding highway road
    final roadPaint = Paint()
      ..color = const Color(0xFF5A7264)
      ..style = PaintingStyle.fill;
    final roadPath = Path()
      ..moveTo(size.width * 0.25, size.height)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.85, size.width * 0.72, size.height * 0.6)
      ..lineTo(size.width * 0.78, size.height * 0.6)
      ..quadraticBezierTo(size.width * 0.65, size.height * 0.9, size.width * 0.45, size.height)
      ..close();
    canvas.drawPath(roadPath, roadPaint);

    // Dashed road center line
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.35, size.height * 0.98),
      Offset(size.width * 0.42, size.height * 0.93),
      dashPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.48, size.height * 0.88),
      Offset(size.width * 0.56, size.height * 0.82),
      dashPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.75),
      Offset(size.width * 0.68, size.height * 0.68),
      dashPaint,
    );

    // Peak destination pin badge
    final pinPaint = Paint()..color = const Color(0xFF0F2D23);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.56), 6, pinPaint);
    final innerPinPaint = Paint()..color = const Color(0xFFA7C957);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.56), 3, innerPinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
