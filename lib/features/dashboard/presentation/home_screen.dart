import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/presentation/widgets/vehicle_card.dart';

/// Entry point of the app. Purely an aggregation of the Vehicles module -
/// it stores nothing of its own (RG-DASH-001).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    final profileAsync = ref.watch(localProfileProvider);
    final remindersAsync = ref.watch(allActiveRemindersProvider);

    return Scaffold(
      appBar: AppBar(
        title: profileAsync.maybeWhen(
          data: (p) => Text(
            p != null ? 'Bonjour, ${p.displayName.split(' ').first}' : 'AutoCarnet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => const Text('AutoCarnet'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: vehiclesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (vehicles) {
          if (vehicles.isEmpty) {
            return EmptyState(
              icon: Icons.directions_car_outlined,
              title: 'Aucun véhicule pour le moment',
              subtitle:
                  'Ajoutez votre premier véhicule pour commencer à suivre '
                  'son entretien, ses documents et ses dépenses.',
              actionLabel: 'Ajouter un véhicule',
              onAction: () => context.push('/vehicles/new'),
            );
          }
          final reminderCount = remindersAsync.maybeWhen(
            data: (r) => r.length,
            orElse: () => 0,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
            children: [
              if (reminderCount > 0) ...[
                _RemindersBanner(count: reminderCount),
                const SizedBox(height: AppSpacing.md),
              ],
              for (var i = 0; i < vehicles.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                _StaggeredEntry(
                  index: i,
                  child: VehicleCard(
                    vehicle: vehicles[i],
                    onTap: () => context.push('/vehicles/${vehicles[i].id}'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: vehiclesAsync.maybeWhen(
        data: (vehicles) => vehicles.isEmpty
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/vehicles/new'),
                tooltip: 'Ajouter un véhicule',
                child: const Icon(Icons.add),
              ),
        orElse: () => null,
      ),
    );
  }
}

class _RemindersBanner extends StatelessWidget {
  const _RemindersBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: scheme.onTertiaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == 1
                  ? '1 échéance à surveiller'
                  : '$count échéances à surveiller',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaggeredEntry extends StatelessWidget {
  const _StaggeredEntry({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 6)) * 40;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
