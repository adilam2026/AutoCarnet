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
import '../../../core/widgets/stat_tile.dart';
import '../../account/data/account_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle_ownership.dart';
import '../data/fuel_repository.dart';
import 'fuel_form_sheet.dart';

class FuelTab extends ConsumerStatefulWidget {
  const FuelTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<FuelTab> createState() => _FuelTabState();
}

class _FuelTabState extends ConsumerState<FuelTab> {
  PeriodFilter _period = PeriodFilter.all;
  bool _onlyFullTank = false;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(
      vehicleFuelEntriesProvider(widget.vehicleId),
    );
    final statsAsync = ref.watch(vehicleFuelStatsProvider(widget.vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(widget.vehicleId));
    final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
    final canEdit = vehicleAsync.maybeWhen(
      data: (v) => v != null && canEditVehicle(v, currentUserId),
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Carburant')),
      body: entriesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              icon: Icons.local_gas_station_outlined,
              title: 'Aucun plein enregistré',
              subtitle: canEdit
                  ? 'Ajoutez vos pleins pour suivre la consommation réelle et '
                        'le budget carburant de ce véhicule.'
                  : 'Vous avez un accès en lecture seule à ce véhicule.',
              actionLabel: canEdit ? 'Ajouter un plein' : null,
              onAction: !canEdit
                  ? null
                  : vehicleAsync.maybeWhen(
                      data: (vehicle) => vehicle == null
                          ? null
                          : () => showFuelFormSheet(
                              context,
                              vehicleId: widget.vehicleId,
                              currentMileage: vehicle.currentMileage,
                              vehicleFuelType: vehicle.fuelType,
                            ),
                      orElse: () => null,
                    ),
            );
          }
          final filtered = entries
              .where((f) => _period.matches(f.date))
              .where((f) => !_onlyFullTank || f.isFullTank)
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statsAsync.maybeWhen(
                      data: (stats) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: StatTileRow(
                          tiles: [
                            StatTile(
                              label: 'Conso. moyenne',
                              value: stats.averageConsumption != null
                                  ? '${stats.averageConsumption!.toStringAsFixed(1)} L/100'
                                  : '—',
                              icon: Icons.speed_outlined,
                              highlight: true,
                            ),
                            StatTile(
                              label: 'Total litres',
                              value:
                                  '${stats.totalLiters.toStringAsFixed(0)} L',
                              icon: Icons.local_gas_station_outlined,
                            ),
                            StatTile(
                              label: 'Total dépensé',
                              value: formatAmount(stats.totalCost),
                              icon: Icons.payments_outlined,
                            ),
                          ],
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Pleins complets uniquement'),
                            selected: _onlyFullTank,
                            onSelected: (v) =>
                                setState(() => _onlyFullTank = v),
                          ),
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
                        subtitle: 'Essayez une autre période.',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          fabSafeBottomPadding(context),
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final f = filtered[i];
                          final card = Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.local_gas_station_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 19,
                                ),
                              ),
                              title: Text(
                                '${f.quantityLiters.toStringAsFixed(1)} L — ${f.fuelType}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_fmt(f.date)} • ${f.mileage.toStringAsFixed(0)} km'
                                '${f.isFullTank ? '' : ' • partiel'}',
                              ),
                              trailing: Text(
                                formatAmount(f.totalAmount),
                                style: AppTypography.mono(
                                  context,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: !canEdit
                                  ? null
                                  : () => vehicleAsync.maybeWhen(
                                      data: (vehicle) {
                                        if (vehicle == null) return;
                                        showFuelFormSheet(
                                          context,
                                          vehicleId: widget.vehicleId,
                                          currentMileage:
                                              vehicle.currentMileage,
                                          editing: f,
                                        );
                                      },
                                      orElse: () {},
                                    ),
                            ),
                          );
                          if (!canEdit) return card;
                          return DismissibleDelete(
                            itemKey: ValueKey(f.id),
                            confirmTitle: 'Supprimer ce plein ?',
                            confirmMessage:
                                'Le plein du ${_fmt(f.date)} sera déplacé dans '
                                'la corbeille.',
                            onConfirmedDelete: () async {
                              await ref
                                  .read(fuelRepositoryProvider)
                                  .softDelete(f.id);
                              if (context.mounted) {
                                showAppSnackBar(
                                  context,
                                  'Plein supprimé',
                                  icon: Icons.delete_outline,
                                );
                              }
                            },
                            child: card,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: !canEdit
          ? null
          : vehicleAsync.maybeWhen(
              data: (vehicle) => vehicle == null
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: () => showFuelFormSheet(
                        context,
                        vehicleId: widget.vehicleId,
                        currentMileage: vehicle.currentMileage,
                        vehicleFuelType: vehicle.fuelType,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un plein'),
                    ),
              orElse: () => null,
            ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
