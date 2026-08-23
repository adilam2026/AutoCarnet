import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../fuel/presentation/fuel_form_sheet.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../reminders/domain/reminder_urgency.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/presentation/widgets/mileage_update_sheet.dart';
import 'widgets/vehicle_hero_card.dart';

/// AutoCarnet's home base ("Premium clair" concept, 2026; cohérence pass:
/// accueil trimmed to a short synthesis) - a real personal dashboard, not a
/// bare vehicle list: a greeting, the vehicle(s) as the central element,
/// what needs attention, one-tap logging. Deliberately NOT an analytics
/// dashboard: "Votre carnet" (santé/dépenses/dernier entretien/km-an) was
/// removed from this screen so it fits with minimal scroll on a real
/// phone - none of that data was deleted, it's a display-only trim (santé
/// stays on the vehicle card, the rest live in the fiche véhicule's
/// "Aperçu" section). Every number shown here already exists somewhere in
/// the app (health score, reminders) - nothing is invented for this
/// screen.
class VehiclesListBody extends ConsumerStatefulWidget {
  const VehiclesListBody({super.key});

  @override
  ConsumerState<VehiclesListBody> createState() => _VehiclesListBodyState();
}

class _VehiclesListBodyState extends ConsumerState<VehiclesListBody> {
  int _selectedIndex = 0;
  PageController? _pageController;
  int _pageControllerVehicleCount = 0;

  /// Half-width of the virtual paging window either side of the real
  /// index-0 vehicle (bloc 12-14: the carousel must loop circularly in
  /// both directions with no dead end and no visible jump). A fixed,
  /// generous virtual index range - not a literal infinite data structure
  /// - is the standard, invisible-to-the-user way to get that: at 100 000
  /// pages either side, even a garage of 2 vehicles allows 50 000 full
  /// loops per direction in a single session, far past anything a real
  /// swipe test could reach.
  static const int _virtualHalfWindow = 100000;

