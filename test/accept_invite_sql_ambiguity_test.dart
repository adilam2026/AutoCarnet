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
/// Confirmed live *twice*: once directly (Postgres logs showing 42702),
/// and a second time after 0007 alone had been applied, because
/// 0006_invite_already_member_owner.sql *also* defines
/// accept_vehicle_invite() (it was written before the bug was found) and
/// still had the same bare line - applying 0006 after 0007 (a very easy
/// mistake given both files touch the same function) silently reintroduced
/// it. Both files are checked here so neither can regress independently of
/// the other, whichever order they're (re-)applied in.
///
/// This can't be exercised against a live Postgres instance from this
/// sandbox, so this is a static text guard on the migration SQL itself:
/// it can't prove the fix compiles/executes correctly server-side, but it
/// does lock in that the exact broken line is gone and the qualified
/// replacement is present, so it can't silently regress back to the bare
/// form in a future edit.
void main() {
  for (final path in [
    'supabase/migrations/0006_invite_already_member_owner.sql',
    'supabase/migrations/0007_fix_ambiguous_vehicle_id.sql',
  ]) {
    test(
        '$path: accept_vehicle_invite\'s vehicle_members "bump last_activity_at" UPDATE never uses '
        'a bare, ambiguous vehicle_id/user_id', () {
      final rawSql = File(path).readAsStringSync();
      // Strip comment lines first - both migrations' own explanatory
      // headers quote the old broken line as an example, which would
      // otherwise trivially (and misleadingly) "match" the forbidden
      // pattern below.
      final executableSql =
          rawSql.split('\n').where((line) => !line.trim().startsWith('--')).join('\n');

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
}
