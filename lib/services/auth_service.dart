import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _passwordKey = 'vault_password_hash';
  static const _saltKey = 'vault_password_salt';

  final LocalAuthentication _localAuth = LocalAuthentication();

  // Check if password is set
  Future<bool> hasPassword() async {
    final hash = await _storage.read(key: _passwordKey);
    return hash != null;
  }

  // Set password (first time setup)
  Future<void> setPassword(String password) async {
    // Generate a random salt
    final salt = DateTime.now().millisecondsSinceEpoch.toString();

    // Hash the password with salt
    final hash = _hashPassword(password, salt);

    // Store hash and salt
    await _storage.write(key: _passwordKey, value: hash);
    await _storage.write(key: _saltKey, value: salt);
  }

  // Verify password
  Future<bool> verifyPassword(String password) async {
    final storedHash = await _storage.read(key: _passwordKey);
    final salt = await _storage.read(key: _saltKey);

    if (storedHash == null || salt == null) {
      return false;
    }

    final hash = _hashPassword(password, salt);
    return hash == storedHash;
  }

  // Hash password with salt
  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Check if biometric authentication is available
  Future<bool> isBiometricAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      return false;
    }
  }

  // Get available biometric types (for debugging)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Authenticate with biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access Vault',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }

  // Change password
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    final isValid = await verifyPassword(oldPassword);
    if (!isValid) {
      return false;
    }

    await setPassword(newPassword);
    return true;
  }

  // Clear all auth data (for testing/reset)
  Future<void> clearAuth() async {
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _saltKey);
  }
}
