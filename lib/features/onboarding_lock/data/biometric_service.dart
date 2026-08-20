import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps the device's own biometrics (fingerprint / Face ID) as a fast
/// alternative to typing the local PIN (RG-USER-003). It never replaces
/// the PIN as a credential - enabling it always requires a PIN to already
/// be set, and any failure (cancelled, lockout, hardware unavailable)
/// falls back to the PIN screen rather than ever silently unlocking.
class BiometricService {
  BiometricService(this._auth, this._storage);
  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _enabledKey = 'biometric_unlock_enabled';

  /// Whether this device can even offer biometrics - enrolled fingerprint/
  /// face AND hardware support. Never assume; always ask the platform.
  Future<bool> isDeviceSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async => (await _storage.read(key: _enabledKey)) == 'true';

  Future<void> setEnabled(bool enabled) async {
    await _storage.write(key: _enabledKey, value: enabled ? 'true' : 'false');
  }

  /// Only ever returns true on a real, fresh biometric success reported by
  /// the OS - any exception (user cancelled, too many attempts, no
  /// biometrics enrolled anymore) is treated as "not unlocked" and the
  /// caller falls back to the PIN field.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Déverrouillez AutoCarnet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService(LocalAuthentication(), const FlutterSecureStorage());
});
