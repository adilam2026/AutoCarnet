/// Pure decision logic for [AppGate]'s "must this device go back through
/// email/OTP before PIN/biometric are even considered?" check - extracted
/// out of the widget so it's directly testable without a live Supabase
/// session or secure storage.
///
/// [hasEverLinkedCloudAccount] is true once this device has *ever*
/// completed a real cloud sign-in (survives a sign-out - see
/// AccountRepository.lastCloudUserId); [isSignedIn] reflects the *live*
/// Supabase session right now. Only the combination of "had one" and "no
/// longer signed in" forces a fresh email/OTP pass - a device that never
/// had a cloud account at all is unaffected, and PIN/biometric alone
/// stays a legitimate unlock for it.
bool mustReauthenticateViaEmail({
  required bool hasEverLinkedCloudAccount,
  required bool isSignedIn,
}) {
  return hasEverLinkedCloudAccount && !isSignedIn;
}
