import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/sheet_handle.dart';
import '../../../documents/presentation/document_form_sheet.dart';
import '../../../expenses/presentation/expense_form_sheet.dart';
import '../../../fuel/presentation/adblue_form_sheet.dart';
import '../../../fuel/presentation/fuel_form_sheet.dart';
import '../../../maintenance/presentation/maintenance_form_sheet.dart';
import 'mileage_update_sheet.dart';

/// Single entry point for "I need to log something on this vehicle" (bloc
/// 24 principle: one obvious path, not several menus to dig through). Picks
/// the operation type, then opens that module's real add form directly -
/// no intermediate screen.
Future<void> showAddOperationSheet(
  BuildContext context,
  WidgetRef ref, {
  required Vehicle vehicle,
}) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    // Scrollable on purpose (mission 2026: adding "Plein AdBlue" as a 6th
    // tile overflowed the previous fixed-fraction sheet on shorter
    // screens) - matches every other bottom sheet in the app
    // (isScrollControlled + a scrollable child) rather than a plain
    // Column capped at a fraction of the screen height.
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(sheetContext).padding.bottom + AppSpacing.md,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const SheetHandle(),
            Text(
              'Que voulez-vous ajouter ?',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _OperationTile(
              icon: Icons.build_outlined,
              label: 'Entretien / réparation',
              subtitle: 'Vidange, révision, freins, pneus, carrosserie...',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showMaintenanceFormSheet(
                  context,
                  vehicleId: vehicle.id,
                  currentMileage: vehicle.currentMileage,
                );
              },
            ),
            _OperationTile(
              icon: Icons.local_gas_station_outlined,
              label: 'Plein de carburant',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showFuelFormSheet(
                  context,
                  vehicleId: vehicle.id,
                  currentMileage: vehicle.currentMileage,
                  vehicleFuelType: vehicle.fuelType,
                );
              },
            ),
            // Diesel-only (mission 2026, point 15: "ne pas proposer AdBlue
            // à une voiture essence") - a vehicle with no declared fuel
            // type stays neutral rather than guessing.
            if (vehicle.fuelType == 'Diesel')
              _OperationTile(
                icon: Icons.water_drop_outlined,
                label: 'Plein AdBlue',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showAdblueFormSheet(
                    context,
                    vehicleId: vehicle.id,
                    currentMileage: vehicle.currentMileage,
                  );
                },
              ),
            _OperationTile(
              icon: Icons.payments_outlined,
              label: 'Dépense',
              subtitle: 'Péage, parking, amende, divers...',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showExpenseFormSheet(context, vehicleId: vehicle.id);
              },
            ),
            _OperationTile(
              icon: Icons.description_outlined,
              label: 'Document',
              subtitle: 'Assurance, vignette, visite technique, carte grise...',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showDocumentFormSheet(context, vehicleId: vehicle.id);
              },
            ),
            _OperationTile(
              icon: Icons.speed_outlined,
              label: 'Mettre à jour le kilométrage',
              onTap: () {
                Navigator.of(sheetContext).pop();
                showMileageUpdateSheet(context, ref, vehicle);
              },
            ),
          ],
        ),
      );
    },
  );
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        title: Text(label),
        subtitle: subtitle != null
            ? Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
