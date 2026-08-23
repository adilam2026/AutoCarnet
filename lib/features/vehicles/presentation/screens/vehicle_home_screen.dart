import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database.dart';
import '../../../../core/sync/vehicle_sync_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/widgets/loading_error_views.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../account/data/account_repository.dart';
import '../../../documents/data/document_repository.dart';
import '../../../documents/presentation/document_form_sheet.dart';
import '../../../documents/presentation/document_status_chip.dart';
import '../../../expenses/data/expense_repository.dart';
import '../../../fuel/data/fuel_repository.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../maintenance/domain/revision_estimation.dart';
import '../../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../../reminders/data/reminder_repository.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/vehicle_card_color.dart';
import '../../domain/vehicle_compliance_rules.dart';
import '../../domain/vehicle_health.dart';
import '../../domain/vehicle_ownership.dart';
import '../../../sharing/presentation/share_vehicle_screen.dart';
import '../../../sharing/presentation/vehicle_access_screen.dart';
import '../../../dashboard/presentation/widgets/vehicle_hero_card.dart'
    show formatReminderDue;
import '../providers/vehicle_form_providers.dart';
import '../widgets/add_operation_sheet.dart';
import '../widgets/health_factors_sheet.dart';
import '../widgets/mileage_update_sheet.dart';
import 'vehicle_edit_screen.dart';

/// The carnet of a single vehicle: a real dashboard, not a near-empty
/// screen - mileage, what needs attention, what was last done, an overview,
/// and the administrative essentials, all built only from data already
/// collected elsewhere (Principe 2). Every module reachable from here
/// (RG-VEH-002: all operations belong to exactly one vehicle) is a
/// full-screen push, never a horizontal tab strip.
class VehicleHomeScreen extends ConsumerWidget {
  const VehicleHomeScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleByIdProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => const Scaffold(
        body: ErrorView(message: 'Impossible de charger ce véhicule. Réessayez dans un instant.'),
      ),
      data: (vehicle) => vehicle == null
          ? _VehicleSyncingView(vehicleId: vehicleId)
          : _VehicleHomeBody(vehicle: vehicle),
    );
  }
}

