import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/sync/conflict_repository.dart';
import '../../../core/sync/conflict_resolution_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/empty_state.dart';

const Map<String, String> _tableLabels = {
  'vehicles': 'Fiche véhicule',
  'maintenance_entries': 'Entretien',
  'expenses': 'Dépense',
  'fuel_entries': 'Plein de carburant',
  'documents': 'Document',
  'document_versions': 'Version de document',
  'reminders': 'Rappel',
  'operation_frequency_preferences': 'Fréquence d\'entretien',
};

// Internal/bookkeeping fields never worth showing in a diff - the owner
// cares about what actually changed, not ids or version counters.
const _hiddenFields = {
  'id',
  'vehicle_id',
  'document_id',
  'maintenance_entry_id',
  'version',
  'created_at',
  'created_by',
};

/// A version-mismatch push is never resolved automatically (see
/// occ_sync.dart/ConflictRepository) - this is where the owner actually
/// picks a winner. Reachable from the notification a conflict itself
/// generates, or from "Conflits de synchronisation" in the drawer.
class ConflictResolutionScreen extends ConsumerWidget {
  const ConflictResolutionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictsAsync = ref.watch(unresolvedConflictsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Conflits de synchronisation')),
      body: conflictsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('$e')),
        data: (conflicts) {
          if (conflicts.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Aucun conflit en attente',
              subtitle:
                  'Toutes les modifications simultanées ont déjà été résolues.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: conflicts.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _ConflictCard(conflict: conflicts[i]),
          );
        },
      ),
    );
  }
}

class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard({required this.conflict});
  final SyncConflict conflict;

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  bool _busy = false;

  Map<String, dynamic> get _local =>
      jsonDecode(widget.conflict.localSnapshotJson) as Map<String, dynamic>;
  Map<String, dynamic> get _remote =>
      jsonDecode(widget.conflict.remoteSnapshotJson) as Map<String, dynamic>;

  List<String> get _differingFields {
    final keys = {..._local.keys, ..._remote.keys}..removeAll(_hiddenFields);
    return keys.where((k) => _local[k] != _remote[k]).toList()..sort();
  }

  Future<void> _resolve(
    Future<void> Function(SyncConflict) action,
    String message,
  ) async {
    setState(() => _busy = true);
    await action(widget.conflict);
    if (mounted) {
      showAppSnackBar(context, message, icon: Icons.check_circle_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _tableLabels[widget.conflict.syncedTableName] ?? 'Donnée';
    final fields = _differingFields;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.sync_problem_outlined,
                    color: scheme.onErrorContainer,
                    size: 19,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Modifié à la fois sur cet appareil et par un autre collaborateur '
              '- choisissez la version à garder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Vous : ${_local[field] ?? '—'}',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Serveur : ${_remote[field] ?? '—'}',
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _resolve(
                            ref
                                .read(conflictResolutionServiceProvider)
                                .keepServerVersion,
                            'Version du serveur conservée',
                          ),
                    child: const Text('Garder celle du serveur'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _resolve(
                            ref
                                .read(conflictResolutionServiceProvider)
                                .keepLocalVersion,
                            'Votre version sera synchronisée',
                          ),
                    child: const Text('Garder la mienne'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
