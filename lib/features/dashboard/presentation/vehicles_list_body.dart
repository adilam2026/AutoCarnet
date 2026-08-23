import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../expenses/data/expense_repository.dart';
import '../../fuel/presentation/fuel_form_sheet.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/domain/revision_estimation.dart';
import '../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../reminders/domain/reminder_urgency.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle_health.dart';
import '../../vehicles/presentation/widgets/mileage_update_sheet.dart';
import 'widgets/vehicle_hero_card.dart';

/// AutoCarnet's home base ("Premium clair" concept, 2026) - a real personal
/// dashboard, not a bare vehicle list: a greeting, the vehicle(s) as the
/// central element, what needs attention, one-tap logging, and a compact
/// read on the carnet as a whole. Every number shown here already exists
/// somewhere in the app (health score, reminders, expenses, mileage
/// history) - nothing is invented for this screen.
class VehiclesListBody extends ConsumerStatefulWidget {
  const VehiclesListBody({super.key});

  @override
  ConsumerState<VehiclesListBody> createState() => _VehiclesListBodyState();
}

class _VehiclesListBodyState extends ConsumerState<VehiclesListBody> {
  int _selectedIndex = 0;
  late final PageController _pageController = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return vehiclesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (vehicles) {
        if (vehicles.isEmpty) return _EmptyDashboard();
        final index = _selectedIndex.clamp(0, vehicles.length - 1);
        return _Dashboard(
          vehicles: vehicles,
          selectedIndex: index,
          pageController: _pageController,
          onVehicleChanged: (i) => setState(() => _selectedIndex = i),
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

String _greetingLine(WidgetRef ref) {
  final name = ref.watch(localProfileProvider).value?.displayName.trim();
  return (name == null || name.isEmpty) ? 'Bonjour' : 'Bonjour $name';
}

/// "Votre Audi Q5 est à jour." / "2 actions sont à prévoir prochainement."
/// - always scoped to the single active vehicle (the one currently shown
/// in the carousel/card above), never an aggregate across the garage: a
/// swipe to another vehicle must change this line too.
class _StatusLine extends ConsumerWidget {
  const _StatusLine({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final actionable = remindersAsync.maybeWhen(
      data: (all) => all.where((r) {
        final u = reminderUrgency(r, currentMileage: vehicle.currentMileage);
        return u == ReminderUrgency.urgent || u == ReminderUrgency.upcoming;
      }).length,
      orElse: () => 0,
    );

    final text = actionable == 0
        ? 'Votre ${vehicle.brand} ${vehicle.model} est à jour.'
        : actionable == 1
            ? '1 action est à prévoir prochainement.'
            : '$actionable actions sont à prévoir prochainement.';

    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 7),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: actionable == 0 ? scheme.tertiary : scheme.secondary,
          ),
        ),
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _EmptyDashboard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_greetingLine(ref), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.directions_car_filled, size: 44, color: scheme.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Bienvenue dans AutoCarnet',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Centralisez l\'entretien, les documents et les dépenses de vos '
                'véhicules - un carnet complet, toujours avec vous.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => context.push('/vehicles/new'),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter mon premier véhicule'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.push('/vehicles/join'),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('Rejoindre un véhicule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({
    required this.vehicles,
    required this.selectedIndex,
    required this.pageController,
    required this.onVehicleChanged,
  });

  final List<Vehicle> vehicles;
  final int selectedIndex;
  final PageController pageController;
  final ValueChanged<int> onVehicleChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = vehicles[selectedIndex];

    return ListView(
      padding: EdgeInsets.fromLTRB(0, AppSpacing.md, 0, fabSafeBottomPadding(context)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greetingLine(ref), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              _StatusLine(vehicle: selected),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (vehicles.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _VehicleCardWithReminders(
              vehicle: vehicles.first,
              onTap: () => context.push('/vehicles/${vehicles.first.id}'),
            ),
          )
        else
          _VehicleCarousel(
            vehicles: vehicles,
            selectedIndex: selectedIndex,
            controller: pageController,
            onChanged: onVehicleChanged,
          ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('À faire prochainement'),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _TodoSection(vehicle: selected),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel(
          'Dernières opérations',
          trailing: _RecentOperationsSeeAllButton(vehicleId: selected.id),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _RecentOperationsSection(vehicle: selected),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Actions rapides'),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _QuickActionsRow(vehicle: selected),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Votre carnet'),
        const SizedBox(height: AppSpacing.sm),
        _InsightsStrip(vehicle: selected),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: trailing == null
          ? text
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [text, trailing!],
            ),
    );
  }
}

/// Wires a single vehicle's own active reminders into [VehicleHeroCard] -
/// the small piece of glue both the single-vehicle and carousel paths need.
class _VehicleCardWithReminders extends ConsumerWidget {
  const _VehicleCardWithReminders({required this.vehicle, required this.onTap});
  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(vehicleActiveRemindersProvider(vehicle.id)).value ?? const [];
    return VehicleHeroCard(vehicle: vehicle, reminders: reminders, onTap: onTap);
  }
}

