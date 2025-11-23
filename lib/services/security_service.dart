import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:crypto/crypto.dart';

class SecurityService {
  // Get APK signature hash
  Future<String?> getApkHash() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      // Use platform channel to get APK path and compute hash
      const platform = MethodChannel('ai.positronic.vault/security');
      final String? apkPath = await platform.invokeMethod('getApkPath');

      if (apkPath != null) {
        final file = File(apkPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final digest = sha256.convert(bytes);
          return digest.toString();
        }
      }
    } catch (e) {
      debugPrint('Error getting APK hash: $e');
    }

    return 'Unable to compute hash';
  }

  // Get APK signing certificate fingerprint (more reliable)
  Future<String?> getCertificateFingerprint() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      const platform = MethodChannel('ai.positronic.vault/security');
      final String? fingerprint =
          await platform.invokeMethod('getCertificateFingerprint');
      return fingerprint;
    } catch (e) {
      debugPrint('Error getting certificate fingerprint: $e');
      return 'Unable to get certificate fingerprint';
    }
  }

  // Check if device is rooted/jailbroken
  // Uses basic file existence checks for common root indicators
  Future<bool> isDeviceCompromised() async {
    try {
      if (Platform.isAndroid) {
        // Check for common root management apps and binaries
        final rootIndicators = [
          '/system/app/Superuser.apk',
          '/system/app/SuperSU.apk',
          '/system/app/Magisk.apk',
          '/sbin/su',
          '/system/bin/su',
          '/system/xbin/su',
          '/data/local/xbin/su',
          '/data/local/bin/su',
          '/system/sd/xbin/su',
          '/system/bin/failsafe/su',
          '/data/local/su',
          '/su/bin/su',
        ];

        for (final path in rootIndicators) {
          try {
            if (await File(path).exists()) {
              return true;
            }
          } catch (e) {
            // Permission denied or other errors - continue checking
            continue;
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking root status: $e');
      return false;
    }
  }

  // Check if running in developer mode (USB debugging enabled)
  Future<bool> isDeveloperMode() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      const platform = MethodChannel('ai.positronic.vault/security');
      final bool? devModeEnabled =
          await platform.invokeMethod('isDeveloperModeEnabled');
      return devModeEnabled ?? false;
    } catch (e) {
      debugPrint('Error checking developer mode: $e');
      return false;
    }
  }

  // Get app version info
  Future<String> getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return '${packageInfo.version} (${packageInfo.buildNumber})';
  }

  // Perform all security checks
  Future<SecurityStatus> getSecurityStatus() async {
    final isRooted = await isDeviceCompromised();
    final isDevMode = await isDeveloperMode();
    final version = await getAppVersion();
    final certFingerprint = await getCertificateFingerprint();

    return SecurityStatus(
      isRooted: isRooted,
      isDeveloperMode: isDevMode,
      appVersion: version,
      certificateFingerprint: certFingerprint,
    );
  }
}

class SecurityStatus {
  final bool isRooted;
  final bool isDeveloperMode;
  final String appVersion;
  final String? certificateFingerprint;

  SecurityStatus({
    required this.isRooted,
    required this.isDeveloperMode,
    required this.appVersion,
    this.certificateFingerprint,
  });

  bool get hasWarnings => isRooted || isDeveloperMode;
}
