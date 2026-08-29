import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/onboarding_lock/data/biometric_service.dart';
import 'package:autocarnet/features/onboarding_lock/data/pin_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, real device incident: a device that had gone through
/// several uninstall/reinstall cycles hit a real, confirmed
/// `PlatformException(..., javax.crypto.BadPaddingException: error:
/// 1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT, ...)` reading a
/// stored value back from flutter_secure_storage - a well-known Android
/// failure mode: Auto Backup restores the app's old encrypted preferences
/// file across a reinstall, but the AES key living in the Android Keystore
/// is hardware-bound and never backed up, so the fresh install's brand new
/// key can never decrypt the old ciphertext again.
///
/// AccountRepository/PinService/BiometricService now treat that failure
/// exactly like "no value stored" (and drop the poisoned key so it stops
/// throwing on every future read) instead of letting the exception
/// propagate - these tests simulate the exact throw via a fake
/// FlutterSecureStorage (its own `read` explicitly documents "Can throw a
/// PlatformException") and assert every affected method degrades
/// gracefully instead of crashing the caller.
class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({Set<String> corruptedKeys = const {}})
      : _corruptedKeys = {...corruptedKeys};
  final Map<String, String> _values = {};
  final Set<String> _corruptedKeys;
  final List<String> deletedKeys = [];

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (_corruptedKeys.contains(key)) {
      throw PlatformException(
        code: 'read',
        message: 'Exception encountered',
        details: 'javax.crypto.BadPaddingException: error:1e000065:Cipher '
            'functions:OPENSSL_internal:BAD_DECRYPT',
      );
    }
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    _corruptedKeys.remove(key);
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.add(key);
    _values.remove(key);
    _corruptedKeys.remove(key);
  }
}

void main() {
  // An unauthenticated, no-network client is enough - none of the methods
  // exercised here ever reach it once the corrupted local read has already
  // returned null (same technique as sync_outbox_recovery_test.dart).
  SupabaseClient buildClient() =>
      SupabaseClient('https://example.invalid.supabase.co', 'anon-key-test');

  group('AccountRepository - undecryptable secure storage values', () {
    test('deviceAuthorizedUserId() returns null instead of throwing, and '
        'clears the poisoned key', () async {
      final storage = _FakeSecureStorage(corruptedKeys: {'device_authorized_user_id'});
      final account = AccountRepository(buildClient(), storage);

      final result = await account.deviceAuthorizedUserId();

      expect(result, isNull);
      expect(storage.deletedKeys, contains('device_authorized_user_id'));
    });

    test('lastDeviceUserId() and deviceAuthorizedEmail() are equally '
        'resilient', () async {
      final storage = _FakeSecureStorage(
        corruptedKeys: {'device_last_user_id', 'device_authorized_email'},
      );
      final account = AccountRepository(buildClient(), storage);

      expect(await account.lastDeviceUserId(), isNull);
      expect(await account.deviceAuthorizedEmail(), isNull);
    });

    test('installationId() recovers by generating and storing a fresh id '
        'when the previously stored one is undecryptable - never throws',
        () async {
      final storage = _FakeSecureStorage(corruptedKeys: {'device_installation_id'});
      final account = AccountRepository(buildClient(), storage);

      final id = await account.installationId();

      expect(id, isNotEmpty);
      // A second call now reads back the freshly-written id, not the
      // still-poisoned one - proof the corrupted key was actually replaced.
      expect(await account.installationId(), id);
    });

    test('tryRestoreDeviceSession() falls through to null (real OTP path) '
        'instead of crashing when the stored refresh token cannot be '
        'decrypted - never reaches Supabase at all in that case', () async {
      final storage = _FakeSecureStorage(
        corruptedKeys: {'account_refresh_token_a@example.com'},
      );
      final account = AccountRepository(buildClient(), storage);

      final restored = await account.tryRestoreDeviceSession('a@example.com');

      expect(restored, isNull);
    });
  });

  group('PinService - undecryptable secure storage values', () {
    test('isPinSet() returns false instead of throwing, and clears the '
        'poisoned key', () async {
      final storage = _FakeSecureStorage(corruptedKeys: {'pin_hash_user-1'});
      final pinService = PinService(storage);

      expect(await pinService.isPinSet('user-1'), isFalse);
      expect(storage.deletedKeys, contains('pin_hash_user-1'));
    });

    test('verifyPin() returns false instead of throwing when either the '
        'salt or the hash is undecryptable', () async {
      final storageSaltCorrupted =
          _FakeSecureStorage(corruptedKeys: {'pin_salt_user-1'});
      final pinService1 = PinService(storageSaltCorrupted);
      expect(await pinService1.verifyPin('user-1', '1234'), isFalse);

      final storageHashCorrupted =
          _FakeSecureStorage(corruptedKeys: {'pin_hash_user-1'});
      final pinService2 = PinService(storageHashCorrupted);
      expect(await pinService2.verifyPin('user-1', '1234'), isFalse);
    });

    test('setPin() after a corrupted read cures it - the account can set a '
        'fresh PIN rather than being permanently locked out', () async {
      final storage = _FakeSecureStorage(
        corruptedKeys: {'pin_salt_user-1', 'pin_hash_user-1'},
      );
      final pinService = PinService(storage);
      expect(await pinService.isPinSet('user-1'), isFalse);

      await pinService.setPin('user-1', '1234');

      expect(await pinService.isPinSet('user-1'), isTrue);
      expect(await pinService.verifyPin('user-1', '1234'), isTrue);
    });
  });

  group('BiometricService - undecryptable secure storage values', () {
    test('isEnabled() returns false instead of throwing, and clears the '
        'poisoned key', () async {
      final storage = _FakeSecureStorage(corruptedKeys: {'biometric_unlock_enabled_user-1'});
      final biometricService = BiometricService(LocalAuthentication(), storage);

      expect(await biometricService.isEnabled('user-1'), isFalse);
      expect(storage.deletedKeys, contains('biometric_unlock_enabled_user-1'));
    });
  });
}
