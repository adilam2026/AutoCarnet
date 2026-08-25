import 'package:flutter/material.dart';
import '../../../core/widgets/date_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/utils/period_filter.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/timeline_repository.dart';
import '../domain/timeline_navigation.dart';

const _moduleIcons = {
  'vehicles': Icons.directions_car_outlined,
  'documents': Icons.description_outlined,
  'maintenance': Icons.build_outlined,
  'expenses': Icons.payments_outlined,
  'fuel': Icons.local_gas_station_outlined,
};

const _moduleLabels = {
  'vehicles': 'Véhicule',
  'documents': 'Documents',
  'maintenance': 'Entretien',
  'expenses': 'Dépenses',
  'fuel': 'Carburant',
};

class TimelineTab extends ConsumerStatefulWidget {
  const TimelineTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<TimelineTab> createState() => _TimelineTabState();
}

class _TimelineTabState extends ConsumerState<TimelineTab> {
  String? _moduleFilter;
  PeriodFilter _period = PeriodFilter.all;

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(vehicleTimelineProvider(widget.vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(widget.vehicleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: eventsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
        data: (events) {
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.timeline_outlined,
              title: 'L\'historique est vide',
              subtitle:
                  'Chaque entretien, document, dépense ou plein ajouté '
                  'apparaîtra ici automatiquement, dans l\'ordre '
                  'chronologique.',
            );
          }
          final modules = {for (final e in events) e.moduleOrigin}.toList()
            ..sort();
          final filtered = events
              .where((e) => _moduleFilter == null || e.moduleOrigin == _moduleFilter)
              .where((e) => _period.matches(e.occurredAt))
              .toList();
          final scheme = Theme.of(context).colorScheme;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Tout'),
                            selected: _moduleFilter == null,
                            onSelected: (_) => setState(() => _moduleFilter = null),
                          ),
                          const SizedBox(width: 8),
                          for (final m in modules) ...[
                            ChoiceChip(
                              label: Text(_moduleLabels[m] ?? m),
                              selected: _moduleFilter == m,
                              onSelected: (_) => setState(() => _moduleFilter = m),
                            ),
                            const SizedBox(width: 8),
                          ],
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
                        subtitle: 'Essayez un autre module ou période.',
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
                            AppSpacing.md, fabSafeBottomPadding(context)),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          final isLast = i == filtered.length - 1;
                          return _TimelineEntranceAnimation(
                            index: i,
                            child: InkWell(
                              onTap: () => vehicleAsync.maybeWhen(
                                data: (vehicle) {
                                  if (vehicle == null) return;
                                  openTimelineEventSource(context, ref, e, vehicle);
                                },
                                orElse: () {},
                              ),
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
                                            _moduleIcons[e.moduleOrigin] ??
                                                Icons.circle,
                                            size: 16,
                                            color: scheme.onPrimaryContainer,
                                          ),
                                        ),
                                        if (!isLast)
                                          Expanded(
                                            child: Container(
                                              width: 2,
                                              margin: const EdgeInsets.symmetric(
                                                  vertical: 4),
                                              color: scheme.outlineVariant
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: AppSpacing.lg),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(e.title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium),
                                            if (e.description != null &&
                                                e.description!.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                e.description!,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                            const SizedBox(height: 2),
                                            Text(
                                              _fmt(e.occurredAt),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right,
                                        color: scheme.outline, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${formatDdMmYyyy(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
