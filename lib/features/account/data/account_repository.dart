import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/id_generator.dart';

/// A device this account has authorized, as listed on "Compte & sécurité ->
/// Appareils connectés" (spec bloc 13/14).
class AuthorizedDevice {
  const AuthorizedDevice({
    required this.id,
    required this.name,
    required this.isThisDevice,
    this.lastSeenAt,
  });
  final String id;
  final String name;
  final bool isThisDevice;
  final DateTime? lastSeenAt;
}

/// Wraps Supabase Auth plus this app's own notion of "device authorization"
/// (spec bloc 13): a device only ever needs email/OTP once per account: from
/// then on it's recognized locally (no server round trip required to use
/// the app) and just needs the local PIN. The one exception, checked
/// best-effort whenever online, is a device the account owner has since
/// revoked from "Appareils connectés" - that always forces a fresh OTP.
///
/// Never conflate three separate ideas (spec bloc 1): CONNEXION AU COMPTE
/// (email/OTP - this class), VERROUILLAGE LOCAL (purely a PIN-screen UI
/// state in AppGate, this class is never involved), and CHANGER DE COMPTE /
/// DISSOCIER (clears the local device authorization below and signs out).
class AccountRepository {
  AccountRepository(this._client, this._storage);
  final SupabaseClient _client;
  final FlutterSecureStorage _storage;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isSignedIn => currentSession != null;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  static const _installationIdKey = 'device_installation_id';
  static const _deviceAuthUserIdKey = 'device_authorized_user_id';
  static const _deviceAuthEmailKey = 'device_authorized_email';
  static const _lastDeviceUserIdKey = 'device_last_user_id';

  /// A stable identifier for this physical app installation - generated
  /// once and never cleared by sign-out/account-switch (it identifies the
  /// *device*, not any one account's session on it). Deliberately not a
  /// phone number (spec bloc 13: "sans utiliser un simple numéro de
  /// téléphone") - a fresh random id has no PII and survives a SIM/number
  /// change.
  Future<String> installationId() async {
    final existing = await _storage.read(key: _installationIdKey);
    if (existing != null) return existing;
    final fresh = newId();
    await _storage.write(key: _installationIdKey, value: fresh);
    return fresh;
  }

  /// The account id this device is currently authorized for, or null if
  /// none (spec state NO_ACCOUNT_ON_DEVICE). Survives app restarts but is
  /// cleared by [disconnectFromThisDevice]/[disconnectFromAllDevices] -
  /// after that, even re-entering the *same* email always requires a fresh
  /// OTP (spec bloc 11).
  Future<String?> deviceAuthorizedUserId() => _storage.read(key: _deviceAuthUserIdKey);

  /// The last account id this device was ever authorized for, even across
  /// a "Changer de compte" that has since cleared [deviceAuthorizedUserId].
  /// Used exactly once, right after a fresh OTP success (see AppGate.
  /// _onAccountAuthenticated), to decide whether any locally-orphaned row
  /// (created while account-less, e.g. a pre-rebuild install, or a rare
  /// session-expiry edge case) belongs to whoever actually used this
  /// device before, not to the account that just signed in.
  Future<String?> lastDeviceUserId() => _storage.read(key: _lastDeviceUserIdKey);

  /// Cosmetic only (shown as "Bienvenue {email}" on the PIN screen, spec
  /// bloc 5) - never used for any authorization decision.
  Future<String?> deviceAuthorizedEmail() => _storage.read(key: _deviceAuthEmailKey);

  Future<void> _rememberDeviceAuthorization({required String userId, required String email}) async {
    await _storage.write(key: _deviceAuthUserIdKey, value: userId);
    await _storage.write(key: _deviceAuthEmailKey, value: email);
  }

  Future<void> _forgetDeviceAuthorization() async {
    await _storage.delete(key: _deviceAuthUserIdKey);
    await _storage.delete(key: _deviceAuthEmailKey);
  }

  /// Sends a 6-digit code to [email]. Covers both signup and sign-in -
  /// Supabase's email OTP endpoint auto-creates the account on a new
  /// address and just re-sends the code on an existing one, so the app
  /// never has to know in advance which case it's in (spec bloc 3, CAS A/B
  /// share the exact same app-visible flow).
  Future<void> sendEmailCode(String email) async {
    final trimmedEmail = email.trim();
    try {
      await _client.auth.signInWithOtp(email: trimmedEmail);
      _debugLogOtp('ENVOI OTP ok - email=$trimmedEmail');
    } catch (e) {
      _debugLogOtp('ENVOI OTP échec - email=$trimmedEmail erreur=$e');
      rethrow;
    }
  }

