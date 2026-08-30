import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/sync/vehicle_sync_diagnostics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/icon_chip.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/section_header.dart';
import '../../vehicles/data/vehicle_repository.dart';

/// Mission 2026, real-device incident report: a vehicle created while
/// genuinely signed in never reached Supabase, twice, with no way for
/// either the user or Claude to see WHY without a computer and adb. This
/// screen exposes the engine's own internal sync state directly on the
/// device - no logcat, no SQL access needed - so the exact failure point
/// (never attempted / failed with a specific error / actually synced) is
/// visible on the phone itself.
///
/// Deliberately technical, not marketing-polished (mission point 3's own
/// framing: "pas forcément à afficher en permanence à l'utilisateur, mais
/// le moteur doit le connaître précisément") - reachable from Compte &
/// sécurité, never on the main navigation.
class SyncDiagnosticsScreen extends ConsumerWidget {
  const SyncDiagnosticsScreen({super.key});

  static String formatDate(DateTime? d) {
    if (d == null) return 'jamais';
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _stateLabel(EntitySyncState state) => switch (state) {
        EntitySyncState.synced => 'Synchronisé',
        EntitySyncState.queued => 'En attente (pas encore tenté)',
        EntitySyncState.syncing => 'Synchronisation en cours',
        EntitySyncState.failed => 'Échec de synchronisation',
      };

  Color _stateColor(BuildContext context, EntitySyncState state) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      EntitySyncState.synced => Colors.green,
      EntitySyncState.queued => scheme.outline,
      EntitySyncState.syncing => Colors.orange,
      EntitySyncState.failed => scheme.error,
    };
  }

  IconData _stateIcon(EntitySyncState state) => switch (state) {
        EntitySyncState.synced => Icons.cloud_done_outlined,
        EntitySyncState.queued => Icons.schedule_outlined,
        EntitySyncState.syncing => Icons.sync,
        EntitySyncState.failed => Icons.cloud_off_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    final failingAsync = ref.watch(_failingOutboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic de synchronisation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Resynchroniser tout',
            onPressed: () async {
              await ref.read(syncCoordinatorProvider).resyncNow();
              ref.invalidate(_failingOutboxProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Synchronisation relancée')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SectionHeader('État global'),
          const SizedBox(height: AppSpacing.sm),
          ListSurface(
            children: [
              ListTile(
                leading: IconChip(
                  status.pendingCount == 0 ? Icons.check_circle_outline : Icons.schedule_outlined,
                  color: status.pendingCount == 0 ? Colors.green : Colors.orange,
                ),
                title: Text('${status.pendingCount} modification(s) en attente'),
                subtitle: Text('${status.failedCount} en échec (retry automatique)'),
              ),
              ListTile(
                leading: const IconChip(Icons.check_circle_outline),
                title: const Text('Dernière synchronisation réussie'),
                subtitle: Text(formatDate(status.lastSuccessAt)),
              ),
              ListTile(
                leading: IconChip(
                  status.hasUnresolvedError ? Icons.error_outline : Icons.check_circle_outline,
                  color: status.hasUnresolvedError
                      ? Theme.of(context).colorScheme.error
                      : Colors.green,
                ),
                title: const Text('Dernière erreur'),
                subtitle: Text(status.lastErrorMessage ?? 'aucune'),
              ),
              ListTile(
                leading: const IconChip(Icons.history),
                title: const Text('Dernière tentative'),
                subtitle: Text(formatDate(status.lastAttemptAt)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Véhicules'),
          const SizedBox(height: AppSpacing.sm),
          vehiclesAsync.when(
            data: (vehicles) => vehicles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text('Aucun véhicule.'),
                  )
                : Column(
                    children: [
                      for (final vehicle in vehicles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _VehicleDiagnosticCard(
                            vehicle: vehicle,
                            stateIcon: _stateIcon,
                            stateColor: _stateColor,
                            stateLabel: _stateLabel,
                          ),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur : $e'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Opérations en échec (détail global)'),
          const SizedBox(height: AppSpacing.sm),
          failingAsync.when(
            data: (rows) => rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text('Aucune opération en échec actuellement.'),
                  )
                : ListSurface(
                    children: [
                      for (final row in rows)
                        ListTile(
                          leading: IconChip(Icons.error_outline,
                              color: Theme.of(context).colorScheme.error),
                          title: Text('${row.entityType} (${row.operation}) - '
                              'id: ${row.entityId}'),
                          subtitle: Text(
                            'Tentatives : ${row.retryCount}\n'
                            'Dernière tentative : ${formatDate(row.lastAttemptAt)}\n'
                            'Erreur : ${row.lastError ?? "inconnue"}',
                          ),
                          isThreeLine: true,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur : $e'),
          ),
        ],
      ),
    );
  }
}

final _failingOutboxProvider = FutureProvider.autoDispose<List<SyncOutboxData>>((ref) {
  return ref.watch(syncOutboxRepositoryProvider).failing();
});

/// One vehicle's full technical picture: raw local fields, its outbox
/// trace if any, an on-demand full pipeline diagnostic run (mission point:
/// "chaque étape ... OK / ÉCHEC / NON EXÉCUTÉ, avec horodatage"), and a
/// live, independent Supabase lookup by UUID - the two never share state,
/// so a local report that says "synced" while the live cloud check says
/// "absent" is visible as exactly that contradiction, not silently
/// reconciled by the screen.
class _VehicleDiagnosticCard extends ConsumerStatefulWidget {
  const _VehicleDiagnosticCard({
    required this.vehicle,
    required this.stateIcon,
    required this.stateColor,
    required this.stateLabel,
  });

  final Vehicle vehicle;
  final IconData Function(EntitySyncState) stateIcon;
  final Color Function(BuildContext, EntitySyncState) stateColor;
  final String Function(EntitySyncState) stateLabel;

  @override
  ConsumerState<_VehicleDiagnosticCard> createState() => _VehicleDiagnosticCardState();
}

class _VehicleDiagnosticCardState extends ConsumerState<_VehicleDiagnosticCard> {
  VehicleSyncDiagnosticReport? _report;
  bool _runningDiagnostic = false;

  bool _checkingCloud = false;
  Object? _cloudError;
  Map<String, dynamic>? _cloudRow; // null after a completed check == absent
  bool _cloudChecked = false;

  Future<void> _runDiagnostic() async {
    setState(() {
      _runningDiagnostic = true;
      _report = null;
    });
    final coordinator = ref.read(syncCoordinatorProvider);
    final runner = VehicleSyncDiagnosticRunner(
      ref.read(appDatabaseProvider),
      coordinator.vehicles,
      () => Supabase.instance.client,
    );
    final report = await runner.runFor(widget.vehicle.id);
    if (!mounted) return;
    setState(() {
      _report = report;
      _runningDiagnostic = false;
    });
  }

  Future<void> _checkCloud() async {
    setState(() {
      _checkingCloud = true;
      _cloudError = null;
      _cloudChecked = false;
    });
    try {
      final rows = await Supabase.instance.client
          .from('vehicles')
          .select()
          .eq('id', widget.vehicle.id)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _cloudRow = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
        _cloudChecked = true;
        _checkingCloud = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudError = e;
        _checkingCloud = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: FutureBuilder<EntitySyncState>(
          future: ref.read(vehicleRepositoryProvider).syncStateFor(vehicle.id),
          builder: (context, snapshot) {
            final state = snapshot.data;
            return IconChip(
              state == null ? Icons.hourglass_empty : widget.stateIcon(state),
              color: state == null ? null : widget.stateColor(context, state),
            );
          },
        ),
        title: Text('${vehicle.brand} ${vehicle.model}'),
        subtitle: FutureBuilder<EntitySyncState>(
          future: ref.read(vehicleRepositoryProvider).syncStateFor(vehicle.id),
          builder: (context, snapshot) =>
              Text(snapshot.data == null ? 'chargement...' : widget.stateLabel(snapshot.data!)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rawFieldsTable(context),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _runningDiagnostic ? null : _runDiagnostic,
                        icon: _runningDiagnostic
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: const Text('Synchroniser maintenant\n(diagnostic complet)',
                            textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _checkingCloud ? null : _checkCloud,
                        icon: _checkingCloud
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_queue),
                        label: const Text('Vérifier dans\nle cloud', textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ),
                if (_report != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Diagnostic exécuté le ${SyncDiagnosticsScreen.formatDate(_report!.ranAt)} :',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  for (final step in _report!.steps) _stepTile(context, step),
                ],
                if (_cloudChecked || _cloudError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _cloudResultCard(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rawFieldsTable(BuildContext context) {
    final v = widget.vehicle;
    final rows = <(String, String)>[
      ('ID local / UUID', v.id),
      ('user_id (propriétaire local, "ownerId")', v.ownerId ?? '(vide - jamais confirmé par un pull)'),
      ('created_by / updated_by', '${v.createdBy ?? "—"} / ${v.updatedBy ?? "—"}'),
      ('syncStatus (brut)', v.syncStatus),
      ('version locale', '${v.version}'),
      ('createdAt', SyncDiagnosticsScreen.formatDate(v.createdAt)),
      ('updatedAt', SyncDiagnosticsScreen.formatDate(v.updatedAt)),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                  children: [
                    TextSpan(
                      text: '$label : ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: value, style: const TextStyle(fontFamily: 'monospace')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepTile(BuildContext context, DiagnosticStep step) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (step.status) {
      DiagnosticStepStatus.ok => (Icons.check_circle, Colors.green, 'OK'),
      DiagnosticStepStatus.failed => (Icons.cancel, scheme.error, 'ÉCHEC'),
      DiagnosticStepStatus.notRun => (Icons.remove_circle_outline, scheme.outline, 'NON EXÉCUTÉ'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${step.label} — $label', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (step.at != null)
                  Text(SyncDiagnosticsScreen.formatDate(step.at),
                      style: Theme.of(context).textTheme.bodySmall),
                if (step.detail != null)
                  Text(step.detail!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cloudResultCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_cloudError != null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text('Erreur lors de la vérification cloud : $_cloudError'),
      );
    }
    final present = _cloudRow != null;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: present ? Colors.green.withValues(alpha: 0.12) : scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            present
                ? 'PRÉSENT dans public.vehicles'
                : 'ABSENT de public.vehicles (SELECT par id vide)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (present) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final key in [
              'id',
              'user_id',
              'brand',
              'model',
              'current_mileage',
              'version',
              'created_at',
              'updated_at',
              'is_deleted',
            ])
              Text('$key : ${_cloudRow![key]}', style: const TextStyle(fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }
}
