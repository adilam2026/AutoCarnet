import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/tables.dart';
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
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur : $e'))),
      data: (vehicle) => DefaultTabController(
        length: 6,
        child: Scaffold(
          appBar: AppBar(
            title: Text('${vehicle.brand} ${vehicle.model}'),
            actions: [
              PopupMenuButton<VehicleStatus>(
                onSelected: (status) => ref
                    .read(vehicleRepositoryProvider)
                    .setStatus(vehicle.id, status),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: VehicleStatus.active, child: Text('Actif')),
                  PopupMenuItem(
                      value: VehicleStatus.archived, child: Text('Archivé')),
                  PopupMenuItem(
                      value: VehicleStatus.sold, child: Text('Vendu')),
                  PopupMenuItem(
                      value: VehicleStatus.destroyed, child: Text('Détruit')),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VehicleEditScreen(vehicle: vehicle),
                  ),
                ),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
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
}
