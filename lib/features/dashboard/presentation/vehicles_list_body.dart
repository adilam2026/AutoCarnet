import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/presentation/widgets/vehicle_card.dart';

/// "Mes véhicules" - the app's home base. AutoCarnet is multi-vehicle by
/// design: this list is always the entry point, never a single-vehicle
/// dashboard (bloc 3, §6.2).
class VehiclesListBody extends ConsumerWidget {
  const VehiclesListBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return vehiclesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (vehicles) {
        if (vehicles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_outlined,
                      size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Aucun véhicule pour le moment',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Ajoutez votre véhicule pour commencer à suivre son '
                    'entretien, ses documents et ses dépenses - ou rejoignez '
                    'un véhicule déjà suivi par un proche.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => context.push('/vehicles/new'),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter mon véhicule'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/vehicles/join'),
                      icon: const Icon(Icons.qr_code_2_outlined),
                      label: const Text('Rejoindre un véhicule'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
          children: [
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
    );
  }
}

/// Small badge shown on the "Alertes" bottom-nav destination.
final globalReminderCountProvider = Provider<int>((ref) {
  final async = ref.watch(allActiveRemindersProvider);
  return async.maybeWhen(data: (r) => r.length, orElse: () => 0);
});

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
