import 'package:autocarnet/features/onboarding_lock/domain/gate_decision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for a real anomaly found during the session/logout
/// audit: after a genuine account sign-out, the app used to decide
/// PIN-vs-account-auth purely from "does a local profile exist?" - which
/// stays true forever (sign-out never deletes it) - so the local PIN alone
/// could re-enter a cloud account whose Supabase session was already gone.
/// mustReauthenticateViaEmail is the extracted fix: it must say yes
/// whenever a device has ever linked a cloud account but isn't currently
/// signed in, and never block a device that has no cloud account history
/// at all.
void main() {
  test('a device that was never cloud-linked never needs to reauthenticate via email', () {
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: false, isSignedIn: false),
      isFalse,
    );
  });

  test('a device with a live session never needs to reauthenticate, linked or not', () {
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: true, isSignedIn: true),
      isFalse,
    );
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: false, isSignedIn: true),
      isFalse,
    );
  });

  test(
      'a device that was cloud-linked but has no live session must go through email again - '
      'this is the exact bug: PIN/biometric alone must never be enough here', () {
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: true, isSignedIn: false),
      isTrue,
    );
  });

  test(
      'an authenticated session used entirely offline is NOT a logout - Supabase keeps '
      '`currentSession` (and therefore isSignedIn) non-null without connectivity; only an '
      'explicit signOut() call clears it, so PIN/biometric stay a legitimate unlock offline',
      () {
    // isSignedIn: true here represents a live, cached session being used
    // with no network reachable - distinct from a real sign-out, which
    // is the only thing that ever makes isSignedIn false.
    expect(
      mustReauthenticateViaEmail(hasEverLinkedCloudAccount: true, isSignedIn: true),
      isFalse,
      reason: 'an offline-but-authenticated session must never be treated as a logout',
    );
  });
}
