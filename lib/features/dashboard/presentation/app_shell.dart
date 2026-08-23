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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _titles = ['AutoCarnet', 'Alertes', 'Revendre'];

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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_titles[_index],
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
        actions: const [_NotificationBellButton(), _AccountAvatarButton()],
      ),
      drawer: _AppDrawer(onSelectTab: _goToTab),
      body: IndexedStack(
        index: _index,
        children: const [
          VehiclesListBody(),
          AlertsBody(),
          ResaleBody(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              tooltip: 'Ajouter ou rejoindre un véhicule',
              onPressed: () => _showAddOrJoinSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        // The 4th destination never becomes the selected tab (matching the
        // validated mockup's nav: Véhicules / Alertes / Revendre / Menu) -
        // it opens the same drawer the hamburger icon does, instead of a
        // separate "Plus" screen that duplicated the drawer's own items.
        onDestinationSelected: (i) {
          if (i == 3) {
            _scaffoldKey.currentState?.openDrawer();
            return;
          }
          setState(() => _index = i);
        },
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
            icon: Icon(Icons.menu_outlined),
            selectedIcon: Icon(Icons.menu),
            label: 'Menu',
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
            // V2.1 pass: a compact, flat header (no decorative gradient
            // block eating drawer height) - matches the mockup's plain
            // avatar/name/email row with a hairline border underneath.
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      _initialsFromName(displayName ?? email),
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 13),
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
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        if (email != null && email.isNotEmpty)
                          Text(email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DrawerItem(
              icon: Icons.directions_car_outlined,
              label: 'Mes véhicules',
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(0);
              },
            ),
            _DrawerItem(
              icon: Icons.notifications_outlined,
              label: 'Alertes',
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(1);
              },
            ),
            _DrawerItem(
              icon: Icons.sell_outlined,
              label: 'Revendre',
              onTap: () {
                Navigator.of(context).pop();
                onSelectTab(2);
              },
            ),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
            _DrawerItem(
              icon: Icons.storefront_outlined,
              label: 'Prestataires',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/providers');
              },
            ),
            _DrawerItem(
              icon: Icons.manage_accounts_outlined,
              label: 'Compte & sécurité',
              onTap: () {
                Navigator.of(context).pop();
                context.push('/settings');
              },
            ),
            _DrawerItem(
              icon: Icons.fact_check_outlined,
              label: 'Journal d\'audit',
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
                final errorColor = Theme.of(context).colorScheme.error;
                return _DrawerItem(
                  icon: Icons.sync_problem_outlined,
                  label: 'Conflits de synchronisation',
                  color: errorColor,
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
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
            _DrawerItem(
              icon: Icons.lock_outline,
              label: 'Verrouiller AutoCarnet',
              color: scheme.error,
              fontWeight: FontWeight.w600,
              onTap: () {
                Navigator.of(context).pop();
                _onLockApp(context, ref);
              },
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// Compact drawer navigation row matching the V2.1 mockup's `.drawer__item`
/// spec (10px/8px padding, 19px icon, 14px/500 label) - deliberately not a
/// stock [ListTile], whose default intrinsic height is noticeably taller.
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.fontWeight = FontWeight.w500,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final FontWeight fontWeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: fontWeight, color: fg),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

