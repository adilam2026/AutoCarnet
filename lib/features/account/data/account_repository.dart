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
    await _client.auth.signInWithOtp(
      email: email.trim(),
      data: (displayName != null && displayName.trim().isNotEmpty)
          ? {'display_name': displayName.trim()}
          : null,
    );
  }

  /// Verifying the code signs the user in directly - there's no separate
  /// password to set, this call alone produces a live session. Requires the
  /// project's "Magic Link" email template to embed {{ .Token }} instead of
  /// the default link (see supabase/README.md).
  Future<void> verifyEmailCode({required String email, required String code}) async {
    await _client.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
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
