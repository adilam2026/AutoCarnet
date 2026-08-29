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
/// (spec bloc 13): a device only ever needs email/OTP once *per account* -
/// from then on that account is recognized locally on this exact
/// installation and just needs its own local PIN. A single device can know
/// *several* accounts this way (spec: "Un même téléphone doit pouvoir
/// mémoriser plusieurs comptes déjà autorisés, chacun avec son contexte
/// local approprié") - switching between two already-known accounts never
/// needs a fresh OTP, only switching to a genuinely new account/device
/// pairing does. The one exception, checked best-effort whenever online, is
/// a device the account owner has since revoked from "Appareils connectés"
/// - that always forces a fresh OTP for that specific account again.
///
/// Never conflate three separate ideas (spec bloc 1/15): VERROUILLER
/// (purely a PIN-screen UI state in AppGate, this class is never involved),
/// CHANGER DE COMPTE (switches which known account is active - see
/// [tryRestoreDeviceSession] - never forgets anything), and RÉVOQUER/
/// DISSOCIER (forgets one specific account's local association - see
/// [disconnectFromThisDevice]/[disconnectFromAllDevices] - the *only* two
/// operations that make a fresh OTP mandatory again).
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

  /// A raw [FlutterSecureStorage.read] throws (a `PlatformException`
  /// wrapping `javax.crypto.BadPaddingException`/`OPENSSL_internal:
  /// BAD_DECRYPT`) instead of returning null when the stored ciphertext
  /// can't be decrypted with the app's *current* Android Keystore key - a
  /// real, observed failure mode after an uninstall/reinstall: Android's
  /// Auto Backup restores the old encrypted preferences file, but the
  /// Keystore key itself is hardware-bound and never backed up, so the
  /// fresh install gets a brand new key that can never open the old
  /// ciphertext. Every read in this class goes through here instead of
  /// `_storage.read` directly - an undecryptable value is exactly as good
  /// as an absent one from the app's perspective, and is deleted so this
  /// same key doesn't keep throwing on every future read.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[AutoCarnet][secure_storage] undecryptable value for "$key" ($e) - '
          'treating as absent and clearing it');
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  /// A stable identifier for this physical app installation - generated
  /// once and never cleared by sign-out/account-switch (it identifies the
  /// *device*, not any one account's session on it). Deliberately not a
  /// phone number (spec bloc 13: "sans utiliser un simple numéro de
  /// téléphone") - a fresh random id has no PII and survives a SIM/number
  /// change.
  Future<String> installationId() async {
    final existing = await _safeRead(_installationIdKey);
    if (existing != null) return existing;
    final fresh = newId();
    await _storage.write(key: _installationIdKey, value: fresh);
    return fresh;
  }

  /// The account id that is currently *active* on this device (whichever
  /// account's PIN screen should show), or null if none (spec state
  /// NO_ACCOUNT_ON_DEVICE - a brand new device, or every known account has
  /// been explicitly dissociated). Switching to a different already-known
  /// account (spec CAS 3) updates this to the new one without clearing
  /// anything else - only [disconnectFromThisDevice]/
  /// [disconnectFromAllDevices] (a real dissociation) can send this back to
  /// null, and only for the account being dissociated.
  Future<String?> deviceAuthorizedUserId() => _safeRead(_deviceAuthUserIdKey);

  /// The last account id this device was ever authorized for. Used exactly
  /// once, right after any account becomes active (fresh OTP *or* a silent
  /// restore - see AppGate._onAccountAuthenticated), to decide whether any
  /// locally-orphaned row (created while account-less, e.g. a pre-rebuild
  /// install, or a rare session-expiry edge case) belongs to whoever
  /// actually used this device most recently, not to the account that just
  /// became active.
  Future<String?> lastDeviceUserId() => _safeRead(_lastDeviceUserIdKey);

  /// Cosmetic only - never used for any authorization decision. Shown on
  /// the PIN screen (spec bloc 5) only as a fallback greeting for an
  /// account with no profile displayName set yet; once one exists, that
  /// name is used instead (mission: never a raw email once a name exists).
  Future<String?> deviceAuthorizedEmail() => _safeRead(_deviceAuthEmailKey);

  Future<void> _rememberDeviceAuthorization({required String userId, required String email}) async {
    await _storage.write(key: _deviceAuthUserIdKey, value: userId);
    await _storage.write(key: _deviceAuthEmailKey, value: email);
  }

  Future<void> _forgetDeviceAuthorization() async {
    await _storage.delete(key: _deviceAuthUserIdKey);
    await _storage.delete(key: _deviceAuthEmailKey);
  }

  String _refreshTokenKey(String email) => 'account_refresh_token_${_normalizeEmail(email)}';
  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<void> _forgetKnownAccount(String email) async {
    await _storage.delete(key: _refreshTokenKey(email));
  }

  /// Sends a 6-digit code to [email]. Covers both signup and sign-in -
  /// Supabase's email OTP endpoint auto-creates the account on a new
  /// address and just re-sends the code on an existing one, so the app
  /// never has to know in advance which case it's in (spec bloc 3, CAS 1/2
  /// share the exact same app-visible flow). Only ever called after
  /// [tryRestoreDeviceSession] has already failed for that email - never
  /// for an account this exact device already knows (spec CAS 3).
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

  /// The heart of spec CAS 3 ("email enrôlé ET déjà associé à cet
  /// appareil -> pas d'OTP, PIN directement"): attempts to silently
  /// restore this *exact installation's* own previously-established
  /// session for [email], using a refresh token saved locally the last
  /// time that account completed a real OTP on this device (see
  /// [registerThisDevice]). No network round trip to any OTP endpoint at
  /// all - `setSession` just exchanges the stored refresh token for a
  /// fresh access token.
  ///
  /// On success, [email]'s account becomes this device's *active* account
  /// (whichever one the PIN screen now protects) - its own local PIN
  /// (never a different known account's) is what's asked for next. Returns
  /// the restored account's id, or null if this device has never stored a
  /// token for [email], or the stored token no longer works (expired, or
  /// the account owner revoked this exact device from "Appareils
  /// connectés" - spec bloc 14/TEST E) - in which case the caller must
  /// fall back to a real OTP (spec CAS 1/2).
  Future<String?> tryRestoreDeviceSession(String email) async {
    final normalized = _normalizeEmail(email);
    final refreshToken = await _safeRead(_refreshTokenKey(normalized));
    if (refreshToken == null) return null;
    try {
      final response = await _client.auth.setSession(refreshToken);
      final user = response.user;
      if (user == null) return null;
      final stillAuthorized = await isDeviceStillAuthorized(userId: user.id);
      if (!stillAuthorized) {
        // Revoked from "Appareils connectés" since this device last
        // checked in - the stored token must never be tried again; the
        // caller falls through to a real OTP, exactly as if this were a
        // brand new association (spec TEST E).
        await _client.auth.signOut();
        await _forgetKnownAccount(normalized);
        return null;
      }
      await _rememberDeviceAuthorization(userId: user.id, email: user.email ?? normalized);
      await _storage.write(key: _lastDeviceUserIdKey, value: user.id);
      // Supabase rotates the refresh token on every use - the one just
      // consumed is now dead, so the *new* one is what must be kept for
      // the next silent restore attempt.
      final rotatedToken = response.session?.refreshToken;
      if (rotatedToken != null) {
        await _storage.write(key: _refreshTokenKey(normalized), value: rotatedToken);
      }
      return user.id;
    } catch (_) {
      return null;
    }
  }

  /// Call once, immediately after a successful [verifyEmailCode]: records
  /// this physical installation as an authorized device for the
  /// now-signed-in account, both locally (so a future [tryRestoreDeviceSession]
  /// for this exact email can skip OTP - spec CAS C) and server-side in
  /// `devices` (so it shows up under "Appareils connectés" and can be
  /// revoked - spec bloc 13/14). The row id combines the installation id
  /// with the account id so the same physical device can hold one
  /// independent row per account it has ever been used with (RLS would
  /// otherwise reject one account's device row being silently repointed to
  /// another account via upsert).
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
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best-effort: an offline first sign-in must still work locally (see
      // isDeviceStillAuthorized's own fail-open policy below) - the next
      // time this device is online it will simply upsert again.
    }
    await _rememberDeviceAuthorization(userId: user.id, email: user.email ?? '');
    await _storage.write(key: _lastDeviceUserIdKey, value: user.id);
    final refreshToken = currentSession?.refreshToken;
    if (refreshToken != null && user.email != null) {
      await _storage.write(key: _refreshTokenKey(user.email!), value: refreshToken);
    }
  }

  /// Best-effort, online-only check that this device hasn't been revoked
  /// from another device since it last checked in (spec bloc 14). Never
  /// punishes an offline user: any failure (no connectivity, timeout)
  /// defaults to "still authorized" so PIN alone keeps working exactly as
  /// it always has whenever this can't be verified live.
  Future<bool> isDeviceStillAuthorized({required String userId}) async {
    try {
      final instId = await installationId();
      final rows = await _client
          .from('devices')
          .select('id')
          .eq('id', '${instId}_$userId')
          .limit(1)
          // A request that never resolves (present but broken network, a
          // captive portal, a stalled TCP connection) throws nothing on its
          // own - without this, AppGate's _evaluate() would await this
          // forever and the whole app would stay stuck on the splash
          // screen, never even reaching PIN/lock. A real error/timeout both
          // fall into the catch below and keep the same fail-open policy.
          .timeout(const Duration(seconds: 8));
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

  /// Forgets the *currently active* account's local association with this
  /// device: its stored refresh token (so a future email entry can never
  /// silently restore it again without a fresh OTP) and its own `devices`
  /// row (self-revoke). Never touches any *other* account this device also
  /// knows about (spec: switching accounts must never mix up their local
  /// contexts). Must run before signing out, since it needs [currentUser]
  /// to know which account's association to forget.
  Future<void> _forgetCurrentAccountAssociation() async {
    final user = currentUser;
    if (user != null) {
      if (user.email != null) await _forgetKnownAccount(user.email!);
      final instId = await installationId();
      try {
        await _client
            .from('devices')
            .delete()
            .eq('id', '${instId}_${user.id}')
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Best-effort - if offline, the row is simply cleaned up the next
        // time this device (or the account owner from elsewhere) revokes it.
      }
    }
    await _forgetDeviceAuthorization();
  }

  /// "Dissocier ce compte de cet appareil" / vraie déconnexion (spec bloc
  /// 15): the *only* action that makes the currently active account
  /// require a fresh OTP again on this device - even re-entering this
  /// exact same email next time. Deliberately distinct from "Changer de
  /// compte" (spec bloc 11), which never forgets anything and only
  /// switches which already-known account is active.
  Future<void> disconnectFromThisDevice() async {
    await _forgetCurrentAccountAssociation();
    // The local association is already forgotten above - a stalled/failed
    // network sign-out must never leave this call hanging (it would freeze
    // whichever screen awaits it, e.g. AppGate itself re-evaluating after a
    // revocation) or stop the local effect from taking hold.
    try {
      await _client.auth.signOut().timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Same as [disconnectFromThisDevice], but also revokes every other
  /// device's session for this account (spec bloc 6 - "se déconnecter de
  /// tous les appareils"). Other devices' `devices` rows are left in place
  /// (so they still show up under "Appareils connectés" for the user to
  /// see/revoke individually) but their cached session can no longer be
  /// refreshed, so their own next launch naturally falls back to email/OTP.
  Future<void> disconnectFromAllDevices() async {
    await _forgetCurrentAccountAssociation();
    // See disconnectFromThisDevice's identical rationale.
    try {
      await _client.auth.signOut(scope: SignOutScope.global).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(Supabase.instance.client, const FlutterSecureStorage());
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(accountRepositoryProvider).onAuthStateChange;
});
