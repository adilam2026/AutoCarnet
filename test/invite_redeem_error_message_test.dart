import 'package:autocarnet/features/sharing/data/sharing_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the exact wording mandated for the "Rejoindre un
/// véhicule" journey - a screen must never surface Drift/Postgrest's raw
/// technical exception text (that's what crashed with "Expected exactly
/// one element, but got 0" in the first place), only these clear messages.
void main() {
  group('InviteRedeemException.message (pure)', () {
    test('TEST 3: invalid code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.invalid).message,
        'Code de partage invalide.',
      );
    });

    test('TEST 5: expired code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.expired).message,
        'Ce code de partage a expiré.',
      );
    });

    test('a cancelled invitation', () {
      expect(
        const InviteRedeemException(InviteRedeemError.cancelled).message,
        'Cette invitation n\'est plus disponible.',
      );
    });

    test('an already-used code reads the same way as a cancelled one - both '
        '"no longer available" from the joiner\'s point of view', () {
      expect(
        const InviteRedeemException(InviteRedeemError.alreadyUsed).message,
        'Cette invitation n\'est plus disponible.',
      );
    });

    test('owner redeeming their own code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.alreadyOwner).message,
        'Ce véhicule vous appartient déjà.',
      );
    });
  });
}
