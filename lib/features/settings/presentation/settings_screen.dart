import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../providers/data/provider_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(localProfileProvider);
    final providersAsync = ref.watch(providersListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          profileAsync.maybeWhen(
            data: (profile) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(profile?.displayName ?? '—'),
              subtitle: Text(
                  'Devise : ${profile?.currency ?? '—'} • Unité : ${profile?.distanceUnit ?? '—'}'),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Verrouillage par code PIN'),
            subtitle: const Text('Protège uniquement l\'accès local'),
            value: false,
            onChanged: null,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('Prestataires', style: Theme.of(context).textTheme.titleSmall),
          ),
          providersAsync.maybeWhen(
            data: (providers) => Column(
              children: [
                for (final p in providers)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(p.name),
                    subtitle: p.city != null ? Text(p.city!) : null,
                  ),
                if (providers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('Aucun prestataire enregistré pour le moment'),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'AutoCarnet fonctionne entièrement hors connexion. Vos données '
            'restent stockées sur cet appareil.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
