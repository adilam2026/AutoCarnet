import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The PIN only ever protects local access to the app (RG-USER-003) - it is
/// never sent anywhere and never substitutes account authentication
/// (RG-USER-004).
///
/// Scoped per [accountId] on purpose: a device can know several already-
/// authorized accounts at once (spec bloc "changer de compte n'est pas
/// forcément nouvel appareil"), each with its own local PIN - PIN A must
/// never open account B's data and vice versa (spec TEST F).
class PinService {
  PinService(this._storage);
  final FlutterSecureStorage _storage;

  static const _saltPrefix = 'pin_salt_';
  static const _hashPrefix = 'pin_hash_';

  Future<bool> isPinSet(String accountId) async =>
      (await _storage.read(key: _hashPrefix + accountId)) != null;

  Future<void> setPin(String accountId, String pin) async {
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await _storage.write(key: _saltPrefix + accountId, value: salt);
    await _storage.write(key: _hashPrefix + accountId, value: hash);
  }

  Future<bool> verifyPin(String accountId, String pin) async {
    final salt = await _storage.read(key: _saltPrefix + accountId);
    final expectedHash = await _storage.read(key: _hashPrefix + accountId);
    if (salt == null || expectedHash == null) return false;
    return _hash(pin, salt) == expectedHash;
  }

  Future<void> clearPin(String accountId) async {
    await _storage.delete(key: _saltPrefix + accountId);
    await _storage.delete(key: _hashPrefix + accountId);
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
  return PinService(const FlutterSecureStorage());
});
