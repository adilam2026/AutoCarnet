import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/widgets/loading_error_views.dart';
import '../../../documents/presentation/documents_tab.dart';
import '../../../expenses/presentation/expenses_tab.dart';
import '../../../fuel/presentation/fuel_tab.dart';
import '../../../maintenance/presentation/maintenance_tab.dart';
import '../../../timeline/presentation/timeline_tab.dart';
import '../../data/vehicle_repository.dart';
import 'vehicle_edit_screen.dart';
import 'vehicle_overview_tab.dart';

class VehicleDetailScreen extends ConsumerWidget {
  const VehicleDetailScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleByIdProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
      data: (vehicle) => DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${vehicle.brand} ${vehicle.model}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              PopupMenuButton<VehicleStatus>(
                tooltip: 'Statut du véhicule',
                icon: _StatusIndicator(status: vehicle.status),
                onSelected: (status) async {
                  await ref
                      .read(vehicleRepositoryProvider)
                      .setStatus(vehicle.id, status);
                  if (context.mounted) {
                    showAppSnackBar(
                      context,
                      'Statut mis à jour : ${_statusLabel(status)}',
                      icon: Icons.check_circle_outline,
                    );
                  }
                },
                itemBuilder: (context) => [
                  for (final status in VehicleStatus.values)
                    PopupMenuItem(
                      value: status,
                      child: Row(
                        children: [
                          if (status == vehicle.status)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.check, size: 18),
                            )
                          else
                            const SizedBox(width: 26),
                          Text(_statusLabel(status)),
                        ],
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Modifier la fiche',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VehicleEditScreen(vehicle: vehicle),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Aperçu'),
                Tab(text: 'Documents'),
                Tab(text: 'Entretiens'),
                Tab(text: 'Dépenses'),
                Tab(text: 'Carburant'),
                Tab(text: 'Timeline'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              VehicleOverviewTab(vehicle: vehicle),
              DocumentsTab(vehicleId: vehicle.id),
              MaintenanceTab(vehicleId: vehicle.id),
              ExpensesTab(vehicleId: vehicle.id),
              FuelTab(vehicleId: vehicle.id),
              TimelineTab(vehicleId: vehicle.id),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});
  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      VehicleStatus.active => scheme.primary,
      VehicleStatus.archived => scheme.outline,
      VehicleStatus.sold => scheme.tertiary,
      VehicleStatus.destroyed => scheme.error,
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}
