import 'dart:convert';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/core/sync/vehicle_sync_diagnostics.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, diagnostic-screen validation: proves [VehicleSyncDiagnosticRunner]
/// genuinely drives the REAL [VehicleSyncService.syncNow] (not a re-implementation,
/// not a mock that just returns HTTP 200) for the exact three shapes the real-device
/// incident report needs distinguished on-screen without adb: a clean success, a
/// rejected-then-visible-as-failed push, and - the actual reported bug pattern -
/// a vehicle whose LOCAL syncStatus says "synced" while nothing was ever pushed,
/// which only a live, independent Supabase check (not this report alone) can catch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => call.method == 'check' ? ['wifi'] : null,
  );

  String fakeJwt({required String sub, required Duration validFor}) {
    String segment(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final header = segment({'alg': 'none', 'typ': 'JWT'});
    final exp = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
    final payload = segment({'sub': sub, 'exp': exp, 'role': 'authenticated'});
    return '$header.$payload.fake-signature';
  }

  Future<void> signIn(SupabaseClient client, String userId) async {
    final sessionJson = jsonEncode({
      'access_token': fakeJwt(sub: userId, validFor: const Duration(hours: 1)),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'fake-refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'email': 'diag@example.com',
        'created_at': DateTime.now().toIso8601String(),
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    });
    await client.auth.recoverSession(sessionJson);
  }

  late AppDatabase db;
  late SupabaseClient client;
  late _FakeCloudHttpClient cloud;
  late VehicleRepository vehicleRepo;
  late VehicleSyncService vehicleSync;
  late VehicleSyncDiagnosticRunner runner;
  const userId = 'diag-test-user';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cloud = _FakeCloudHttpClient(currentUserId: userId);
    client = SupabaseClient(
      'https://example.invalid.supabase.co',
      'anon-key-test',
      httpClient: cloud,
    );
    await signIn(client, userId);

    final outbox = SyncOutboxRepository(db);
    final conflicts = ConflictRepository(db);
    // No SyncCoordinator passed in (null) so VehicleRepository's own
    // fire-and-forget _nudgeSync() is a no-op - runFor() below is the only
    // thing allowed to trigger a push in these tests, for a fully
    // deterministic before/after per step.
    vehicleRepo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db), null, outbox);
    vehicleSync = VehicleSyncService(db, () => client, conflicts, outbox);
    runner = VehicleSyncDiagnosticRunner(db, vehicleSync, () => client);
  });

  tearDown(() => db.close());

  test(
      'SUCCÈS - every one of the 11 steps reports OK, in order, with the '
      'exact same real syncNow() that production uses', () async {
    final vehicleId = await vehicleRepo.createVehicle(
      brand: 'Volkswagen',
      model: 'Tiguan',
      currentMileage: 95600,
    );

    final report = await runner.runFor(vehicleId);

    expect(report.steps, hasLength(11));
    for (final step in report.steps) {
      expect(step.status, DiagnosticStepStatus.ok, reason: step.label);
    }
    expect(cloud.tables['vehicles']!.any((r) => r['id'] == vehicleId), isTrue,
        reason: 'the real pipeline must have actually reached Supabase, not just '
            'returned an HTTP 200 from a mock that never inspects the payload');
    final after = await vehicleRepo.getOne(vehicleId);
    expect(after.syncStatus, 'synced');
  });

  test(
      'ÉCHEC RÉEL - Supabase rejette le push : les étapes 9, 10 et 11 sont '
      'ÉCHEC avec le texte technique exact de l\'erreur, jamais masquées en '
      '"synced"', () async {
    cloud.failInsertsUntilAttempt = 999; // reject every attempt in this test

    final vehicleId = await vehicleRepo.createVehicle(
      brand: 'Volkswagen',
      model: 'Tiguan',
      currentMileage: 95600,
    );

    final report = await runner.runFor(vehicleId);
    expect(report.steps, hasLength(11));
    final step8 = report.steps[7];
    final step9 = report.steps[8];
    final step10 = report.steps[9];
    final step11 = report.steps[10];

    expect(step8.status, DiagnosticStepStatus.ok, reason: 'the INSERT was genuinely attempted');
    expect(step9.status, DiagnosticStepStatus.failed);
    expect(step9.detail, contains('row-level security'));
    expect(step10.status, DiagnosticStepStatus.failed);
    expect(step11.status, DiagnosticStepStatus.failed);
    expect(step11.detail, contains('pendingSync'));
    expect(cloud.tables['vehicles']?.any((r) => r['id'] == vehicleId) ?? false, isFalse);
  });

  test(
      'FANTÔME - un véhicule marqué "synced" localement sans jamais avoir '
      'été réellement poussé (exactement le scénario Volkswagen Tiguan '
      'rapporté) : le rapport de pipeline seul seul ne peut pas le voir '
      '(rien n\'est à envoyer), mais une vérification cloud indépendante '
      'révèle l\'absence réelle - la contradiction que ce diagnostic doit '
      'rendre visible', () async {
    final vehicleId = await vehicleRepo.createVehicle(
      brand: 'Volkswagen',
      model: 'Tiguan',
      currentMileage: 95600,
    );
    // Simulates exactly the reported defect class: syncStatus flipped to
    // "synced" (e.g. by a defect elsewhere, or a since-fixed bug) with no
    // outbox trace left, while the row never actually reached
    // public.vehicles - cloud.tables stays empty for this id throughout.
    await (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId)))
        .write(const VehiclesCompanion(syncStatus: Value('synced')));
    await (db.delete(db.syncOutbox)..where((o) => o.entityId.equals(vehicleId))).go();

    final report = await runner.runFor(vehicleId);
    expect(report.steps, hasLength(11));
    final step8 = report.steps[7];
    final step11 = report.steps[10];

    expect(step8.status, DiagnosticStepStatus.notRun,
        reason: 'nothing was pending, so no push was even attempted this run');
    expect(step8.detail, contains('déjà marqué synced'));
    expect(step11.status, DiagnosticStepStatus.ok,
        reason: 'the local report genuinely cannot see the problem by itself - '
            'this is exactly why a separate live cloud check exists');

    // The independent ground truth (what SyncDiagnosticsScreen's "Vérifier
    // dans le cloud" button performs) must show the contradiction plainly.
    final liveRows =
        await client.from('vehicles').select().eq('id', vehicleId).limit(1);
    expect(liveRows, isEmpty,
        reason: 'ABSENT de public.vehicles despite the local report saying OK '
            'end-to-end - the exact mismatch this diagnostic screen exists to '
            'surface');
  });
}

