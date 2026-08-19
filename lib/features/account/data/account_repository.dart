import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth so the rest of the app never talks to the SDK
/// directly (bloc 7-9, 15): account creation, email verification via a
/// 6-digit code (never a bare magic link, so nothing depends on deep-link
/// handling working correctly on every device), sign-in, sign-out and the
/// forgot-password flow. The local PIN lock (PinService) stays a
/// separate, purely local concern layered on top of an already-authenticated
/// account - it never substitutes for it (RG-USER-004).
class AccountRepository {
  AccountRepository(this._client);
  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  bool get isSignedIn => currentSession != null;
  bool get isEmailVerified => currentUser?.emailConfirmedAt != null;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Step 1 of account creation - the account exists right away but stays
  /// unverified until [confirmSignUp] succeeds (bloc 8: "le compte n'est
  /// complètement activé qu'après vérification de l'adresse").
  Future<void> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
  }

  /// Step 2 - the 6-digit code from the "Confirm signup" email. Requires
  /// the project's email template to embed {{ .Token }} instead of the
  /// default magic-link URL (see supabase/README.md).
  Future<void> confirmSignUp({required String email, required String code}) async {
    await _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim(),
      token: code.trim(),
    );
  }

  Future<void> resendSignUpCode(String email) async {
    await _client.auth.resend(type: OtpType.signup, email: email.trim());
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Step 1 of "mot de passe oublié" - sends a 6-digit recovery code.
  Future<void> sendPasswordResetCode(String email) async {
    await _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Step 2 - verifying the recovery code signs the user in with a
  /// short-lived recovery session, just enough to call [updatePassword].
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email.trim(),
      token: code.trim(),
    );
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
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
