import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/providers.dart';
import '../utils/id_generator.dart';
import '../../features/account/data/account_repository.dart';

/// The kinds of collaboration events that ever produce a notification -
/// kept as a closed set so the UI can pick one icon/label per type instead
/// of guessing from free text.
enum AppNotificationType {
  memberJoined,
  memberRemoved,
  roleChanged,
  remoteEdit,
  remoteDelete,
  syncConflict,
}

/// Persistent, per-device notification center (see AppNotifications' class
/// doc for why this is never synced across devices). Populated from two
/// places only: SyncCoordinator's realtime callbacks (a collaborator's
/// change, skipping this device's own echoes) and conflict detection
/// inside each *SyncService's push step.
class NotificationRepository {
  NotificationRepository(this._db);
  final AppDatabase _db;

  Future<void> add({
    required String accountId,
    required AppNotificationType type,
    required String title,
    String? body,
    String? vehicleId,
    String? linkedEntityType,
    String? linkedEntityId,
  }) async {
    await _db.into(_db.appNotifications).insert(
          AppNotificationsCompanion.insert(
            id: newId(),
            accountId: accountId,
            type: type.name,
            title: title,
            body: Value(body),
            vehicleId: Value(vehicleId),
            linkedEntityType: Value(linkedEntityType),
            linkedEntityId: Value(linkedEntityId),
            createdAt: DateTime.now(),
          ),
        );
  }

  Stream<List<AppNotification>> watchAllFor(String accountId) {
    final query = _db.select(_db.appNotifications)
      ..where((n) => n.accountId.equals(accountId))
      ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]);
    return query.watch();
  }

  Stream<int> watchUnreadCountFor(String accountId) {
    final query = _db.select(_db.appNotifications)
      ..where((n) => n.accountId.equals(accountId) & n.readAt.isNull());
    return query.watch().map((rows) => rows.length);
  }

  Future<void> markRead(String id) {
    return (_db.update(_db.appNotifications)..where((n) => n.id.equals(id)))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> markAllRead(String accountId) {
    return (_db.update(_db.appNotifications)
          ..where((n) => n.accountId.equals(accountId) & n.readAt.isNull()))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(appDatabaseProvider));
});

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  ref.watch(authStateChangesProvider);
  final userId = ref.watch(accountRepositoryProvider).currentUser?.id;
  if (userId == null) return const Stream.empty();
  return ref.watch(notificationRepositoryProvider).watchAllFor(userId);
});

final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  ref.watch(authStateChangesProvider);
  final userId = ref.watch(accountRepositoryProvider).currentUser?.id;
  if (userId == null) return Stream.value(0);
  return ref.watch(notificationRepositoryProvider).watchUnreadCountFor(userId);
});
