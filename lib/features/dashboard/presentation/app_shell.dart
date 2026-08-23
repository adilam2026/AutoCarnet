import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_repository.dart';
import '../../../core/sync/conflict_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/account_repository.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../onboarding_lock/presentation/app_gate.dart';
import '../../resale/presentation/resale_body.dart';
import '../../sync/presentation/conflict_resolution_screen.dart';
import '../../sync/presentation/notifications_screen.dart';
import 'alerts_body.dart';
import 'vehicles_list_body.dart';

/// Root navigation shell: a hamburger drawer for the full menu, and a
/// bottom bar limited to the handful of destinations used every day
/// (Véhicules / Alertes / Revendre / Plus) - never more than 4, so the
/// user is never scanning a crowded bar or scrolling a long tab strip.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _titles = ['AutoCarnet', 'Alertes', 'Revendre', 'Plus'];

  void _goToTab(int index) => setState(() => _index = index);

  /// Two clearly distinct actions, never two identical giant buttons
  /// (bloc 20): creating a vehicle makes you its owner; joining one never
  /// creates anything, it only ever attaches your account to an existing
  /// vehicle via a code.
  Future<void> _showAddOrJoinSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('Ajouter mon véhicule'),
              subtitle: const Text('Vous en devenez le propriétaire'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/vehicles/new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_outlined),
              title: const Text('Rejoindre un véhicule'),
              subtitle: const Text('Avec un code reçu d\'un proche'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/vehicles/join');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reminderCount = ref.watch(globalReminderCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: const [_NotificationBellButton(), _AccountAvatarButton()],
      ),
      drawer: _AppDrawer(onSelectTab: _goToTab),
      body: IndexedStack(
        index: _index,
        children: const [
          VehiclesListBody(),
          AlertsBody(),
          ResaleBody(),
          _MoreMenuBody(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              tooltip: 'Ajouter ou rejoindre un véhicule',
              onPressed: () => _showAddOrJoinSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'Véhicules',
          ),
          NavigationDestination(
            icon: reminderCount > 0
                ? Badge(
                    label: Text('$reminderCount'),
                    child: const Icon(Icons.notifications_outlined),
                  )
                : const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Alertes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell),
            label: 'Revendre',
          ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'Plus',
          ),
        ],
      ),
    );
  }
}

/// Entry point to the persistent notification center (see
/// AppNotifications' class doc) - a red badge with the unread count is the
/// only thing that ever draws attention to it, exactly like a phone's own
/// notification tray.
class _NotificationBellButton extends ConsumerWidget {
  const _NotificationBellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider).value ?? 0;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text('$unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Direct, always-visible entry point to the account (bloc "connexion
/// visible") - the hamburger drawer still has "Compte & sécurité" for
/// general navigation, but the account itself must never be several taps
/// deep. Shows the user's initials (from the local profile's display name,
/// falling back to the account email) so the current identity is
/// recognizable at a glance, not just a generic icon.
class _AccountAvatarButton extends ConsumerWidget {
  const _AccountAvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched purely so this rebuilds when the session changes - the
    // initials themselves come from a plain read below.
    ref.watch(authStateChangesProvider);
    final profileAsync = ref.watch(localProfileProvider);
    final account = ref.read(accountRepositoryProvider);
    final displayName = profileAsync.maybeWhen(
      data: (p) => p?.displayName,
      orElse: () => null,
    );
    final initials = _initialsFromName(displayName ?? account.currentUser?.email);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: IconButton(
        tooltip: 'Mon compte',
        onPressed: () => context.push('/settings'),
        icon: CircleAvatar(
          radius: 16,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            initials,
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared between the avatar button and the drawer header - the same
/// person must show the same initials everywhere in the shell.
String _initialsFromName(String? source) {
  final trimmed = source?.trim() ?? '';
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return trimmed[0].toUpperCase();
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.onSelectTab});
  final ValueChanged<int> onSelectTab;

  /// "Verrouiller AutoCarnet": deliberately NOT a dissociation - only hides
  /// the app behind the PIN/biometric screen. The account stays associated
  /// with this device, and a correct PIN returns straight to the home page
  /// (see AppGate._goUnlocked). Kept very easy to reach - bottom of the
  /// main drawer, one tap plus a light confirmation - since this is the
  /// frequent action; the rare/sensitive ones (dissociate, disconnect
  /// everywhere) live behind "Gestion du compte" in Compte & sécurité.
  Future<void> _onLockApp(BuildContext context, WidgetRef ref) async {
    // Read the notifier before the drawer finishes closing (it's popped
    // right before this is called) - by the time the dialog's await below
    // resolves, `_AppDrawer`'s own element is disposed, and `ref` itself
    // can no longer be used past that point.
    final lockRequest = ref.read(sessionLockRequestProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verrouiller AutoCarnet ?'),
        content: const Text(
          'Le code d\'accès (ou la biométrie) sera nécessaire pour rouvrir. '
          'Le compte reste connecté sur cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Verrouiller'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    lockRequest.state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(localProfileProvider);
    ref.watch(authStateChangesProvider);
    final email = ref.read(accountRepositoryProvider).currentUser?.email;
    final displayName = profileAsync.maybeWhen(data: (p) => p?.displayName, orElse: () => null);
    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xl, AppSpacing.md, AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.secondary],
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    child: Text(
                      _initialsFromName(displayName ?? email),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName?.isNotEmpty == true ? displayName! : 'AutoCarnet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        if (email != null && email.isNotEmpty)
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: const Text('Mes véhicules'),
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Alertes'),
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Revendre'),
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(2);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Prestataires'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/providers');
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Compte & sécurité'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Journal d\'audit'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/audit-log');
              },
            ),
            Builder(
              builder: (context) {
                final conflictCount =
                    ref.watch(unresolvedConflictsProvider).value?.length ?? 0;
                if (conflictCount == 0) return const SizedBox.shrink();
                return ListTile(
                  leading: Icon(
                    Icons.sync_problem_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Conflits de synchronisation'),
                  trailing: Badge(label: Text('$conflictCount')),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConflictResolutionScreen(),
                      ),
                    );
                  },
                );
              },
            ),
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Material(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  leading: Icon(Icons.lock_outline, color: scheme.error),
                  title: Text('Verrouiller AutoCarnet',
                      style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.exit_to_app, size: 18, color: scheme.error),
                  onTap: () {
                    Navigator.of(context).pop();
                    _onLockApp(context, ref);
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _MoreMenuBody extends StatelessWidget {
  const _MoreMenuBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Prestataires'),
            subtitle: const Text(
              'Garages, stations, organismes réutilisés partout',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/providers'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Compte & sécurité'),
            subtitle: const Text('Profil, devise, code PIN, biométrie'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Journal d\'audit'),
            subtitle: const Text(
              'Trace technique des modifications, séparée du carnet',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/audit-log'),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Center(
          child: Text(
            'AutoCarnet fonctionne entièrement hors connexion.\n'
            'Vos données restent stockées sur cet appareil.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
