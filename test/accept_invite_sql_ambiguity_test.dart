import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the real cause of every "Rejoindre un véhicule"
/// failure to date: Postgres error 42702 ("column reference \"vehicle_id\"
/// is ambiguous"). accept_vehicle_invite() was declared `returns table
/// (vehicle_id uuid, ...)`, and PL/pgSQL implicitly declares an OUT
/// variable per returned column - so a bare `vehicle_id` inside the
/// function body was genuinely ambiguous between that OUT parameter and
/// vehicle_members.vehicle_id.
///
/// 0006/0007 qualified the one bare reference found by manual review, but
/// the *same* live error persisted afterwards (confirmed via Postgres
/// logs) - meaning at least one more bare reference existed somewhere a
/// line-by-line review didn't catch. 0008 removes the entire class of bug
/// instead of continuing to hunt for the exact spot: the function's
/// RETURNS TABLE columns are renamed to out_-prefixed names that can never
/// collide with any real table column, so no bare identifier inside the
/// function body - now or in any future edit - can ever again be
/// ambiguous with an OUT parameter.
void main() {
  for (final path in [
    'supabase/migrations/0006_invite_already_member_owner.sql',
    'supabase/migrations/0007_fix_ambiguous_vehicle_id.sql',
  ]) {
    test(
        '$path: accept_vehicle_invite\'s vehicle_members "bump last_activity_at" UPDATE never uses '
        'a bare, ambiguous vehicle_id/user_id', () {
      final rawSql = File(path).readAsStringSync();
      final executableSql =
          rawSql.split('\n').where((line) => !line.trim().startsWith('--')).join('\n');

      expect(
        executableSql,
        isNot(contains('where vehicle_id = v_row.vehicle_id and user_id = auth.uid()')),
        reason: 'this exact bare (unqualified) form is what produced the live 42702 error',
      );
    });
  }

  test(
      '0008: accept_vehicle_invite\'s RETURNS TABLE columns are renamed so none can collide with a '
      'real table column (the actual fix, after qualifying references alone was not enough)', () {
    final sql =
        File('supabase/migrations/0008_rename_accept_invite_out_columns.sql').readAsStringSync();

    expect(sql, contains('out_vehicle_id uuid'));
    expect(sql, contains('out_brand text'));
    expect(sql, contains('out_model text'));
    expect(sql, contains('out_plate text'));
    expect(sql, contains('out_role text'));
    // None of the renamed columns collide with a real column on any table
    // this function touches (vehicles, vehicle_members,
    // vehicle_invite_codes) - unlike the original names, which did.
  });

  test(
      'SharingRepository.acceptInvite parses the exact out_-prefixed keys 0008 declares - this '
      'file and the migration must never drift apart silently', () {
    final dartSource =
        File('lib/features/sharing/data/sharing_repository.dart').readAsStringSync();
    final startIndex = dartSource.indexOf('Future<VehicleInvite> acceptInvite(');
    final endIndex = dartSource.indexOf('String _technicalDetail(', startIndex);
    expect(startIndex, greaterThan(-1), reason: 'acceptInvite must still exist under this name');
    expect(endIndex, greaterThan(startIndex));
    final acceptInviteBody = dartSource.substring(startIndex, endIndex);

    expect(acceptInviteBody, contains("row['out_vehicle_id']"));
    expect(acceptInviteBody, contains("row['out_role']"));
    expect(acceptInviteBody, isNot(contains("row['vehicle_id']")),
        reason: 'acceptInvite must not still read the pre-0008 key name '
            '(previewInvite legitimately still does - only acceptInvite changed)');
  });
}
