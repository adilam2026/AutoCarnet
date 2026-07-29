import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// The PIN only ever protects local access to the app (RG-USER-003) - it is
/// never sent anywhere and never substitutes account authentication
/// (RG-USER-004), which belongs to a future backend phase.
class PinService {
  PinService(this._storage, this._localAuth);
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  static const _saltKey = 'pin_salt';
  static const _hashKey = 'pin_hash';
  static const _biometricEnabledKey = 'biometric_enabled';

  Future<bool> isPinSet() async => (await _storage.read(key: _hashKey)) != null;

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final expectedHash = await _storage.read(key: _hashKey);
    if (salt == null || expectedHash == null) return false;
    return _hash(pin, salt) == expectedHash;
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _biometricEnabledKey);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _biometricEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  Future<bool> isBiometricEnabled() async {
    return (await _storage.read(key: _biometricEnabledKey)) == 'true';
  }

  static const _pinSetupOfferedKey = 'pin_setup_offered';

  /// The PIN prompt is only ever shown once after the first profile
  /// creation (bloc 2 §5.6) - skipping it should not nag the user again.
  Future<bool> hasPinSetupBeenOffered() async =>
      (await _storage.read(key: _pinSetupOfferedKey)) == 'true';

  Future<void> markPinSetupOffered() async {
    await _storage.write(key: _pinSetupOfferedKey, value: 'true');
  }

  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Local unlock only (Principe 9 / bloc 2 §5.7): never replaces account
  /// authentication.
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Déverrouillez AutoCarnet',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}

final pinServiceProvider = Provider<PinService>((ref) {
  return PinService(const FlutterSecureStorage(), LocalAuthentication());
});
