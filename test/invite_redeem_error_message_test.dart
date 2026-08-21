import 'package:autocarnet/features/sharing/data/sharing_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the exact wording mandated for the "Rejoindre un
/// véhicule" journey - a screen must never surface Drift/Postgrest's raw
/// technical exception text (that's what crashed with "Expected exactly
/// one element, but got 0" in the first place), only these clear messages.
void main() {
  group('InviteRedeemException.message (pure)', () {
    test('TEST B: no invitation found', () {
      expect(
        const InviteRedeemException(InviteRedeemError.invalid).message,
        'Code invalide ou introuvable.',
      );
    });

    test('TEST C: expired code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.expired).message,
        'Ce code de partage a expiré. Demandez un nouveau code au propriétaire.',
      );
    });

    test('TEST D: already-used code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.alreadyUsed).message,
        'Cette invitation n\'est plus valide.',
      );
    });

    test('a cancelled code reads the same way as an already-used one - both '
        '"no longer valid" from the joiner\'s point of view', () {
      expect(
        const InviteRedeemException(InviteRedeemError.cancelled).message,
        'Cette invitation n\'est plus valide.',
      );
    });

    test('TEST F: owner redeeming their own code', () {
      expect(
        const InviteRedeemException(InviteRedeemError.alreadyOwner).message,
        'Vous êtes déjà propriétaire de ce véhicule.',
      );
    });
  });
}
