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
  });

  final String vehicleId;
  final String brand;
  final String model;
  final String? plate;
  final String ownerDisplayName;
  final VehiclePermission role;
  final DateTime expiresAt;
}

/// Deliberately generic where the mandate asks for it (a wrong/nonexistent
/// code must never leak technical detail), and specific for the states
/// that deserve their own clear message (expired/cancelled/already used).
enum InviteRedeemError { invalid, cancelled, alreadyUsed, expired, notAuthenticated, unknown }

class InviteRedeemException implements Exception {
  const InviteRedeemException(this.error);
  final InviteRedeemError error;

  String get message => switch (error) {
        InviteRedeemError.invalid => 'Ce code n\'est pas valide. Vérifiez qu\'il est bien saisi.',
        InviteRedeemError.cancelled => 'Ce code a été annulé par le propriétaire du véhicule.',
        InviteRedeemError.alreadyUsed => 'Ce code a déjà été utilisé.',
        InviteRedeemError.expired => 'Ce code a expiré. Demandez-en un nouveau au propriétaire.',
        InviteRedeemError.notAuthenticated => 'Connectez-vous d\'abord pour rejoindre ce véhicule.',
        InviteRedeemError.unknown => 'Une erreur est survenue. Réessayez.',
      };
}
