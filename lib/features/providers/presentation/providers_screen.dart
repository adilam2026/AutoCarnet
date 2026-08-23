import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/icon_chip.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/provider_repository.dart';
import '../domain/service_provider_category.dart';
import 'provider_form_screen.dart';

/// A real management screen (mission point 2/7): consult, add, edit and
/// delete a prestataire - not just an implicit, read-only by-product of
/// typing a name into another module's form.
class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  ProviderFilter _filter = ProviderFilter.all;

  void _openForm({ServiceProvider? editing}) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProviderFormScreen(editing: editing)));
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(providersListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prestataires'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un prestataire',
            onPressed: () => _openForm(),
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => const ErrorView(
            message: 'Impossible de charger vos prestataires. Réessayez dans un instant.'),
        data: (providers) {
          if (providers.isEmpty) {
            return EmptyState(
              icon: Icons.storefront_outlined,
              title: 'Aucun prestataire enregistré',
              subtitle:
                  'Ajoutez vos garages, concessionnaires, assureurs et stations, ou '
                  'ils seront enregistrés automatiquement dès que vous les saisissez '
                  'dans une opération.',
              actionLabel: '+ Ajouter un prestataire',
              onAction: () => _openForm(),
            );
          }

          final filtered =
              providers.where((p) => _filter.matches(p.category)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in ProviderFilter.values) ...[
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun prestataire dans cette catégorie',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        children: [
                          ListSurface(
                            children: [
                              for (final p in filtered)
                                ListTile(
                                  leading: const IconChip(Icons.storefront_outlined),
                                  title: Text(p.name),
                                  subtitle: Text([
                                    if (p.category != null) p.category!.label,
                                    if (p.city != null) p.city!,
                                  ].join(' · ')),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openForm(editing: p),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