class _FakeCloudHttpClient extends http.BaseClient {
  _FakeCloudHttpClient({required this.currentUserId});

  final String currentUserId;
  final Map<String, List<Map<String, dynamic>>> tables = {};

  /// Every insert attempt up to and including this count is rejected with a
  /// synthetic RLS-style 403, exactly like a real Supabase-side rejection.
  /// 0 (default) means every insert succeeds.
  int failInsertsUntilAttempt = 0;
  int insertAttempts = 0;

  List<Map<String, dynamic>> _tableFor(Uri url) =>
      tables.putIfAbsent(url.pathSegments.last, () => []);

  Map<String, String> _eqFilters(Map<String, String> query) {
    final filters = <String, String>{};
    for (final entry in query.entries) {
      if (entry.value.startsWith('eq.')) {
        filters[entry.key] = entry.value.substring(3);
      }
    }
    return filters;
  }

  bool _matches(Map<String, dynamic> row, Map<String, String> filters) {
    for (final entry in filters.entries) {
      if (row[entry.key]?.toString() != entry.value) return false;
    }
    return true;
  }

  http.StreamedResponse _json(http.BaseRequest request, int status, Object body) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = _tableFor(request.url);
    final filters = _eqFilters(request.url.queryParameters);

    switch (request.method) {
      case 'POST':
        insertAttempts++;
        if (insertAttempts <= failInsertsUntilAttempt) {
          return _json(request, 403, {
            'message': 'new row violates row-level security policy',
            'code': '42501',
          });
        }
        final bytes = await request.finalize().toBytes();
        final decoded = jsonDecode(utf8.decode(bytes));
        final incoming = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : [decoded as Map<String, dynamic>];
        for (final row in incoming) {
          final stored = Map<String, dynamic>.from(row);
          stored.putIfAbsent('user_id', () => currentUserId);
          rows.removeWhere((r) => r['id'] == stored['id']);
          rows.add(stored);
        }
        return _json(request, 201, const []);

      case 'PATCH':
        final bytes = await request.finalize().toBytes();
        final patch = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final matched = rows.where((r) => _matches(r, filters)).toList();
        for (final row in matched) {
          row.addAll(patch);
        }
        return _json(request, 200, matched.map((r) => {'id': r['id']}).toList());

      case 'GET':
        final matched = rows.where((r) => _matches(r, filters)).toList();
        return _json(request, 200, matched);

      default:
        return _json(request, 200, const []);
    }
  }
}
