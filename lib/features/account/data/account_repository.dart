import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth so the rest of the app never talks to the SDK
/// directly (bloc 7-9, 15): account creation and sign-in are both a single
/// passwordless step - a 6-digit code sent to the email address (never a
/// bare magic link, so nothing depends on deep-link handling working
/// correctly on every device) - plus sign-out. The local PIN lock
/// (PinService) stays a separate, purely local concern layered on top of an
/// already-authenticated account - it never substitutes for it
/// (RG-USER-004).
class AccountRepository {
  AccountRepository(this._client);
  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isSignedIn => currentSession != null;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Sends a 6-digit code to [email]. This single call covers both signup
  /// and sign-in - Supabase's email OTP endpoint auto-creates the account on
  /// a new address and just re-sends the code on an existing one, so the app
  /// never has to know in advance which case it's in. [displayName] is only
  /// used the first time (a new address): it's carried as user metadata so
  /// the handle_new_user() trigger can seed the profile with it.
  Future<void> sendEmailCode(String email, {String? displayName}) async {
    final trimmedEmail = email.trim();
    try {
      await _client.auth.signInWithOtp(
        email: trimmedEmail,
        data: (displayName != null && displayName.trim().isNotEmpty)
            ? {'display_name': displayName.trim()}
            : null,
      );
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
  /// supabase/README.md. A template that still contains a clickable
  /// confirmation link lets email security scanners silently "click" it and
  /// consume the underlying one-time token before the user ever types the
  /// code, which surfaces here as the exact same "Token has expired or is
  /// invalid" error as a real expiry - that's a Supabase-documented failure
  /// mode, not something this call can detect or work around.
  ///
  /// `email` is Supabase's unified type for a numeric code (as opposed to a
  /// literal magic-link click) and is correct for both a brand new account
  /// and a returning one *given* the template only ever shows the token -
  /// but a handful of real Supabase projects still mint a brand new user's
  /// very first code under the `signup` type internally (a known GoTrue
  /// quirk), so a single retry under that type follows the same "not the
  /// bug's fault, but not free" account for it before giving up.
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

  /// Closes the account session on this device only - never deletes cloud
  /// data (bloc 6).
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// RG bloc 6 - "se déconnecter de tous les appareils": revokes every
  /// refresh token for this account, not just the current device's.
  Future<void> signOutEverywhere() async {
    await _client.auth.signOut(scope: SignOutScope.global);
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(Supabase.instance.client);
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(accountRepositoryProvider).onAuthStateChange;
});
