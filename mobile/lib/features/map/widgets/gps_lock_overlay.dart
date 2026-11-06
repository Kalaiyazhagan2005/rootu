import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../services/native_gps_service.dart';

/// Overlay displayed while acquiring hardware GPS satellite fix or handling permission issues
class GpsLockOverlay extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback onRetry;

  const GpsLockOverlay({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppTheme.primaryDark.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.accentLightGreen, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: AppTheme.accentLightGreen,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'LOCKING HARDWARE GPS SATELLITES...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ??
                  'Directly connecting to device GPS chip.\nEnsure Precise Location is active.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentLightGreen,
                    foregroundColor: AppTheme.primaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => NativeGpsService.openLocationSettings(),
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text(
                    'GPS SETTINGS',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => NativeGpsService.openAppSettings(),
                  icon: const Icon(Icons.security, size: 16),
                  label: const Text(
                    'PERMISSIONS',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentLightGreen,
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text(
                    'RETRY',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

