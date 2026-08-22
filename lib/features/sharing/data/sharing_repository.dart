import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/invite_code.dart';
import '../domain/vehicle_permission.dart';
import 'sharing_models.dart';

/// All cloud operations for vehicle sharing/collaboration - generating and
/// managing invite codes, redeeming one, and listing/managing who has
/// access to a vehicle. Deliberately online-only (every method needs a
/// live Supabase session): setting up sharing is a coordination act
/// between two real accounts, unlike day-to-day vehicle use, which stays
/// fully offline-first via VehicleSyncService.
class SharingRepository {
  SharingRepository(this._client);
  final SupabaseClient _client;

  Future<VehicleInvite> createInvite({
    required String vehicleId,
    required VehiclePermission role,
    required InviteExpiry expiry,
  }) async {
    // Astronomically unlikely to collide (31^8 combinations), but the code
    // column is UNIQUE - retry on the rare conflict instead of ever
    // silently reusing/weakening a code.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generateInviteCode();
      try {
        final row = await _client
            .from('vehicle_invite_codes')
            .insert({
              'vehicle_id': vehicleId,
              'code': code,
              'role': role.wireValue,
              'expires_at': DateTime.now().toUtc().add(expiry.duration).toIso8601String(),
            })
            .select()
            .single();
        return VehicleInvite(
          id: row['id'] as String,
          vehicleId: row['vehicle_id'] as String,
          rawCode: code,
          role: VehiclePermission.fromWire(row['role'] as String),
          expiresAt: DateTime.parse(row['expires_at'] as String),
          status: row['status'] as String,
        );
      } on PostgrestException catch (e) {
        if (e.code == '23505' && attempt < 4) continue; // unique_violation
        rethrow;
      }
    }
    throw StateError('Impossible de générer un code unique après plusieurs essais.');
  }

  Future<List<VehicleInvite>> listActiveInvites(String vehicleId) async {
    final rows = await _client
        .from('vehicle_invite_codes')
        .select()
        .eq('vehicle_id', vehicleId)
        .eq('status', 'active')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return rows
        .map((row) => VehicleInvite(
              id: row['id'] as String,
              vehicleId: row['vehicle_id'] as String,
              // Never re-shown - only the device that generated it ever
              // saw the plaintext code, right after creation.
              rawCode: null,
              role: VehiclePermission.fromWire(row['role'] as String),
              expiresAt: DateTime.parse(row['expires_at'] as String),
              status: row['status'] as String,
            ))
        .toList();
  }

  Future<void> cancelInvite(String inviteId) async {
    await _client.from('vehicle_invite_codes').update({'status': 'cancelled'}).eq('id', inviteId);
  }

  Future<InvitePreview> previewInvite(String rawInput) async {
    final code = normalizeInviteCodeInput(rawInput);
    try {
      final rows = await _client.rpc('preview_vehicle_invite', params: {'p_code': code});
      final row = (rows as List).first as Map<String, dynamic>;
      return InvitePreview(
        vehicleId: row['vehicle_id'] as String,
        brand: row['brand'] as String,
        model: row['model'] as String,
        plate: row['plate'] as String?,
        ownerDisplayName: row['owner_display_name'] as String? ?? 'Propriétaire',
        role: VehiclePermission.fromWire(row['role'] as String),
        expiresAt: DateTime.parse(row['expires_at'] as String),
        alreadyMember: row['already_member'] as bool? ?? false,
        alreadyOwner: row['already_owner'] as bool? ?? false,
      );
    } on PostgrestException catch (e) {
      throw InviteRedeemException(_mapRedeemError(e), technicalDetail: _technicalDetail(e));
    }
  }

  Future<VehicleInvite> acceptInvite(String rawInput) async {
    final code = normalizeInviteCodeInput(rawInput);
    try {
      final rows = await _client.rpc('accept_vehicle_invite', params: {'p_code': code});
      final row = (rows as List).first as Map<String, dynamic>;
      // out_-prefixed keys (see 0008_rename_accept_invite_out_columns.sql):
      // the function's RETURNS TABLE columns were renamed so they can
      // never again collide with a real table column name inside the
      // function body (the root cause of a live, hard-to-pin-down 42702
      // "ambiguous column" error).
      return VehicleInvite(
        id: '',
        vehicleId: row['out_vehicle_id'] as String,
        rawCode: null,
        role: VehiclePermission.fromWire(row['out_role'] as String),
        expiresAt: DateTime.now(),
        status: 'accepted',
      );
    } on PostgrestException catch (e) {
      throw InviteRedeemException(_mapRedeemError(e), technicalDetail: _technicalDetail(e));
    }
  }

  /// Postgrest error code + message (e.g. '42501: new row violates
  /// row-level security policy...') - only ever attached to
  /// [InviteRedeemError.unknown], where the app has no clear message of
  /// its own. This can't be fixed from the client, but a real rejection
  /// from Postgres/RLS/a constraint needs to be diagnosable from the
  /// device that hit it, not just show a generic "try again".
  String _technicalDetail(PostgrestException e) => '${e.code}: ${e.message}';

  InviteRedeemError _mapRedeemError(PostgrestException e) {
    return switch (e.message) {
      'code_invalid' => InviteRedeemError.invalid,
      'code_cancelled' => InviteRedeemError.cancelled,
      'code_already_used' => InviteRedeemError.alreadyUsed,
      'code_expired' => InviteRedeemError.expired,
      'not_authenticated' => InviteRedeemError.notAuthenticated,
      'already_owner' => InviteRedeemError.alreadyOwner,
      _ => InviteRedeemError.unknown,
    };
  }

  Future<List<VehicleMember>> listMembers(String vehicleId) async {
    final memberRows =
        await _client.from('vehicle_members').select().eq('vehicle_id', vehicleId).order('added_at');
    if (memberRows.isEmpty) return const [];
    final userIds = memberRows.map((r) => r['user_id'] as String).toList();
    final profileRows = await _client.from('profiles').select('id, display_name, email').inFilter('id', userIds);
    final profilesById = {for (final p in profileRows) p['id'] as String: p};
    return memberRows.map((row) {
      final profile = profilesById[row['user_id'] as String];
      return VehicleMember(
        id: row['id'] as String,
        vehicleId: row['vehicle_id'] as String,
        userId: row['user_id'] as String,
        role: VehiclePermission.fromWire(row['role'] as String),
        addedAt: DateTime.parse(row['added_at'] as String),
        lastActivityAt:
            row['last_activity_at'] != null ? DateTime.parse(row['last_activity_at'] as String) : null,
        displayName: profile?['display_name'] as String?,
        email: profile?['email'] as String?,
      );
    }).toList();
  }

  Future<void> updateMemberRole(String memberId, VehiclePermission role) async {
    await _client.from('vehicle_members').update({'role': role.wireValue}).eq('id', memberId);
  }

  Future<void> revokeMember(String memberId) async {
    await _client.from('vehicle_members').delete().eq('id', memberId);
  }

  /// Keeps `profiles.email` current for the signed-in account, so it can be
  /// shown to collaborators on the access-management screen (never read
  /// directly from `auth.users`, which clients can't query at all).
  /// Safe/cheap to call opportunistically on every sign-in.
  Future<void> ensureOwnEmailSynced() async {
    final user = _client.auth.currentUser;
    if (user?.email == null) return;
    await _client.from('profiles').update({'email': user!.email}).eq('id', user.id);
  }
}

final sharingRepositoryProvider = Provider<SharingRepository>((ref) {
  return SharingRepository(Supabase.instance.client);
});
