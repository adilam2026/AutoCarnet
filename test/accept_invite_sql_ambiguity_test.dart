import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the real cause of every "Rejoindre un véhicule"
/// failure to date: Postgres error 42702 ("column reference \"vehicle_id\"
/// is ambiguous"). accept_vehicle_invite() is declared `returns table
/// (vehicle_id uuid, ...)`, and PL/pgSQL implicitly declares an OUT
/// variable per returned column - so a bare `vehicle_id` inside the
/// function body is genuinely ambiguous between that OUT parameter and
/// vehicle_members.vehicle_id. One statement used it bare (unchanged since
/// the very first migration this feature shipped in), which meant the
/// membership row was already inserted successfully by the time the
/// function then errored out - every accept looked like a total failure
/// even though half of it had actually worked.
///
/// This can't be exercised against a live Postgres instance from this
/// sandbox, so this is a static text guard on the migration SQL itself:
/// it can't prove the fix compiles/executes correctly server-side, but it
/// does lock in that the exact broken line is gone and the qualified
/// replacement is present, so it can't silently regress back to the bare
/// form in a future edit.
void main() {
  test(
      'accept_vehicle_invite\'s vehicle_members "bump last_activity_at" UPDATE never uses a bare, '
      'ambiguous vehicle_id/user_id again', () {
    final rawSql = File('supabase/migrations/0007_fix_ambiguous_vehicle_id.sql').readAsStringSync();
    // Strip comment lines first - the migration's own explanatory header
    // quotes the old broken line as an example, which would otherwise
    // trivially (and misleadingly) "match" the forbidden pattern below.
    final executableSql = rawSql
        .split('\n')
        .where((line) => !line.trim().startsWith('--'))
        .join('\n');

    expect(
      executableSql,
      isNot(contains('where vehicle_id = v_row.vehicle_id and user_id = auth.uid()')),
      reason: 'this exact bare (unqualified) form is what produced the live 42702 error',
    );
    expect(
      executableSql,
      contains('where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid()'),
      reason: 'the fix must qualify both columns through the table alias',
    );
  });
}