class _VehicleCarousel extends StatelessWidget {
  const _VehicleCarousel({
    required this.vehicles,
    required this.selectedIndex,
    required this.controller,
    required this.onChanged,
  });

  final List<Vehicle> vehicles;
  final int selectedIndex;
  final PageController controller;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 208,
          child: PageView.builder(
            controller: controller,
            itemCount: vehicles.length,
            onPageChanged: onChanged,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: _VehicleCardWithReminders(
                vehicle: vehicles[i],
                onTap: () => context.push('/vehicles/${vehicles[i].id}'),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < vehicles.length; i++)
              AnimatedContainer(
                duration: AppMotion.fast,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == selectedIndex ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == selectedIndex ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Up to 3 reminders for the active vehicle only that are actually close
/// (overdue, due within 60 days, or within 1 500 km - see
/// [isReminderDueSoon]), nearest first - or a positive "tout est à jour"
/// state when there are none (spec: the section disappears/turns positive,
/// it never just shows an empty list, and never a distant reminder just to
/// fill up to 3). Scoped to a single [vehicle]: swiping to another vehicle
/// must never leave a stale reminder from the previous one on screen, and
/// a vehicle with zero due-soon reminders must show "Tout est à jour" even
/// while another vehicle in the garage has several.
class _TodoSection extends ConsumerWidget {
  const _TodoSection({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    return remindersAsync.when(
      loading: () => const SizedBox(
          height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => const SizedBox.shrink(),
      data: (reminders) {
        // A single ascending scalar (days or km remaining, whichever is
        // known) is enough on its own: negative values (overdue) sort
        // first automatically, then the soonest/closest next - exactly the
        // "1. dépassé, 2. le plus proche, 3. km restant le plus faible"
        // order the spec asks for, without a separate urgency-rank key.
        double proximity(Reminder r) {
          final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
          final byKm = r.dueMileage != null ? r.dueMileage! - vehicle.currentMileage : null;
          if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
          return byDays ?? byKm ?? double.infinity;
        }

        final top = reminders
            .where((r) => isReminderDueSoon(r, currentMileage: vehicle.currentMileage))
            .toList()
          ..sort((a, b) => proximity(a).compareTo(proximity(b)));

        if (top.isEmpty) return const _AllGoodCard();

        return Column(
          children: [
            for (var i = 0; i < top.length && i < 3; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              _TodoTile(
                reminder: top[i],
                vehicle: vehicle,
                urgency: reminderUrgency(top[i], currentMileage: vehicle.currentMileage),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AllGoodCard extends StatelessWidget {
  const _AllGoodCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: AppElevation.card(scheme),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.tertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tout est à jour', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Aucune action requise pour le moment.',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.reminder, required this.vehicle, required this.urgency});
  final Reminder reminder;
  final Vehicle vehicle;
  final ReminderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railColor = switch (urgency) {
      ReminderUrgency.urgent => scheme.error,
      ReminderUrgency.upcoming => scheme.secondary,
      ReminderUrgency.later || ReminderUrgency.done => scheme.onSurfaceVariant,
    };
    final due = formatReminderDue(reminder, vehicle.currentMileage);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppElevation.card(scheme),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: railColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(reminder.title,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(due,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: AppTypography.mono(context,
                                fontSize: 12, fontWeight: FontWeight.w600, color: railColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Voir tout" always follows whichever vehicle is currently active - it
/// never opens a fixed vehicle's history regardless of what's selected.
class _RecentOperationsSeeAllButton extends ConsumerWidget {
  const _RecentOperationsSeeAllButton({required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEntries =
        (ref.watch(vehicleMaintenanceProvider(vehicleId)).value ?? const []).isNotEmpty;
    if (!hasEntries) return const SizedBox.shrink();
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => context.push('/vehicles/$vehicleId/timeline'),
      child: const Text('Voir tout', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// The 3 most recent real business interventions for the active vehicle -
/// a fiche edit, a plain mileage correction, a sync pass or an audit entry
/// never appear here, since they simply aren't maintenance operations
/// (RG-TIME-002 / bloc "Journal d'audit" already keeps them out of this
/// data source entirely).
class _RecentOperationsSection extends ConsumerWidget {
  const _RecentOperationsSection({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(vehicleMaintenanceProvider(vehicle.id));
    return entriesAsync.when(
      loading: () => const SizedBox(
          height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => const SizedBox.shrink(),
      data: (entries) {
        if (entries.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: AppElevation.card(Theme.of(context).colorScheme),
            ),
            child: Text(
              'Aucune opération enregistrée pour l\'instant.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }
        final top = entries.take(3).toList();
        return Column(
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.xs),
              _RecentOperationTile(
                entry: top[i],
                onTap: () => showMaintenanceFormSheet(context,
                    vehicleId: vehicle.id, currentMileage: vehicle.currentMileage, editing: top[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RecentOperationTile extends StatelessWidget {
  const _RecentOperationTile({required this.entry, required this.onTap});
  final MaintenanceEntry entry;
  final VoidCallback onTap;

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppElevation.card(scheme),
      ),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.build_outlined, size: 17, color: scheme.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(
                        '${_fmtDate(entry.date)} · ${formatAmount(entry.mileage)} km',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Direct-tap actions - each opens its target form immediately (no
/// intermediate sheet), unlike the rarer "add/join a vehicle" action which
/// stays behind the tab's FAB. Document was dropped: it's a rarer action
/// than the other three and didn't earn a permanent slot on the home screen
/// just to fill a 2x2 grid. "Opération" is the most common of the three, so
/// it gets a real primary CTA (bloc design-review 2026: "un bouton
/// principal plus important") - Kilométrage/Plein stay direct-tap too, just
/// visually secondary.
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => showMaintenanceFormSheet(context,
                vehicleId: vehicle.id, currentMileage: vehicle.currentMileage),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppElevation.cta(scheme.primary),
              ),
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle, color: scheme.onPrimary, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('Ajouter une opération',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                icon: Icons.speed_outlined,
                label: 'Kilométrage',
                onTap: () => showMileageUpdateSheet(context, ref, vehicle),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _QuickActionTile(
                icon: Icons.local_gas_station_outlined,
                label: 'Plein',
                onTap: () => showFuelFormSheet(context,
                    vehicleId: vehicle.id, currentMileage: vehicle.currentMileage),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: AppElevation.card(scheme),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: scheme.primary),
              ),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact 2-column grid read on the carnet as a whole - never an
/// analytics dashboard, just the handful of numbers an owner actually
/// wants at a glance, all visible at once without any horizontal swipe.
class _InsightsStrip extends ConsumerWidget {
  const _InsightsStrip({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(vehicleHealthScoreProvider(vehicle));
    final expenseStats = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final maintenance = ref.watch(vehicleMaintenanceProvider(vehicle.id)).value;
    final mileageHistory = ref.watch(vehicleMileageHistoryProvider(vehicle.id)).value;
    final currency = ref.watch(defaultCurrencyProvider);

    final lastMaintenance = (maintenance == null || maintenance.isEmpty) ? null : maintenance.first;
    final monthlyPace = mileageHistory == null ? null : estimateMonthlyPaceKm(mileageHistory);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Santé',
                  value: health == null ? '—' : '${health.score}',
                  sub: '/ 100',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  label: 'Dépenses ${DateTime.now().year}',
                  value: expenseStats.maybeWhen(
                      data: (s) => formatAmount(s.thisYear), orElse: () => '—'),
                  sub: currency,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Dernier entretien',
                  value: lastMaintenance == null ? 'Aucun' : _monthsAgo(lastMaintenance.date),
                  sub: lastMaintenance?.category ?? '',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  label: 'Km / an estimé',
                  value: monthlyPace == null ? '—' : formatAmount(monthlyPace * 12),
                  sub: 'km',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _monthsAgo(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days < 31) return 'Il y a ${days}j';
    final months = (days / 30.4).round();
    return 'Il y a ${months}mois';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.sub});
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: AppElevation.card(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 9.5, letterSpacing: 0.3, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTypography.mono(context, fontSize: 17, fontWeight: FontWeight.w600)),
          if (sub.isNotEmpty)
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
