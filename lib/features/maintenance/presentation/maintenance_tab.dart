import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/maintenance_repository.dart';
import 'maintenance_form_sheet.dart';

class MaintenanceTab extends ConsumerWidget {
  const MaintenanceTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(vehicleMaintenanceProvider(vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(vehicleId));
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
                  'Vidange, freins, révision... chaque intervention '
                  'enregistrée alimente automatiquement l\'historique et '
                  'les dépenses du véhicule.',
              actionLabel: 'Ajouter un entretien',
              onAction: vehicleAsync.maybeWhen(
                data: (vehicle) => () => showMaintenanceFormSheet(
                      context,
                      vehicleId: vehicleId,
                      currentMileage: vehicle.currentMileage,
                    ),
                orElse: () => null,
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final e = entries[i];
              final total = e.partsCost + e.laborCost;
              return DismissibleDelete(
                itemKey: ValueKey(e.id),
                confirmTitle: 'Supprimer cet entretien ?',
                confirmMessage:
                    '« ${e.category} » du ${_fmt(e.date)} sera déplacé '
                    'dans la corbeille.',
                onConfirmedDelete: () async {
                  await ref.read(maintenanceRepositoryProvider).softDelete(e.id);
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
                            '${total.toStringAsFixed(0)} ${e.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: vehicleAsync.maybeWhen(
        data: (vehicle) => FloatingActionButton(
          onPressed: () => showMaintenanceFormSheet(
            context,
            vehicleId: vehicleId,
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
