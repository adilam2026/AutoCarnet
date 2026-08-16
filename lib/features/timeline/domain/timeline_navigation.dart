import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/presentation/document_form_sheet.dart';
import '../../expenses/data/expense_repository.dart';
import '../../expenses/presentation/expense_form_sheet.dart';
import '../../fuel/data/fuel_repository.dart';
import '../../fuel/presentation/fuel_form_sheet.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../vehicles/presentation/screens/vehicle_edit_screen.dart';

/// Opens the record a timeline/historique event points to, so "consult and
/// modify what you already entered" works the same wherever an event is
/// shown (the vehicle dashboard's "Dernières opérations" and the full
/// historique screen both delegate here instead of duplicating the switch).
Future<void> openTimelineEventSource(
  BuildContext context,
  WidgetRef ref,
  TimelineEvent event,
  Vehicle vehicle,
) async {
  final id = event.linkedEntityId;
  if (id == null) return;
  switch (event.moduleOrigin) {
    case 'maintenance':
      final entry = await ref.read(maintenanceRepositoryProvider).getById(id);
      if (entry != null && context.mounted) {
        showMaintenanceFormSheet(
          context,
          vehicleId: vehicle.id,
          currentMileage: vehicle.currentMileage,
          editing: entry,
        );
      }
    case 'fuel':
      final entry = await ref.read(fuelRepositoryProvider).getById(id);
      if (entry != null && context.mounted) {
        showFuelFormSheet(
          context,
          vehicleId: vehicle.id,
          currentMileage: vehicle.currentMileage,
          editing: entry,
        );
      }
    case 'expenses':
      final entry = await ref.read(expenseRepositoryProvider).getById(id);
      if (entry != null && context.mounted) {
        showExpenseFormSheet(context, vehicleId: vehicle.id, editing: entry);
      }
    case 'documents':
      final doc = await ref.read(documentRepositoryProvider).getById(id);
      if (doc != null && context.mounted) {
        showDocumentFormSheet(
          context,
          vehicleId: vehicle.id,
          renewing: doc.document,
          renewingVersion: doc.version,
        );
      }
    case 'vehicles':
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VehicleEditScreen(vehicle: vehicle)),
        );
      }
  }
}
