import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/notifications/notification_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import 'conflict_resolution_screen.dart';

/// Persistent, per-device notification center (see AppNotifications' class
/// doc) - reachable from the bell icon in [AppShell]. Tapping a row marks
/// it read and, when it points somewhere useful, navigates there: a shared
/// vehicle's own screen for a remote edit/delete, or the conflict list for
/// a sync conflict.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(myNotificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          notificationsAsync.maybeWhen(
            data: (items) => items.any((n) => n.readAt == null)
                ? TextButton(
                    onPressed: () => ref
                        .read(notificationRepositoryProvider)
                        .markAllRead(items.first.accountId),
                    child: const Text('Tout marquer lu'),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notificationsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => const ErrorView(
            message: 'Impossible de charger vos notifications. Réessayez dans un instant.'),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Aucune notification',
              subtitle:
                  'Vous serez prévenu ici des modifications faites par vos '
                  'collaborateurs sur vos véhicules partagés.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) =>
                _NotificationTile(notification: items[i]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final AppNotification notification;

  IconData get _icon => switch (notification.type) {
    'memberJoined' => Icons.person_add_alt_1_outlined,
    'memberRemoved' => Icons.person_remove_alt_1_outlined,
    'roleChanged' => Icons.admin_panel_settings_outlined,
    'remoteDelete' => Icons.delete_outline,
    'syncConflict' => Icons.sync_problem_outlined,
    _ => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final unread = notification.readAt == null;
    return Card(
      color: unread ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: notification.type == 'syncConflict'
                ? scheme.errorContainer
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            _icon,
            color: notification.type == 'syncConflict'
                ? scheme.onErrorContainer
                : scheme.primary,
            size: 19,
          ),
        ),
        title: Text(
          notification.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: notification.body != null
            ? Text(
                notification.body!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: unread
            ? Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () async {
          await ref
              .read(notificationRepositoryProvider)
              .markRead(notification.id);
          if (!context.mounted) return;
          if (notification.type == 'syncConflict') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ConflictResolutionScreen(),
              ),
            );
          } else if (notification.vehicleId != null) {
            context.push('/vehicles/${notification.vehicleId}');
          }
        },
      ),
    );
  }
}
