import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/sharing_models.dart';
import '../data/sharing_repository.dart';
import '../domain/invite_code.dart';
import '../domain/vehicle_permission.dart';

/// The owner's "Partager le véhicule" screen: choose a permission level and
/// an expiry, generate a short code, then copy/share it - and manage
/// (cancel) codes already generated. Deliberately online-only: creating a
/// code is a coordination act with a real second account, not part of the
/// offline-first vehicle data itself.
class ShareVehicleScreen extends ConsumerStatefulWidget {
  const ShareVehicleScreen({super.key, required this.vehicleId, required this.vehicleLabel});
  final String vehicleId;
  final String vehicleLabel;

  @override
  ConsumerState<ShareVehicleScreen> createState() => _ShareVehicleScreenState();
}

class _ShareVehicleScreenState extends ConsumerState<ShareVehicleScreen> {
  VehiclePermission _role = VehiclePermission.viewer;
  InviteExpiry _expiry = InviteExpiry.sensibleDefault;
  bool _generating = false;
  VehicleInvite? _justCreated;
  late Future<List<VehicleInvite>> _activeInvites;

  @override
  void initState() {
    super.initState();
    _activeInvites = ref.read(sharingRepositoryProvider).listActiveInvites(widget.vehicleId);
  }

  void _refreshList() {
    setState(() => _activeInvites = ref.read(sharingRepositoryProvider).listActiveInvites(widget.vehicleId));
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final invite = await ref.read(sharingRepositoryProvider).createInvite(
            vehicleId: widget.vehicleId,
            role: _role,
            expiry: _expiry,
          );
      if (!mounted) return;
      setState(() {
        _justCreated = invite;
        _generating = false;
      });
      _refreshList();
    } catch (_) {
      if (!mounted) return;
      setState(() => _generating = false);
      showAppSnackBar(context, 'Impossible de générer le code. Vérifiez votre connexion.',
          icon: Icons.error_outline);
    }
  }

  Future<void> _cancel(VehicleInvite invite) async {
    await ref.read(sharingRepositoryProvider).cancelInvite(invite.id);
    if (_justCreated?.id == invite.id) setState(() => _justCreated = null);
    _refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partager le véhicule')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(widget.vehicleLabel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          if (_justCreated != null) ...[
            _GeneratedCodeCard(
              invite: _justCreated!,
              vehicleLabel: widget.vehicleLabel,
              onCancel: () => _cancel(_justCreated!),
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else ...[
            const Text('Niveau d\'accès', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            for (final role in VehiclePermission.values) ...[
              _RoleOption(
                role: role,
                selected: _role == role,
                onTap: () => setState(() => _role = role),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            const SizedBox(height: AppSpacing.md),
            const Text('Durée de validité du code', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<InviteExpiry>(
              segments: [
                for (final e in InviteExpiry.values) ButtonSegment(value: e, label: Text(e.label)),
              ],
              selected: {_expiry},
              onSelectionChanged: (s) => setState(() => _expiry = s.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_2_outlined),
                label: const Text('Générer un code d\'invitation'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Text('Codes actifs', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<VehicleInvite>>(
            future: _activeInvites,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LoadingView();
              final invites = snapshot.data!;
              if (invites.isEmpty) {
                return Text(
                  'Aucun code actif pour l\'instant.',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }
              return Column(
                children: [
                  for (final invite in invites)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          invite.role == VehiclePermission.editor
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                        ),
                        title: Text(invite.role.label),
                        subtitle: Text('Expire le ${_fmt(invite.expiresAt)}'),
                        trailing: TextButton(
                          onPressed: () => _cancel(invite),
                          child: const Text('Annuler'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year} à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.selected, required this.onTap});
  final VehiclePermission role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(role.description, style: Theme.of(context).textTheme.bodySmall),
                    if (role == VehiclePermission.editor) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Toujours réservé au propriétaire :',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      for (final action in ownerOnlyActionLabels)
                        Text('• $action', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneratedCodeCard extends StatelessWidget {
  const _GeneratedCodeCard({required this.invite, required this.vehicleLabel, required this.onCancel});
  final VehicleInvite invite;
  final String vehicleLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final code = invite.rawCode!;
    final displayCode = formatInviteCodeForDisplay(code);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Code d\'invitation généré',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              displayCode,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${invite.role.label} • expire le ${_fmt(invite.expiresAt)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: displayCode));
                      showAppSnackBar(context, 'Code copié', icon: Icons.check);
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copier'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        text: 'Rejoins "$vehicleLabel" sur AutoCarnet avec le code $displayCode '
                            '(valable jusqu\'au ${_fmt(invite.expiresAt)}).',
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Partager'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: onCancel,
              child: const Text('Annuler ce code'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year} à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
}
