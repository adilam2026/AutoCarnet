import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/sharing_models.dart';
import '../data/sharing_repository.dart';
import '../domain/vehicle_permission.dart';

/// "Fiche véhicule → Partage et accès" - everyone who has access to this
/// vehicle (besides the owner), their permission level, when they were
/// added, and their last activity. Only the owner sees the modify/revoke
/// actions - a collaborator sees the same list read-only, so they know who
/// else is working on the vehicle.
class VehicleAccessScreen extends ConsumerStatefulWidget {
  const VehicleAccessScreen({
    super.key,
    required this.vehicleId,
    required this.vehicleLabel,
    required this.isOwner,
  });
  final String vehicleId;
  final String vehicleLabel;
  final bool isOwner;

  @override
  ConsumerState<VehicleAccessScreen> createState() => _VehicleAccessScreenState();
}

class _VehicleAccessScreenState extends ConsumerState<VehicleAccessScreen> {
  late Future<List<VehicleMember>> _members;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _members = ref.read(sharingRepositoryProvider).listMembers(widget.vehicleId));
  }

  Future<void> _changeRole(VehicleMember member) async {
    final newRole = await showModalBottomSheet<VehiclePermission>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in VehiclePermission.values)
              ListTile(
                leading: Icon(role == member.role ? Icons.check : null),
                title: Text(role.label),
                subtitle: Text(role.description),
                onTap: () => Navigator.of(sheetContext).pop(role),
              ),
          ],
        ),
      ),
    );
    if (newRole == null || newRole == member.role) return;
    await ref.read(sharingRepositoryProvider).updateMemberRole(member.id, newRole);
    if (mounted) {
      showAppSnackBar(context, 'Droits mis à jour pour ${member.displayLabel}.',
          icon: Icons.check_circle_outline);
    }
    _load();
  }

  Future<void> _revoke(VehicleMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Retirer cet accès ?'),
        content: Text(
          '${member.displayLabel} n\'aura plus accès à "${widget.vehicleLabel}". '
          'Ses contributions déjà enregistrées (entretiens, documents...) restent '
          'conservées dans l\'historique du véhicule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retirer l\'accès'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(sharingRepositoryProvider).revokeMember(member.id);
    if (mounted) {
      showAppSnackBar(context, 'Accès retiré pour ${member.displayLabel}.', icon: Icons.check);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partage et accès')),
      body: FutureBuilder<List<VehicleMember>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Impossible de charger la liste des accès. Vérifiez votre connexion.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(onPressed: _load, child: const Text('Réessayer')),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) return const LoadingView();
          final members = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(widget.vehicleLabel, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.isOwner
                    ? 'Vous êtes propriétaire de ce véhicule.'
                    : 'Personnes ayant accès à ce véhicule.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (members.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Personne d\'autre n\'a accès à ce véhicule pour l\'instant.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              else
                for (final member in members)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        child: Text(_initials(member.displayLabel)),
                      ),
                      title: Text(member.displayLabel),
                      subtitle: Text(
                        '${member.role.shortLabel} • ajouté le ${_fmt(member.addedAt)}'
                        '${member.lastActivityAt != null ? ' • actif le ${_fmt(member.lastActivityAt!)}' : ''}',
                      ),
                      trailing: widget.isOwner
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'role') _changeRole(member);
                                if (v == 'revoke') _revoke(member);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'role', child: Text('Modifier les droits')),
                                PopupMenuItem(value: 'revoke', child: Text('Retirer l\'accès')),
                              ],
                            )
                          : null,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  String _initials(String s) => s.trim().isEmpty ? '?' : s.trim()[0].toUpperCase();
  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
