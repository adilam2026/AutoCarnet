import '../domain/vehicle_permission.dart';

class VehicleInvite {
  const VehicleInvite({
    required this.id,
    required this.vehicleId,
    required this.rawCode,
    required this.role,
    required this.expiresAt,
    required this.status,
  });

  final String id;
  final String vehicleId;
  // Only ever populated right after this device generates the code - a
  // code is never re-readable in plaintext once fetched back from the
  // list endpoint (the DB doesn't need to store it any differently, but
  // the app deliberately doesn't re-display an old code as if it were
  // fresh - see SharingRepository.listActiveInvites).
  final String? rawCode;
  final VehiclePermission role;
  final DateTime expiresAt;
  final String status;
}

class VehicleMember {
  const VehicleMember({
    required this.id,
    required this.vehicleId,
    required this.userId,
    required this.role,
    required this.addedAt,
    this.lastActivityAt,
    this.displayName,
    this.email,
  });

  final String id;
  final String vehicleId;
  final String userId;
  final VehiclePermission role;
  final DateTime addedAt;
  final DateTime? lastActivityAt;
  final String? displayName;
  final String? email;

  String get displayLabel => (displayName?.trim().isNotEmpty ?? false) ? displayName! : (email ?? userId);
}

class InvitePreview {
  const InvitePreview({
    required this.vehicleId,
    required this.brand,
    required this.model,
    this.plate,
    required this.ownerDisplayName,
    required this.role,
    required this.expiresAt,
    required this.alreadyMember,
    required this.alreadyOwner,
  });

  final String vehicleId;
  final String brand;
  final String model;
  final String? plate;
  final String ownerDisplayName;
  final VehiclePermission role;
  final DateTime expiresAt;

  /// The caller already has a `vehicle_members` row for this vehicle
  /// (e.g. joined earlier via a different code). Redeeming must not
  /// create a second membership row - the UI offers "Ouvrir le véhicule"
  /// instead of "Rejoindre".
  final bool alreadyMember;

  /// The caller is this vehicle's owner (`vehicles.user_id`), typing
  /// their own share code. Owners already have full access outside
  /// `vehicle_members` - redeeming must never consume the code or create
  /// a redundant self-membership row.
  final bool alreadyOwner;
}

/// Deliberately generic where the mandate asks for it (a wrong/nonexistent
/// code must never leak technical detail), and specific for the states
/// that deserve their own clear message (expired/cancelled/already used).
enum InviteRedeemError {
  invalid,
  cancelled,
  alreadyUsed,
  expired,
  notAuthenticated,
  alreadyOwner,
  unknown,
}

class InviteRedeemException implements Exception {
  const InviteRedeemException(this.error, {this.technicalDetail});
  final InviteRedeemError error;

  /// The raw Postgrest/backend error text, only ever populated for
  /// [InviteRedeemError.unknown] - i.e. an error this app doesn't have a
  /// specific, clear message for. Never shown for a recognized error
  /// (those already have a clear message of their own), and never a
  /// substitute for fixing the actual cause - it exists so a real
  /// backend rejection is diagnosable from the device itself instead of
  /// only ever showing a generic "try again".
  final String? technicalDetail;

  String get message => switch (error) {
        InviteRedeemError.invalid => 'Code de partage invalide.',
        InviteRedeemError.cancelled => 'Cette invitation n\'est plus disponible.',
        InviteRedeemError.alreadyUsed => 'Cette invitation n\'est plus disponible.',
        InviteRedeemError.expired => 'Ce code de partage a expiré.',
        InviteRedeemError.notAuthenticated => 'Connectez-vous d\'abord pour rejoindre ce véhicule.',
        InviteRedeemError.alreadyOwner => 'Ce véhicule vous appartient déjà.',
        InviteRedeemError.unknown => 'Une erreur est survenue. Réessayez.',
      };
}
