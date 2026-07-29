import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/timeline_repository.dart';

const _moduleIcons = {
  'vehicles': Icons.directions_car,
  'documents': Icons.description,
  'maintenance': Icons.build,
  'expenses': Icons.payments,
  'fuel': Icons.local_gas_station,
};

class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(vehicleTimelineProvider(vehicleId));
    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur : $e')),
      data: (events) {
        if (events.isEmpty) {
          return const Center(child: Text('Aucun évènement pour le moment'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: events.length,
          itemBuilder: (context, i) {
            final e = events[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      _moduleIcons[e.moduleOrigin] ?? Icons.circle,
                      size: 16,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title,
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          _fmt(e.occurredAt),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
