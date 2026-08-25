import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026 sync-hardening pass (after the GLC data-loss report): the
/// outbox is a diagnostic/retry ledger layered on top of each table's own
/// syncStatus/version - these tests lock in its state-machine semantics in
/// isolation, independent of any real network call.
void main() {
  late AppDatabase db;
  late SyncOutboxRepository outbox;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = SyncOutboxRepository(db);
  });

  tearDown(() => db.close());

  test('enqueue creates exactly one row per (entityType, entityId), never '
      'duplicated on retry (TEST 6: relancer plusieurs fois la même '
      'opération ne duplique rien)', () async {
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'update');

    expect(await outbox.pendingCount(), 1);
  });

  test('markSynced removes the row only after being called - never before', () async {
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    expect(await outbox.pendingCount(), 1);

    await outbox.markSynced('vehicle', 'v1');
    expect(await outbox.pendingCount(), 0);
  });

  test('markFailed increments retry_count and records the error each time, '
      'without ever duplicating the entity\'s outbox row', () async {
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');

    await outbox.markFailed('vehicle', 'v1', 'network error');
    var rows = await outbox.failing();
    expect(rows, hasLength(1));
    expect(rows.single.retryCount, 1);
    expect(rows.single.lastError, 'network error');
    expect(rows.single.syncStatus, 'failed');

    await outbox.markFailed('vehicle', 'v1', 'timeout');
    rows = await outbox.failing();
    expect(rows, hasLength(1), reason: 'still one row, not a second one');
    expect(rows.single.retryCount, 2);
    expect(rows.single.lastError, 'timeout');
  });

  test('markSyncing stamps lastAttemptAt without removing or duplicating '
      'the row', () async {
    await outbox.enqueue(entityType: 'fuel', entityId: 'f1', operation: 'create');
    await outbox.markSyncing('fuel', 'f1');

    final rows = await outbox.failing(); // not failing yet, just checking count via pendingCount
    expect(rows, isEmpty);
    expect(await outbox.pendingCount(), 1);
  });

  test('pendingCount aggregates across every entity type at once - the '
      '"3 modifications en attente" indicator', () async {
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    await outbox.enqueue(entityType: 'maintenance', entityId: 'm1', operation: 'create');
    await outbox.enqueue(entityType: 'fuel', entityId: 'f1', operation: 'update');

    expect(await outbox.pendingCount(), 3);

    await outbox.markSynced('maintenance', 'm1');
    expect(await outbox.pendingCount(), 2);
  });

  test('recordSuccess/recordError persist a single SyncMeta row, updated '
      'in place - the "dernière synchronisation réussie / dernière erreur" '
      'indicator', () async {
    expect(await outbox.watchMetaOnce(), isNull);

    await outbox.recordSuccess();
    var meta = await outbox.watchMetaOnce();
    expect(meta!.lastSuccessAt, isNotNull);
    expect(meta.lastErrorMessage, isNull);

    await outbox.recordError('vehicles: connection refused');
    meta = await outbox.watchMetaOnce();
    expect(meta!.lastErrorMessage, 'vehicles: connection refused');
    // Recording an error never wipes the last known success.
    expect(meta.lastSuccessAt, isNotNull);
  });

  test('watchFailedCount reflects only rows currently in "failed" status - '
      'mission point 6\'s "nombre d\'échecs" indicator', () async {
    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    await outbox.enqueue(entityType: 'fuel', entityId: 'f1', operation: 'create');
    expect(await outbox.watchFailedCount().first, 0);

    await outbox.markFailed('vehicle', 'v1', 'network error');
    expect(await outbox.watchFailedCount().first, 1);

    await outbox.markSynced('vehicle', 'v1');
    expect(await outbox.watchFailedCount().first, 0);
  });

  test('watchLastAttemptAt reports the most recent attempt across every '
      'outbox entry, not just the last full coordinator pass', () async {
    expect(await outbox.watchLastAttemptAt().first, isNull);

    await outbox.enqueue(entityType: 'vehicle', entityId: 'v1', operation: 'create');
    await outbox.markSyncing('vehicle', 'v1');
    final firstAttempt = await outbox.watchLastAttemptAt().first;
    expect(firstAttempt, isNotNull);

    // Drift's default NativeDatabase stores DateTime at second precision -
    // a sub-second gap would round-trip identically and make this
    // assertion flaky.
    await Future<void>.delayed(const Duration(seconds: 1));
    await outbox.enqueue(entityType: 'fuel', entityId: 'f1', operation: 'create');
    await outbox.markFailed('fuel', 'f1', 'timeout');
    final secondAttempt = await outbox.watchLastAttemptAt().first;
    expect(secondAttempt!.isAfter(firstAttempt!), isTrue);
  });

  group('syncOutboxOperationFor', () {
    test('a never-synced row (version 0) is a create', () {
      expect(syncOutboxOperationFor(version: 0, isDeleted: false), 'create');
    });

    test('a soft-deleted row is a delete (tombstone), regardless of version', () {
      expect(syncOutboxOperationFor(version: 3, isDeleted: true), 'delete');
    });

    test('anything else is an update', () {
      expect(syncOutboxOperationFor(version: 2, isDeleted: false), 'update');
    });
  });
}
