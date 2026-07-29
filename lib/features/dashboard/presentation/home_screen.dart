import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/presentation/widgets/vehicle_card.dart';

/// Entry point of the app. Purely an aggregation of the Vehicles module -
/// it stores nothing of its own (RG-DASH-001).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoCarnet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: vehiclesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_car_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Aucun véhicule pour le moment',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Ajoutez votre premier véhicule pour commencer à '
                      'suivre son entretien, ses documents et ses dépenses.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => context.push('/vehicles/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un véhicule'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: vehicles.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final v = vehicles[i];
              return VehicleCard(
                vehicle: v,
                onTap: () => context.push('/vehicles/${v.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: vehiclesAsync.maybeWhen(
        data: (vehicles) => vehicles.isEmpty
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/vehicles/new'),
                child: const Icon(Icons.add),
              ),
        orElse: () => null,
      ),
    );
  }
}
