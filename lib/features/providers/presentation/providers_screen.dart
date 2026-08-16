import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/provider_repository.dart';

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(providersListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Prestataires')),
      body: providersAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (providers) {
          if (providers.isEmpty) {
            return const EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Aucun prestataire enregistré',
              subtitle:
                  'Les garages, stations et organismes que vous saisissez '
                  'dans les entretiens, pleins ou documents apparaîtront '
                  'automatiquement ici.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final p = providers[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(p.name),
                  subtitle: p.city != null ? Text(p.city!) : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
