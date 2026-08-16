import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../documents/data/document_repository.dart';
import '../../expenses/data/expense_repository.dart';
import '../../fuel/data/fuel_repository.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/presentation/providers/vehicle_form_providers.dart';

/// Read-only resale-readiness snapshot per vehicle, built entirely from data
/// already collected elsewhere (Principe 2: one entry, several benefits).
/// A full exportable PDF dossier (bloc 18) is a later phase - this view
/// just tells the owner how ready a vehicle looks today.
class ResaleBody extends ConsumerStatefulWidget {
  const ResaleBody({super.key});

  @override
  ConsumerState<ResaleBody> createState() => _ResaleBodyState();
}

class _ResaleBodyState extends ConsumerState<ResaleBody> {
  String? _selectedVehicleId;

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return vehiclesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (vehicles) {
        if (vehicles.isEmpty) {
          return const EmptyState(
            icon: Icons.sell_outlined,
            title: 'Aucun véhicule à préparer',
            subtitle: 'Ajoutez un véhicule pour préparer sa fiche de revente.',
          );
        }
        final selected = vehicles.firstWhere(
          (v) => v.id == _selectedVehicleId,
          orElse: () => vehicles.first,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
          children: [
            if (vehicles.length > 1) ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: vehicles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final v = vehicles[i];
                    final isSelected = v.id == selected.id;
                    return ChoiceChip(
                      label: Text('${v.brand} ${v.model}'),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedVehicleId = v.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _ResaleSummary(vehicle: selected),
          ],
        );
      },
    );
  }
}

class _ResaleSummary extends ConsumerWidget {
  const _ResaleSummary({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final expenseStats = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStats = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenance = ref.watch(vehicleMaintenanceProvider(vehicle.id));
    final documents = ref.watch(vehicleDocumentsProvider(vehicle.id));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.directions_car, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${vehicle.brand} ${vehicle.model}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '${vehicle.currentMileage.toStringAsFixed(0)} km'
                        '${vehicle.year != null ? ' • ${vehicle.year}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Fiche complétée à ${(completeness * 100).round()} % — plus elle '
          'est complète, plus le dossier inspire confiance à un acheteur.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        StatTileRow(
          tiles: [
            StatTile(
              label: 'Documents',
              icon: Icons.description_outlined,
              value: documents.maybeWhen(data: (d) => '${d.length}', orElse: () => '—'),
            ),
            StatTile(
              label: 'Entretiens',
              icon: Icons.build_outlined,
              value: maintenance.maybeWhen(data: (m) => '${m.length}', orElse: () => '—'),
            ),
            StatTile(
              label: 'Coût total',
              icon: Icons.payments_outlined,
              value: expenseStats.maybeWhen(
                data: (s) => s.totalAll.toStringAsFixed(0),
                orElse: () => '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        StatTileRow(
          tiles: [
            StatTile(
              label: 'Conso. moyenne',
              icon: Icons.speed_outlined,
              value: fuelStats.maybeWhen(
                data: (s) => s.averageConsumption != null
                    ? '${s.averageConsumption!.toStringAsFixed(1)} L/100'
                    : '—',
                orElse: () => '—',
              ),
            ),
            StatTile(
              label: 'Statut',
              icon: Icons.info_outline,
              value: _statusLabel(vehicle.status),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Card(
          color: scheme.surfaceContainerHigh,
          child: const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Le dossier de revente exportable en PDF arrivera dans une '
              'prochaine version. En attendant, cette synthèse vous aide à '
              'évaluer si le véhicule est prêt à être présenté.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };
}