/// Shown instead of crashing when a vehicle is known to exist (we just
/// navigated here, e.g. right after accepting a share invite) but hasn't
/// reached this device's local mirror yet - a normal, momentary state, not
/// an error. Nudges a sync and waits; if the vehicle still hasn't shown up
/// after a bounded number of attempts (stale/invalid link, revoked access,
/// ...) it offers a safe way out instead of waiting forever.
class _VehicleSyncingView extends ConsumerStatefulWidget {
  const _VehicleSyncingView({required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<_VehicleSyncingView> createState() => _VehicleSyncingViewState();
}

class _VehicleSyncingViewState extends ConsumerState<_VehicleSyncingView> {
  static const _maxAttempts = 6;
  int _attempts = 0;
  bool _gaveUp = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _attemptSync();
  }

  Future<void> _attemptSync() async {
    if (!mounted || _attempts >= _maxAttempts) {
      if (mounted && _attempts >= _maxAttempts) setState(() => _gaveUp = true);
      return;
    }
    _attempts++;
    try {
      await ref.read(vehicleSyncServiceProvider).syncNow();
    } catch (_) {
      // Offline or transient failure: keep retrying on the timer below.
    }
    if (!mounted) return;
    final stillMissing = ref.read(vehicleByIdProvider(widget.vehicleId)).value == null;
    if (stillMissing && _attempts < _maxAttempts) {
      _timer = Timer(const Duration(seconds: 1), _attemptSync);
    } else if (stillMissing) {
      setState(() => _gaveUp = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gaveUp) {
      return Scaffold(
        appBar: AppBar(title: const Text('Véhicule introuvable')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sync_problem_outlined,
                    size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Ce véhicule n\'est pas (encore) disponible sur cet appareil.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Retour à mes véhicules'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpacing.md),
              Text('Synchronisation en cours...', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleHomeBody extends ConsumerWidget {
  const _VehicleHomeBody({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authStateChangesProvider);
    final currentUserId = ref.read(accountRepositoryProvider).currentUser?.id;
    final isOwner = isVehicleOwnedByCurrentUser(vehicle, currentUserId);
    final canEdit = canEditVehicle(vehicle, currentUserId);
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final activeReminders =
        ref.watch(vehicleActiveRemindersProvider(vehicle.id)).value ?? const [];
    final expenseStats = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStats = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenanceEntries =
        ref.watch(vehicleMaintenanceProvider(vehicle.id)).value ?? const [];
    final documents = ref.watch(vehicleDocumentsProvider(vehicle.id)).value ?? const [];
    final driverDocuments = ref.watch(driverDocumentsProvider).value ?? const [];
    final mileageHistory =
        ref.watch(vehicleMileageHistoryProvider(vehicle.id)).value ?? const [];
    final recentOperations = [...maintenanceEntries]..sort((a, b) => b.date.compareTo(a.date));

    final health = computeVehicleHealthScore(
      activeReminders: activeReminders,
      maintenanceEntries: maintenanceEntries,
      documents: documents,
      completeness: completeness,
    );

    final monthlyPace = estimateMonthlyPaceKm(mileageHistory);
    final nextMaintenanceReminder =
        _pickNextMaintenanceReminder(activeReminders, vehicle.currentMileage);
    final revisionEstimate = nextMaintenanceReminder == null
        ? null
        : estimateFromKnownNextDue(
            nextMileage: nextMaintenanceReminder.dueMileage,
            nextDateThreshold: nextMaintenanceReminder.dueDate,
            currentMileage: vehicle.currentMileage,
            monthlyPaceKm: monthlyPace,
          );

    final lastMileageEntry = mileageHistory.isEmpty
        ? null
        : ([...mileageHistory]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt))).first;
    final cardColor = VehicleCardColor.fromKey(vehicle.cardColorKey);

    return Scaffold(
      appBar: AppBar(
        title: _VehicleIdentityChip(vehicle: vehicle, cardColor: cardColor),
        actions: [
          if (canEdit)
            PopupMenuButton<VehicleStatus>(
              tooltip: 'Statut du véhicule',
              icon: _StatusIndicator(status: vehicle.status),
              onSelected: (status) async {
                await ref.read(vehicleRepositoryProvider).setStatus(vehicle.id, status);
                if (context.mounted) {
                  showAppSnackBar(
                    context,
                    'Statut mis à jour : ${_statusLabel(status)}',
                    icon: Icons.check_circle_outline,
                  );
                }
              },
              itemBuilder: (context) => [
                for (final status in VehicleStatus.values)
                  PopupMenuItem(
                    value: status,
                    child: Row(
                      children: [
                        if (status == vehicle.status)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.check, size: 18),
                          )
                        else
                          const SizedBox(width: 26),
                        Text(_statusLabel(status)),
                      ],
                    ),
                  ),
              ],
            )
          else
            _StatusIndicator(status: vehicle.status),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier la fiche',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => VehicleEditScreen(vehicle: vehicle)),
              ),
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              tooltip: 'Partager le véhicule',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShareVehicleScreen(
                    vehicleId: vehicle.id,
                    vehicleLabel: '${vehicle.brand} ${vehicle.model}',
                  ),
                ),
              ),
            ),
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer le véhicule',
              onPressed: () => _confirmDelete(context, ref, vehicle),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
        children: [
          _VehicleSummaryCard(
            vehicle: vehicle,
            cardColor: cardColor,
            health: health,
            completeness: completeness,
            lastUpdate: lastMileageEntry?.recordedAt,
            onUpdate: canEdit ? () => showMileageUpdateSheet(context, ref, vehicle) : null,
            onComplete: canEdit
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => VehicleEditScreen(vehicle: vehicle)),
                    )
                : null,
            onTapHealth: () => showHealthFactorsSheet(context, health),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('À faire prochainement'),
          const SizedBox(height: AppSpacing.sm),
          if (revisionEstimate != null) ...[
            _NextRevisionCard(estimate: revisionEstimate, title: nextMaintenanceReminder!.title),
            const SizedBox(height: AppSpacing.sm),
          ],
          _TodoCard(
            reminders: activeReminders,
            currentMileage: vehicle.currentMileage,
            excludeReminderId: revisionEstimate != null ? nextMaintenanceReminder!.id : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            'Dernières opérations',
            trailing: recentOperations.isEmpty
                ? null
                : TextButton(
                    onPressed: () => context.push('/vehicles/${vehicle.id}/timeline'),
                    child: const Text('Voir tout'),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RecentOperationsCard(
            entries: recentOperations.take(3).toList(),
            vehicle: vehicle,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Aperçu'),
          const SizedBox(height: AppSpacing.sm),
          _OverviewGrid(
            maintenanceEntries: maintenanceEntries,
            expenseThisYear: expenseStats.maybeWhen(data: (s) => s.thisYear, orElse: () => null),
            fuelStats: fuelStats.maybeWhen(data: (s) => s, orElse: () => null),
            estimatedKmPerYear: monthlyPace == null ? null : monthlyPace * 12,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Administratif'),
          const SizedBox(height: AppSpacing.sm),
          _AdministrativeCard(
            vehicleId: vehicle.id,
            firstRegistrationDate: vehicle.firstRegistrationDate,
            vehicleDocuments: documents,
            driverDocuments: driverDocuments,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Modules'),
          const SizedBox(height: AppSpacing.sm),
          _ModuleTile(
            icon: Icons.description_outlined,
            label: 'Documents',
            trailingCount: documents.length,
            onTap: () => context.push('/vehicles/${vehicle.id}/documents'),
          ),
          _ModuleTile(
            icon: Icons.build_outlined,
            label: 'Entretiens',
            trailingCount: maintenanceEntries.length,
            onTap: () => context.push('/vehicles/${vehicle.id}/maintenance'),
          ),
          _ModuleTile(
            icon: Icons.payments_outlined,
            label: 'Dépenses',
            onTap: () => context.push('/vehicles/${vehicle.id}/expenses'),
          ),
          _ModuleTile(
            icon: Icons.local_gas_station_outlined,
            label: 'Carburant',
            onTap: () => context.push('/vehicles/${vehicle.id}/fuel'),
          ),
          if (ref.read(accountRepositoryProvider).isSignedIn)
            _ModuleTile(
              icon: Icons.people_alt_outlined,
              label: 'Partage et accès',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VehicleAccessScreen(
                    vehicleId: vehicle.id,
                    vehicleLabel: '${vehicle.brand} ${vehicle.model}',
                    isOwner: isOwner,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => showAddOperationSheet(context, ref, vehicle: vehicle),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une opération'),
            )
          : null,
    );
  }

  /// Featured reminder for the "prochaine révision" card: the maintenance
  /// reminder that's closest to its threshold, whichever unit (date or
  /// mileage) gets there first.
  Reminder? _pickNextMaintenanceReminder(List<Reminder> reminders, double currentMileage) {
    final candidates = reminders.where((r) => r.sourceType == 'maintenance').toList();
    if (candidates.isEmpty) return null;
    double keyOf(Reminder r) {
      final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
      final byKm = r.dueMileage != null ? r.dueMileage! - currentMileage : null;
      if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
      return byDays ?? byKm ?? double.infinity;
    }

    candidates.sort((a, b) => keyOf(a).compareTo(keyOf(b)));
    return candidates.first;
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Vehicle vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce véhicule ?'),
        content: Text(
          '${vehicle.brand} ${vehicle.model} et tout son historique '
          '(entretiens, dépenses, documents...) ne seront plus visibles '
          'dans AutoCarnet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(vehicleRepositoryProvider).softDelete(vehicle.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Compact reminder of "which vehicle am I in" (mission point 6-9): reuses
/// the exact same identity colour as the accueil's carte véhicule, without
/// recreating that whole card here - a pill just large enough for the icon
/// and name, never a full-width coloured bandeau competing with the header's
/// actions (modifier/partager/supprimer). The vehicle name always gets an
/// explicit [ColorScheme.onSurface] here rather than relying on any
/// ambient/AppBar text styling, so it can never again render as
/// unreadable white-on-white regardless of what the surrounding AppBar
/// theme resolves to.
class _VehicleIdentityChip extends StatelessWidget {
  const _VehicleIdentityChip({required this.vehicle, required this.cardColor});
  final Vehicle vehicle;
  final VehicleCardColor cardColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = cardColor.onLightSurface;
    return Container(
      key: const Key('vehicleIdentityChip'),
      padding: const EdgeInsets.fromLTRB(5, 4, 11, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.07), scheme.surfaceContainerLowest),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: accent.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: 'vehicle-avatar-${vehicle.id}',
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: cardColor.color, shape: BoxShape.circle),
              child: Icon(Icons.directions_car, size: 13, color: cardColor.onColor),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${vehicle.brand} ${vehicle.model}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The vehicle as a real "instrument cluster" hero, matching the home
/// dashboard's VehicleHeroCard language (mono odometer, health ring) -
/// merges the old separate header/mileage cards into one premium summary.
class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({
    required this.vehicle,
    required this.cardColor,
    required this.health,
    required this.completeness,
    required this.lastUpdate,
    required this.onUpdate,
    required this.onComplete,
    required this.onTapHealth,
  });
  final Vehicle vehicle;
  final VehicleCardColor cardColor;
  final VehicleHealthScore health;
  final double completeness;
  final DateTime? lastUpdate;
  final VoidCallback? onUpdate;
  final VoidCallback? onComplete;
  final VoidCallback onTapHealth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completenessPercent = (completeness * 100).round();
    final subtitleParts = <String>[
      if (vehicle.year != null) '${vehicle.year}',
      if (vehicle.plate != null) vehicle.plate!,
    ];

    return Container(
      key: const Key('vehicleSummaryCardContour'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // A thin accent, never a filled background (mission point 11: this
        // card carries a lot of information and must stay very readable) -
        // the same continuity colour as the accueil card and the fiche
        // header's identity chip.
        border: Border.all(color: cardColor.onLightSurface, width: 1.2),
        boxShadow: AppElevation.card(scheme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(vehicle.currentMileage.toStringAsFixed(0),
                  style: AppTypography.mono(context, fontSize: 24, fontWeight: FontWeight.w700)),
              const SizedBox(width: 5),
              Text('km', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const Spacer(),
              _HealthBadge(score: health.score, onTap: onTapHealth),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (subtitleParts.isNotEmpty) subtitleParts.join(' · '),
              lastUpdate != null ? 'MAJ le ${_fmt(lastUpdate!)}' : 'Jamais mis à jour',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (onUpdate != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onUpdate,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: const Size(0, 0),
                ),
                child: const Text('Mettre à jour le kilométrage', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
          if (completenessPercent < 100) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: completeness,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('$completenessPercent %',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                if (onComplete != null)
                  TextButton(
                    onPressed: onComplete,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Compléter', style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.score, required this.onTap});
  final int score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = score >= 80;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: (ok ? scheme.secondary : scheme.tertiary).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: ok ? scheme.secondary : scheme.tertiary),
            ),
            Text('Santé $score',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ok ? scheme.secondary : scheme.tertiary)),
          ],
        ),
      ),
    );
  }
}

class _NextRevisionCard extends StatelessWidget {
  const _NextRevisionCard({required this.estimate, required this.title});
  final RevisionEstimate estimate;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = estimate.isOverdue;
    final railColor = overdue ? scheme.error : scheme.secondary;
    final lines = <String>[];
    if (estimate.remainingKm != null) {
      lines.add(overdue && estimate.isOverdueByMileage
          ? 'Dépassée de ${(-estimate.remainingKm!).toStringAsFixed(0)} km'
          : 'Reste ${estimate.remainingKm!.toStringAsFixed(0)} km');
    }
    if (estimate.probableDate != null) {
      final isPastDate =
          estimate.isOverdueByDate && estimate.probableDate == estimate.nextDateByFrequency;
      lines.add(isPastDate
          ? 'Échéance dépassée depuis le ${_fmt(estimate.probableDate!)}'
          : 'Estimation : ${_fmt(estimate.probableDate!)}');
    } else if (estimate.remainingKm != null) {
      lines.add('Ajoutez régulièrement votre kilométrage pour une estimation de date.');
    }
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          overdue ? Icons.warning_amber_outlined : Icons.event_available_outlined,
                          size: 20,
                          color: railColor,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              for (final l in lines)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(l,
                                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                ),
                            ],
                          ),
                        ),
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

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.reminders,
    required this.currentMileage,
    this.excludeReminderId,
  });
  final List<Reminder> reminders;
  final double currentMileage;
  final String? excludeReminderId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = reminders.where((r) => r.id != excludeReminderId).toList()
      ..sort((a, b) {
        double keyOf(Reminder r) {
          final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
          final byKm = r.dueMileage != null ? r.dueMileage! - currentMileage : null;
          if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
          return byDays ?? byKm ?? double.infinity;
        }
        return keyOf(a).compareTo(keyOf(b));
      });

    if (visible.isEmpty) {
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
            const Text('Tout est à jour', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visible.length && i < 4; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _ReminderTile(reminder: visible[i], currentMileage: currentMileage),
        ],
      ],
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.currentMileage});
  final Reminder reminder;
  final double currentMileage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgency = reminderUrgency(reminder, currentMileage: currentMileage);
    final railColor = switch (urgency) {
      ReminderUrgency.urgent => scheme.error,
      ReminderUrgency.upcoming => scheme.secondary,
      ReminderUrgency.later || ReminderUrgency.done => scheme.onSurfaceVariant,
    };

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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        Text(formatReminderDue(reminder, currentMileage),
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

/// Only real automobile interventions - never vehicle-created, fiche-
/// modifiée or kilométrage-mis-à-jour noise, which belong to the audit
/// trail instead (bloc "historique métier vs journal d'audit").
class _RecentOperationsCard extends ConsumerWidget {
  const _RecentOperationsCard({
    required this.entries,
    required this.vehicle,
  });
  final List<MaintenanceEntry> entries;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Aucune opération enregistrée pour l\'instant. Commencez votre '
            'carnet avec votre dernière vidange ou révision.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            ListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
              title: Text(entries[i].category,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_fmt(entries[i].date)} · ${entries[i].mileage.toStringAsFixed(0)} km',
              ),
              trailing: Text(
                (entries[i].partsCost + entries[i].laborCost) > 0
                    ? '${formatAmount(entries[i].partsCost + entries[i].laborCost)} ${entries[i].currency}'
                    : '',
                style: AppTypography.mono(context, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onTap: () => showMaintenanceFormSheet(
                context,
                vehicleId: vehicle.id,
                currentMileage: vehicle.currentMileage,
                editing: entries[i],
              ),
            ),
            if (i < entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

/// Santé lives as the ring badge on [_VehicleSummaryCard] now - never
/// duplicated here too. A 2x2 grid (mission point 17-D: the accueil's
/// "Votre carnet" strip was removed, not deleted - "Km / an estimé" was
/// only ever shown there, so it joins this existing "Aperçu" section as a
/// 4th tile rather than becoming a brand-new section of its own).
class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({
    required this.maintenanceEntries,
    required this.expenseThisYear,
    required this.fuelStats,
    required this.estimatedKmPerYear,
  });
  final List<MaintenanceEntry> maintenanceEntries;
  final double? expenseThisYear;
  final FuelStats? fuelStats;
  final double? estimatedKmPerYear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _OverviewTile(
                  icon: Icons.build_outlined,
                  label: 'Entretien',
                  value: maintenanceEntries.isEmpty
                      ? null
                      : '${([...maintenanceEntries]..sort((a, b) => b.date.compareTo(a.date))).first.mileage.toStringAsFixed(0)} km',
                  emptyMessage: 'Aucun entretien',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OverviewTile(
                  icon: Icons.payments_outlined,
                  label: 'Dépenses ${DateTime.now().year}',
                  value: expenseThisYear == null ? null : formatAmount(expenseThisYear!),
                  emptyMessage: 'Pas de données',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _OverviewTile(
                  icon: Icons.speed_outlined,
                  label: 'Consommation',
                  value: fuelStats?.averageConsumption != null
                      ? '${fuelStats!.averageConsumption!.toStringAsFixed(1)} L/100'
                      : null,
                  emptyMessage: 'Pas assez de pleins',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OverviewTile(
                  icon: Icons.trending_up_outlined,
                  label: 'Km / an estimé',
                  value: estimatedKmPerYear == null
                      ? null
                      : '${formatAmount(estimatedKmPerYear!)} km',
                  emptyMessage: 'Pas assez de données',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emptyMessage,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String? emptyMessage;

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
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, letterSpacing: 0.3, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          value != null
              ? Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.mono(context, fontSize: 15, fontWeight: FontWeight.w600))
              : Text(
                  emptyMessage ?? 'Pas de données',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
        ],
      ),
    );
  }
}

class _AdministrativeCard extends StatelessWidget {
  const _AdministrativeCard({
    required this.vehicleId,
    required this.firstRegistrationDate,
    required this.vehicleDocuments,
    required this.driverDocuments,
  });
  final String vehicleId;
  final DateTime? firstRegistrationDate;
  final List<DocumentWithVersion> vehicleDocuments;
  final List<DocumentWithVersion> driverDocuments;

  static const _rows = [
    ('Assurance', false),
    ('Visite technique', false),
    ('Vignette', false),
    ('Permis de conduire', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            _buildRow(context, _rows[i].$1, _rows[i].$2),
            if (i < _rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, String type, bool isDriverDoc) {
    final pool = isDriverDoc ? driverDocuments : vehicleDocuments;
    DocumentWithVersion? match;
    for (final d in pool) {
      if (d.document.type == type) {
        match = d;
        break;
      }
    }
    if (match == null) {
      if (type == 'Visite technique' && !visiteTechniqueMandatoryYet(firstRegistrationDate)) {
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          leading: Icon(Icons.info_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          title: const Text('Visite technique'),
          subtitle: const Text('Pas encore obligatoire (à partir de la 5ᵉ année)'),
        );
      }
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        leading: const Icon(Icons.add_circle_outline),
        title: Text('Ajouter $type'),
        onTap: () => showDocumentFormSheet(
          context,
          vehicleId: isDriverDoc ? null : vehicleId,
          initialType: type,
        ),
      );
    }
    final expiry = match.version?.expiryDate;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      title: Text(type),
      subtitle: expiry != null
          ? Text('Expire le ${_fmt(expiry)}')
          : const Text('Aucune échéance renseignée'),
      trailing: DocumentStatusChip(status: match.computedStatus),
      onTap: () => showDocumentFormSheet(
        context,
        vehicleId: isDriverDoc ? null : vehicleId,
        renewing: match!.document,
        renewingVersion: match.version,
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingCount,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Card(
        child: ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppElevation.surfaceAccent(scheme),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: scheme.primary, size: 19),
          ),
          title: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingCount != null && trailingCount! > 0)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(
                    '$trailingCount',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});
  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      VehicleStatus.active => scheme.primary,
      VehicleStatus.archived => scheme.outline,
      VehicleStatus.sold => scheme.tertiary,
      VehicleStatus.destroyed => scheme.error,
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}
