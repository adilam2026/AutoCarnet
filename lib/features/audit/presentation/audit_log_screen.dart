import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/icon_chip.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/audit_repository.dart';

/// Technical trail of data-entry facts (vehicle created, fiche modifiée,
/// kilométrage corrigé...) - deliberately separate from the business
/// history the driver sees on each vehicle's dashboard. Read-only: audit
/// rows are system-generated and never edited or deleted by hand.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(allAuditEventsProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Journal d\'audit')),
      body: eventsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
        data: (events) {
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.fact_check_outlined,
              title: 'Aucune activité pour le moment',
              subtitle:
                  'Chaque création ou modification de fiche apparaîtra ici, '
                  'à titre de trace technique - distincte de l\'historique '
                  'métier de vos véhicules.',
            );
          }
          final vehicleNames = vehiclesAsync.maybeWhen(
            data: (vehicles) => {
              for (final v in vehicles) v.id: '${v.brand} ${v.model}',
            },
            orElse: () => <String, String>{},
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
            children: [
              ListSurface(
                children: [
                  for (final e in events) _buildRow(e, vehicleNames),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(AuditEvent e, Map<String, String> vehicleNames) {
    final vehicleName = e.vehicleId != null ? vehicleNames[e.vehicleId] : null;
    return ListTile(
      dense: true,
      leading: const IconChip(Icons.history_outlined),
      title: Text(e.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text([_fmt(e.occurredAt), ?vehicleName].join(' • ')),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day}/${d.month}/${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
