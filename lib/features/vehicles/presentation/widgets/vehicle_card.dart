import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../reminders/data/reminder_repository.dart';

class VehicleCard extends ConsumerWidget {
  const VehicleCard({super.key, required this.vehicle, required this.onTap});
  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.directions_car,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle.brand} ${vehicle.model}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${vehicle.currentMileage.toStringAsFixed(0)} km'
                      '${vehicle.plate != null ? ' • ${vehicle.plate}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              remindersAsync.maybeWhen(
                data: (reminders) => reminders.isEmpty
                    ? const SizedBox.shrink()
                    : Badge(
                        label: Text('${reminders.length}'),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
