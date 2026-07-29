import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('Aucun entretien enregistré'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final e = entries[i];
              final total = e.partsCost + e.laborCost;
              return Card(
                child: ListTile(
                  title: Text(e.category),
                  subtitle: Text(
                    '${_fmt(e.date)} • ${e.mileage.toStringAsFixed(0)} km',
                  ),
                  trailing: Text(
                    total > 0 ? '${total.toStringAsFixed(0)} ${e.currency}' : '',
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
