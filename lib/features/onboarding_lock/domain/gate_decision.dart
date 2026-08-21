/// The three screens a device can land on once account authentication
/// itself is settled (spec bloc 19's DEVICE_AUTHORIZED_NEEDS_PIN_SETUP /
/// DEVICE_AUTHORIZED_LOCKED, plus EMAIL for everything before that). HOME
/// (AUTHENTICATED_READY) is deliberately not produced by this resolver -
/// it's only ever entered through an explicit unlock action (PIN success,
/// biometric success, PIN just created/reset), never recomputed from
/// persisted facts alone, so re-evaluating this function after unlocking
/// can never itself send the user back into the app.
enum GateState { email, pinSetup, locked }

/// Pure decision logic for [AppGate]'s central "which screen does this
/// device show right now?" question - extracted out of the widget so it's
/// directly testable without a live Supabase session, secure storage, or a
/// network call, and so there is exactly one place in the codebase that
/// makes this decision (spec bloc 19: "Aucun AppGate / AccountGate /
/// Provider / listener ne doit prendre une décision concurrente").
///
/// [deviceAuthorized] is true only when *all* of the following hold: this
/// device remembers being authorized for some account (secure storage),
/// there is a live Supabase session right now, and that session belongs to
/// the exact same account the device remembers - see
/// AppGate._isDeviceAuthorizedAndSignedIn. Anything else (never
/// authorized, signed out, or - should it ever happen - a session for a
/// *different* account than what this device remembers) always fails
/// closed to [GateState.email], never guesses.
GateState resolveGateState({
  required bool deviceAuthorized,
  required bool pinSet,
}) {
  if (!deviceAuthorized) return GateState.email;
  return pinSet ? GateState.locked : GateState.pinSetup;
}
