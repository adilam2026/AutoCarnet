import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/utils/period_filter.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/maintenance_repository.dart';
import 'maintenance_form_sheet.dart';

class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<MaintenanceTab> {
  String? _categoryFilter;
  PeriodFilter _period = PeriodFilter.all;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(vehicleMaintenanceProvider(widget.vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(widget.vehicleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Entretiens')),
      body: entriesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.build_outlined,
              title: 'Aucun entretien enregistré',
              subtitle:
                  'Commencez votre carnet avec votre dernière vidange ou '
                  'révision : chaque intervention alimente automatiquement '
                  'l\'historique et les dépenses du véhicule.',
              actionLabel: 'Ajouter un entretien',
              onAction: vehicleAsync.maybeWhen(
                data: (vehicle) => vehicle == null
                    ? null
                    : () => showMaintenanceFormSheet(
                          context,
                          vehicleId: widget.vehicleId,
                          currentMileage: vehicle.currentMileage,
                        ),
                orElse: () => null,
              ),
            );
          }
          final categories = {for (final e in entries) e.category}.toList()..sort();
          final filtered = entries
              .where((e) => _categoryFilter == null || e.category == _categoryFilter)
              .where((e) => _period.matches(e.date))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Tout'),
                            selected: _categoryFilter == null,
                            onSelected: (_) => setState(() => _categoryFilter = null),
                          ),
                          const SizedBox(width: 8),
                          for (final c in categories) ...[
                            ChoiceChip(
                              label: Text(c),
                              selected: _categoryFilter == c,
                              onSelected: (_) =>
                                  setState(() => _categoryFilter = c),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PeriodFilterChips(
                      value: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Aucun résultat pour ces filtres',
                        subtitle: 'Essayez une autre catégorie ou période.',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
                            AppSpacing.md, fabSafeBottomPadding(context)),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          final total = e.partsCost + e.laborCost;
                          return DismissibleDelete(
                            itemKey: ValueKey(e.id),
                            confirmTitle: 'Supprimer cet entretien ?',
                            confirmMessage:
                                '« ${e.category} » du ${_fmt(e.date)} sera '
                                'déplacé dans la corbeille.',
                            onConfirmedDelete: () async {
                              await ref
                                  .read(maintenanceRepositoryProvider)
                                  .softDelete(e.id);
                              if (context.mounted) {
                                showAppSnackBar(context, 'Entretien supprimé',
                                    icon: Icons.delete_outline);
                              }
                            },
                            child: Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.xs,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.6),
                                  child: Icon(
                                    Icons.build_outlined,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  e.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_fmt(e.date)} • ${e.mileage.toStringAsFixed(0)} km',
                                ),
                                trailing: total > 0
                                    ? Text(
                                        '${formatAmount(total)} ${e.currency}',
                                        style:
                                            const TextStyle(fontWeight: FontWeight.w700),
                                      )
                                    : null,
                                onTap: () => vehicleAsync.maybeWhen(
                                  data: (vehicle) {
                                    if (vehicle == null) return;
                                    showMaintenanceFormSheet(
                                      context,
                                      vehicleId: widget.vehicleId,
                                      currentMileage: vehicle.currentMileage,
                                      editing: e,
                                    );
                                  },
                                  orElse: () {},
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: vehicleAsync.maybeWhen(
        data: (vehicle) => vehicle == null
            ? null
            : FloatingActionButton(
                onPressed: () => showMaintenanceFormSheet(
                  context,
                  vehicleId: widget.vehicleId,
                  currentMileage: vehicle.currentMileage,
                ),
                child: const Icon(Icons.add),
              ),
        orElse: () => null,
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
