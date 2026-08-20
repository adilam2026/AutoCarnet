import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The PIN only ever protects local access to the app (RG-USER-003) - it is
/// never sent anywhere and never substitutes account authentication
/// (RG-USER-004), which belongs to a future backend phase.
class PinService {
  PinService(this._storage);
  final FlutterSecureStorage _storage;

  static const _saltKey = 'pin_salt';
  static const _hashKey = 'pin_hash';

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
  }

  static const _pinSetupOfferedKey = 'pin_setup_offered';

  /// The PIN prompt is only ever shown once per account on this device
  /// (bloc 2 §5.6) - skipping it should not nag that account again, but a
  /// *different* account signing in later (see AppGate's account-switch
  /// handling) must still be offered its own PIN, since the previous
  /// account's answer says nothing about what this new one wants.
  /// [accountId] is the signed-in account's id, or null for a device with
  /// no cloud account at all (a single, device-wide offer in that case -
  /// there's no other account to distinguish it from).
  Future<bool> hasPinSetupBeenOffered({String? accountId}) async =>
      (await _storage.read(key: _offeredKey(accountId))) == 'true';

  Future<void> markPinSetupOffered({String? accountId}) async {
    await _storage.write(key: _offeredKey(accountId), value: 'true');
  }

  String _offeredKey(String? accountId) =>
      accountId == null ? _pinSetupOfferedKey : '${_pinSetupOfferedKey}_$accountId';

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
  return PinService(const FlutterSecureStorage());
});
