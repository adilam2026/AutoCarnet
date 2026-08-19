/// The two access levels a vehicle owner can grant a collaborator - never
/// more than these two, deliberately: "Consultation" (read-only) and
/// "Consultation + Modification" (read+write, but never the owner-only
/// actions listed in [ownerOnlyActionLabels]).
enum VehiclePermission {
  viewer,
  editor;

  /// The exact string stored in `vehicle_members.role` / `vehicle_invite_codes.role`.
  String get wireValue => switch (this) {
        VehiclePermission.viewer => 'viewer',
        VehiclePermission.editor => 'editor',
      };

  static VehiclePermission fromWire(String value) => switch (value) {
        'editor' => VehiclePermission.editor,
        _ => VehiclePermission.viewer,
      };

  String get label => switch (this) {
        VehiclePermission.viewer => 'Consultation',
        VehiclePermission.editor => 'Consultation + Modification',
      };

  String get shortLabel => switch (this) {
        VehiclePermission.viewer => 'Lecture seule',
        VehiclePermission.editor => 'Peut modifier',
      };

  String get description => switch (this) {
        VehiclePermission.viewer =>
          'Peut consulter la fiche, l\'historique et les documents du véhicule, sans rien modifier.',
        VehiclePermission.editor =>
          'Peut aussi ajouter et modifier des entretiens, documents, kilométrage... comme le propriétaire, sauf les actions réservées ci-dessous.',
      };
}

/// Actions the mandate reserves strictly to the vehicle's owner, regardless
/// of permission level - shown next to the "Consultation + Modification"
/// option so the difference is explicit, and enforced server-side (RLS +
/// the vehicles_owner_only_delete trigger), never only client-side.
const ownerOnlyActionLabels = <String>[
  'Supprimer définitivement le véhicule',
  'Transférer la propriété du véhicule',
  'Retirer le propriétaire',
  'Modifier les droits du propriétaire',
  'Supprimer le compte du propriétaire',
];

enum InviteExpiry {
  hours24,
  hours48,
  days7;

  Duration get duration => switch (this) {
        InviteExpiry.hours24 => const Duration(hours: 24),
        InviteExpiry.hours48 => const Duration(hours: 48),
        InviteExpiry.days7 => const Duration(days: 7),
      };

  String get label => switch (this) {
        InviteExpiry.hours24 => '24 heures',
        InviteExpiry.hours48 => '48 heures',
        InviteExpiry.days7 => '7 jours',
      };

  static const sensibleDefault = InviteExpiry.days7;
}
