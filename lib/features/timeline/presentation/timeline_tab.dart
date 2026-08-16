import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/timeline_repository.dart';

const _moduleIcons = {
  'vehicles': Icons.directions_car_outlined,
  'documents': Icons.description_outlined,
  'maintenance': Icons.build_outlined,
  'expenses': Icons.payments_outlined,
  'fuel': Icons.local_gas_station_outlined,
};

class TimelineTab extends ConsumerWidget {
  const TimelineTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(vehicleTimelineProvider(vehicleId));
    return eventsAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (events) {
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.timeline_outlined,
            title: 'La timeline est vide',
            subtitle:
                'Chaque entretien, document ou dépense ajouté apparaîtra '
                'ici automatiquement, dans l\'ordre chronologique.',
          );
        }
        final scheme = Theme.of(context).colorScheme;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
          itemCount: events.length,
          itemBuilder: (context, i) {
            final e = events[i];
            final isLast = i == events.length - 1;
            return _TimelineEntranceAnimation(
              index: i,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: scheme.primaryContainer,
                          child: Icon(
                            _moduleIcons[e.moduleOrigin] ?? Icons.circle,
                            size: 16,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: scheme.outlineVariant.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: Theme.of(context).textTheme.bodyMedium),
                            if (e.description != null &&
                                e.description!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                e.description!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              _fmt(e.occurredAt),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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

/// Gentle staggered fade + slide-in used only for the timeline, since it's
/// the screen most likely to be scanned top-to-bottom on first open.
class _TimelineEntranceAnimation extends StatelessWidget {
  const _TimelineEntranceAnimation({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 8)) * 30;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