  /// Verifying the code signs the user in directly - there's no separate
  /// password to set, this call alone produces a live session. Requires the
  /// project's "Magic Link" (and "Confirm signup") email templates to embed
  /// only {{ .Token }} - never {{ .ConfirmationURL }} - see
  /// supabase/README.md.
  Future<void> verifyEmailCode({required String email, required String code}) async {
    final trimmedEmail = email.trim();
    final trimmedCode = code.trim();
    _debugLogOtp(
      'VALIDATION OTP - email=$trimmedEmail longueur=${trimmedCode.length} type=email',
    );
    try {
      await _client.auth
          .verifyOTP(type: OtpType.email, email: trimmedEmail, token: trimmedCode);
      _debugLogOtp('VALIDATION OTP ok (type=email)');
    } on AuthException catch (e) {
      if (e is AuthApiException && e.code == 'otp_expired') {
        _debugLogOtp('VALIDATION OTP échec (type=email) code=${e.code} - retente en type=signup');
        try {
          await _client.auth
              .verifyOTP(type: OtpType.signup, email: trimmedEmail, token: trimmedCode);
          _debugLogOtp('VALIDATION OTP ok (type=signup, retry)');
          return;
        } on AuthException catch (retryError) {
          _debugLogOtp('VALIDATION OTP échec (type=signup, retry) erreur=$retryError');
          throw e; // Surface the original error, not the retry's.
        }
      }
      _debugLogOtp('VALIDATION OTP échec (type=email) code=${e.code} message=${e.message}');
      rethrow;
    }
  }

  void _debugLogOtp(String message) {
    if (kDebugMode) debugPrint('[AutoCarnet][otp] $message');
  }

  /// Call once, immediately after a successful [verifyEmailCode]: records
  /// this physical installation as an authorized device for the
  /// now-signed-in account, both locally (so the next launch recognizes it
  /// without OTP - spec CAS C) and server-side in `devices` (so it shows up
  /// under "Appareils connectés" and can be revoked - spec bloc 13/14).
  /// The row id combines the installation id with the account id so the
  /// same physical device can hold one independent row per account it has
  /// ever been used with (RLS would otherwise reject one account's device
  /// row being silently repointed to another account via upsert).
  Future<void> registerThisDevice() async {
    final user = currentUser;
    if (user == null) return;
    final instId = await installationId();
    try {
      await _client.from('devices').upsert({
        'id': '${instId}_${user.id}',
        'user_id': user.id,
        'device_name': _deviceLabel(),
        'platform': _platformName(),
        'last_seen_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Best-effort: an offline first sign-in must still work locally (see
      // isDeviceStillAuthorized's own fail-open policy below) - the next
      // time this device is online it will simply upsert again.
    }
    await _rememberDeviceAuthorization(userId: user.id, email: user.email ?? '');
    await _storage.write(key: _lastDeviceUserIdKey, value: user.id);
  }

  /// Best-effort, online-only check that this device hasn't been revoked
  /// from another device since it last checked in (spec bloc 14). Never
  /// punishes an offline user: any failure (no connectivity, timeout)
  /// defaults to "still authorized" so PIN alone keeps working exactly as
  /// it always has whenever this can't be verified live.
  Future<bool> isDeviceStillAuthorized({required String userId}) async {
    try {
      final instId = await installationId();
      final rows =
          await _client.from('devices').select('id').eq('id', '${instId}_$userId').limit(1);
      return rows.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<List<AuthorizedDevice>> listMyDevices() async {
    final instId = await installationId();
    final rows = await _client.from('devices').select().order('last_seen_at', ascending: false);
    return rows
        .map((row) => AuthorizedDevice(
              id: row['id'] as String,
              name: (row['device_name'] as String?)?.trim().isNotEmpty == true
                  ? row['device_name'] as String
                  : 'Appareil inconnu',
              isThisDevice: (row['id'] as String) == '${instId}_${currentUser?.id}',
              lastSeenAt:
                  row['last_seen_at'] != null ? DateTime.tryParse(row['last_seen_at'] as String) : null,
            ))
        .toList();
  }

  /// Revoking a device deletes its `devices` row - the next time that
  /// device checks in (or launches offline-cached and later regains
  /// connectivity), [isDeviceStillAuthorized] returns false and it is
  /// forced back through email/OTP (spec bloc 14).
  Future<void> revokeDevice(String deviceRowId) async {
    await _client.from('devices').delete().eq('id', deviceRowId);
  }

  String _deviceLabel() {
    try {
      if (Platform.isAndroid) return 'Appareil Android';
      if (Platform.isIOS) return 'iPhone / iPad';
    } catch (_) {
      // Platform is unavailable in some test/host environments.
    }
    return 'Appareil';
  }

  String _platformName() {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  /// "Changer de compte" / dissociation (spec bloc 11/15): clears this
  /// device's authorization and signs out of Supabase, so the very next
  /// email typed - even this exact same address - always goes through a
  /// fresh OTP (spec bloc 11: "un OTP est obligatoire lors de
  /// l'association à ce nouvel appareil/contexte", even a returning one).
  Future<void> disconnectFromThisDevice() async {
    await _client.auth.signOut();
    await _forgetDeviceAuthorization();
  }

  /// Same as [disconnectFromThisDevice], but also revokes every other
  /// device's session for this account (spec bloc 6 - "se déconnecter de
  /// tous les appareils"). Other devices' `devices` rows are left in place
  /// (so they still show up under "Appareils connectés" for the user to
  /// see/revoke individually) but their cached session can no longer be
  /// refreshed, so their own next launch naturally falls back to email/OTP.
  Future<void> disconnectFromAllDevices() async {
    await _client.auth.signOut(scope: SignOutScope.global);
    await _forgetDeviceAuthorization();
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(Supabase.instance.client, const FlutterSecureStorage());
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(accountRepositoryProvider).onAuthStateChange;
});
