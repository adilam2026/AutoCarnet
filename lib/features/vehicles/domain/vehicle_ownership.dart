import '../../../core/database/database.dart';

/// Whether the signed-in account (or lack thereof) is this vehicle's
/// owner. `ownerId == null` means the vehicle has never been synced to the
/// cloud (created fully offline, or no cloud account at all) - the current
/// device's user is its de facto sole owner either way, so it counts as
/// owned. Pure and offline-safe: never needs a network call, since
/// [Vehicle.ownerId] is populated locally the moment the vehicle is first
/// pulled/pushed (see vehicle_sync_mapping.dart).
bool isVehicleOwnedByCurrentUser(Vehicle vehicle, String? currentUserId) {
  return vehicle.ownerId == null || vehicle.ownerId == currentUserId;
}

/// Whether this device can create/modify data on the vehicle: true for the
/// owner, or a collaborator whose cached [Vehicle.myRole] is 'editor'.
/// False for a 'viewer' collaborator - checked client-side (not just left
/// to RLS) because a viewer's local edit would otherwise appear to
/// "succeed" offline-first and then simply never be able to sync,
/// silently diverging forever instead of being refused up front.
bool canEditVehicle(Vehicle vehicle, String? currentUserId) {
  if (isVehicleOwnedByCurrentUser(vehicle, currentUserId)) return true;
  return vehicle.myRole == 'editor';
}
