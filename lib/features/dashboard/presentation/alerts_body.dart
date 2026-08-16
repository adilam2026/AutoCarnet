import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';

/// Cross-vehicle view of every active reminder (bloc 12, §15.11) - the
/// dashboard used to bury this inside each vehicle; now it's a first-class
/// destination so nothing gets missed across a multi-vehicle garage.
class AlertsBody extends ConsumerWidget {
  const AlertsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(allActiveRemindersProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return remindersAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (reminders) {
        if (reminders.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_outlined,
            title: 'Aucune échéance à venir',
            subtitle:
                'Les documents à renouveler et les entretiens prévus '
                'apparaîtront ici, tous véhicules confondus.',
          );
        }
        final vehicles = vehiclesAsync.maybeWhen(
          data: (v) => {for (final vehicle in v) vehicle.id: vehicle},
          orElse: () => <String, Vehicle>{},
        );
        final sorted = [...reminders]..sort((a, b) {
            final da = a.dueDate ?? DateTime(2100);
            final db = b.dueDate ?? DateTime(2100);
            return da.compareTo(db);
          });
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) {
            final r = sorted[i];
            final vehicle = vehicles[r.vehicleId];
            final overdue = r.dueDate != null && r.dueDate!.isBefore(DateTime.now());
            final scheme = Theme.of(context).colorScheme;
            return Card(
              child: ListTile(
                onTap: vehicle != null
                    ? () => context.push('/vehicles/${vehicle.id}')
                    : null,
                leading: CircleAvatar(
                  backgroundColor: overdue
                      ? scheme.errorContainer
                      : scheme.tertiaryContainer,
                  child: Icon(
                    overdue ? Icons.warning_amber_outlined : Icons.notifications_outlined,
                    color: overdue ? scheme.onErrorContainer : scheme.onTertiaryContainer,
                    size: 20,
                  ),
                ),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (vehicle != null) '${vehicle.brand} ${vehicle.model}',
                    _dueLabel(r),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        );
      },
    );
  }

  String _dueLabel(Reminder r) {
    if (r.dueDate != null) {
      final d = r.dueDate!;
      final overdue = d.isBefore(DateTime.now());
      return overdue
          ? 'En retard depuis le ${d.day}/${d.month}/${d.year}'
          : '${d.day}/${d.month}/${d.year}';
    }
    if (r.dueMileage != null) return '${r.dueMileage!.toStringAsFixed(0)} km';
    return '';
  }
}
