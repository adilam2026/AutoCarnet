import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/data/account_repository.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../resale/presentation/resale_body.dart';
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

  @override
  Widget build(BuildContext context) {
    final reminderCount = ref.watch(globalReminderCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: const [_AccountAvatarButton()],
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
          ? FloatingActionButton(
              tooltip: 'Ajouter un véhicule',
              onPressed: () => context.push('/vehicles/new'),
              child: const Icon(Icons.add),
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
    final initials = _initialsFrom(displayName ?? account.currentUser?.email);
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

  String _initialsFrom(String? source) {
    final trimmed = source?.trim() ?? '';
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }
}

class _AppDrawer extends ConsumerWidget {
  const _AppDrawer({required this.onSelectTab});
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(localProfileProvider);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_car_filled,
                        color: Theme.of(context).colorScheme.onPrimary, size: 32),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      profileAsync.maybeWhen(
                        data: (p) => p?.displayName ?? 'AutoCarnet',
                        orElse: () => 'AutoCarnet',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
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
            subtitle: const Text('Garages, stations, organismes réutilisés partout'),
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
            subtitle: const Text('Trace technique des modifications, séparée du carnet'),
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