  /// Lazily (re)built only when the vehicle count actually changes (a
  /// vehicle added/removed) - recreating it on every rebuild would reset
  /// the user's current swipe position for no reason.
  PageController _carouselController(int vehicleCount) {
    if (_pageController == null || _pageControllerVehicleCount != vehicleCount) {
      _pageController?.dispose();
      final aligned = _virtualHalfWindow - (_virtualHalfWindow % vehicleCount);
      _pageController = PageController(
        viewportFraction: 0.9,
        initialPage: aligned + _selectedIndex,
      );
      _pageControllerVehicleCount = vehicleCount;
    }
    return _pageController!;
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return vehiclesAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          const ErrorView(message: 'Impossible de charger vos véhicules. Réessayez dans un instant.'),
      data: (vehicles) {
        if (vehicles.isEmpty) return _EmptyDashboard();
        final index = _selectedIndex.clamp(0, vehicles.length - 1);
        return _Dashboard(
          vehicles: vehicles,
          selectedIndex: index,
          pageController: _carouselController(vehicles.length),
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
        const SizedBox(height: 14),
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
        const SizedBox(height: AppSpacing.md),
        _SectionLabel('À faire prochainement'),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _TodoSection(vehicle: selected),
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionLabel(
          'Dernières opérations',
          trailing: _RecentOperationsSeeAllButton(vehicleId: selected.id),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _RecentOperationsSection(vehicle: selected),
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionLabel('Actions rapides'),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: _QuickActionsRow(vehicle: selected),
        ),
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

  /// A large-but-finite virtual page count (see
  /// _VehiclesListBodyState._virtualHalfWindow for why this is invisible
  /// to the user) - real vehicles are addressed as `virtualIndex %
  /// vehicles.length`, never by the virtual index itself.
  static const int _virtualPageCount = 200000;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Sized to Variant A's actual content height (identity band +
        // facts line + "voir la fiche" row, each with their own padding) -
        // a mismatch here either clips the card or leaves an empty gap
        // under it.
        SizedBox(
          height: 130,
          child: PageView.builder(
            controller: controller,
            itemCount: _virtualPageCount,
            onPageChanged: (virtualIndex) => onChanged(virtualIndex % vehicles.length),
            itemBuilder: (context, virtualIndex) {
              final vehicle = vehicles[virtualIndex % vehicles.length];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: _VehicleCardWithReminders(
                  vehicle: vehicle,
                  onTap: () => context.push('/vehicles/${vehicle.id}'),
                ),
              );
            },
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

        if (top.isEmpty) return const _AllGoodRow();

        final urgencies = [
          for (final r in top) reminderUrgency(r, currentMileage: vehicle.currentMileage),
        ];
        // V2.1 pass: a due action gives the section real visual weight
        // instead of another plain white card - a severity-tinted surface
        // and top accent bar (red if anything is overdue/urgent, orange
        // otherwise), matching the "À faire prochainement" reference
        // behaviour the top petrol accent bar on the vehicle card was
        // itself validated against.
        final isDanger = urgencies.contains(ReminderUrgency.urgent);

        return _TodoSurface(
          isDanger: isDanger,
          children: [
            for (var i = 0; i < top.length; i++)
              _TodoTile(reminder: top[i], vehicle: vehicle, urgency: urgencies[i]),
          ],
        );
      },
    );
  }
}

/// The tinted, top-accented surface a non-empty "À faire prochainement"
/// gets (V2.1 pass) - see [_TodoSection]. [ListSurface] (plain, untinted)
/// stays reserved for "Dernières opérations" and other neutral lists.
class _TodoSurface extends StatelessWidget {
  const _TodoSurface({required this.isDanger, required this.children});
  final bool isDanger;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // errorContainer/tertiaryContainer already equal the mockup's own
    // --danger-soft/--warning-soft tones - used at full strength, not
    // diluted, so the section reads with the same visible weight as the
    // validated reference.
    final tint = isDanger ? scheme.errorContainer : scheme.tertiaryContainer;
    final accent = isDanger ? scheme.error : scheme.tertiary;
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: AppElevation.card(scheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 3, color: accent),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: scheme.shadow.withValues(alpha: 0.06)),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AllGoodRow extends StatelessWidget {
  const _AllGoodRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: AppElevation.card(scheme),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.check, size: 15, color: scheme.secondary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tout est à jour',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Aucune action requise',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
    final (iconColor, valueColor, icon) = switch (urgency) {
      ReminderUrgency.urgent => (scheme.error, scheme.error, Icons.warning_amber_rounded),
      ReminderUrgency.upcoming => (scheme.tertiary, scheme.tertiary, Icons.event_outlined),
      ReminderUrgency.later ||
      ReminderUrgency.done =>
        (scheme.onSurfaceVariant, scheme.onSurfaceVariant, Icons.event_outlined),
    };
    final due = formatReminderDue(reminder, vehicle.currentMileage);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          // White icon chip (never severity-tinted) - the surrounding
          // _TodoSurface already carries the severity tint, so the chip's
          // job here is contrast, matching the "À faire prochainement"
          // reference row.
          Container(
            width: 28,
            height: 28,
            decoration:
                BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(reminder.title,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(due,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: AppTypography.mono(context,
                  fontSize: 14, fontWeight: FontWeight.w800, color: valueColor)),
        ],
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
              borderRadius: BorderRadius.circular(AppRadius.lg),
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
        // V2.1 pass: capped at 2 (was 3) - "Voir tout" is right there for
        // the rest, and this keeps "Votre carnet" higher in the viewport.
        final top = entries.take(2).toList();
        return ListSurface(
          children: [
            for (final entry in top)
              _RecentOperationTile(
                entry: entry,
                onTap: () => showMaintenanceFormSheet(context,
                    vehicleId: vehicle.id, currentMileage: vehicle.currentMileage, editing: entry),
              ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.build_outlined, size: 14, color: scheme.onSurfaceVariant),
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
                      '${formatAmount(entry.mileage)} km',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(_fmtDate(entry.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Direct-tap actions - each opens its target form immediately, no
/// intermediate sheet. Three equal tiles rather than one giant primary CTA
/// plus a smaller pair (bloc design-review 2026, V2 pass: a full-width
/// coloured button here duplicated the tab's own "Ajouter" FAB - "choisis
/// une logique... pas deux CTA concurrents"). Document stays off this row:
/// it's rarer than the other three and didn't earn a permanent slot.
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.build_outlined,
            label: 'Entretien',
            onTap: () => showMaintenanceFormSheet(context,
                vehicleId: vehicle.id, currentMileage: vehicle.currentMileage),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
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
    );
  }
}

/// A compact horizontal pill (icon + label inline) - V2.1 pass: the earlier
/// icon-on-top tile competed too much with the vehicle card for visual
/// weight; this row is deliberately smaller and never colour-blocked.
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
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppElevation.surfaceAccent(scheme),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: scheme.primary),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

