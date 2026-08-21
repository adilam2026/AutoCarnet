import 'package:autocarnet/features/onboarding_lock/domain/gate_decision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure coverage for AppGate's single central decision function (spec bloc
/// 19): given only whether this device is currently authorized for some
/// account and whether a local PIN is set, it must deterministically pick
/// exactly one of the three pre-HOME screens - never anything else, and
/// never [GateState] itself resolving to a fourth "unlocked" state (that
/// one is only ever reached through an explicit unlock action in AppGate,
/// see gate_decision.dart's doc).
void main() {
  test('an unauthorized device always lands on the email screen, regardless of PIN state', () {
    expect(
      resolveGateState(deviceAuthorized: false, pinSet: false),
      GateState.email,
    );
    expect(
      resolveGateState(deviceAuthorized: false, pinSet: true),
      GateState.email,
      reason: 'a leftover PIN from a previous account must never let an unauthorized device skip email',
    );
  });

  test('an authorized device with no PIN yet must set one up before reaching HOME', () {
    expect(
      resolveGateState(deviceAuthorized: true, pinSet: false),
      GateState.pinSetup,
    );
  });

  test('an authorized device with a PIN already set shows the lock screen, never HOME directly', () {
    expect(
      resolveGateState(deviceAuthorized: true, pinSet: true),
      GateState.locked,
    );
  });
}
