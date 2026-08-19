import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/vehicle_sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/sharing_models.dart';
import '../data/sharing_repository.dart';

/// "Rejoindre un véhicule" - deliberately its own screen, never confused
/// with "Ajouter mon véhicule": entering a code always previews what it
/// grants (vehicle, owner, permission level) before anything is accepted,
/// and can never create a duplicate/new vehicle - it only ever attaches
/// this account to an existing one.
class JoinVehicleScreen extends ConsumerStatefulWidget {
  const JoinVehicleScreen({super.key});

  @override
  ConsumerState<JoinVehicleScreen> createState() => _JoinVehicleScreenState();
}

enum _Step { enterCode, preview }

class _JoinVehicleScreenState extends ConsumerState<JoinVehicleScreen> {
  final _codeCtrl = TextEditingController();
  _Step _step = _Step.enterCode;
  bool _loading = false;
  String? _error;
  InvitePreview? _preview;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final input = _codeCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await ref.read(sharingRepositoryProvider).previewInvite(input);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _step = _Step.preview;
        _loading = false;
      });
    } on InviteRedeemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Une erreur est survenue. Réessayez.';
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invite = await ref.read(sharingRepositoryProvider).acceptInvite(_codeCtrl.text.trim());
      // The vehicle only exists on the cloud from this device's point of
      // view right now - pulling it down before navigating avoids
      // VehicleHomeScreen's watchOne() finding zero local rows and
      // crashing. Best-effort: if sync doesn't complete in time (e.g. a
      // slow connection), land on the vehicles list instead, where it'll
      // simply appear once the next sync pass picks it up.
      await ref.read(vehicleSyncServiceProvider).syncNow();
      if (!mounted) return;
      final vehicleRepo = ref.read(vehicleRepositoryProvider);
      final arrived = await vehicleRepo.existsLocally(invite.vehicleId);
      if (!mounted) return;
      showAppSnackBar(context, 'Vous avez rejoint le véhicule.', icon: Icons.check_circle_outline);
      if (arrived) {
        context.go('/vehicles/${invite.vehicleId}');
      } else {
        context.go('/');
      }
    } on InviteRedeemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _step = _Step.enterCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Une erreur est survenue. Réessayez.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre un véhicule')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _step == _Step.enterCode ? _buildEnterCode(context) : _buildPreview(context),
      ),
    );
  }

  Widget _buildEnterCode(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Saisissez le code que vous a envoyé le propriétaire du véhicule.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 2),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: InputDecoration(
            hintText: 'Q7K9-M2P4',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
          onSubmitted: (_) => _loadPreview(),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _loading ? null : _loadPreview,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continuer'),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final preview = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${preview.brand} ${preview.model}', style: Theme.of(context).textTheme.titleLarge),
                if (preview.plate != null) ...[
                  const SizedBox(height: 2),
                  Text(preview.plate!, style: Theme.of(context).textTheme.bodyMedium),
                ],
                const Divider(height: AppSpacing.lg),
                _row(context, Icons.person_outline, 'Propriétaire', preview.ownerDisplayName),
                const SizedBox(height: AppSpacing.sm),
                _row(context, Icons.shield_outlined, 'Accès proposé', preview.role.label),
                const SizedBox(height: AppSpacing.sm),
                _row(context, Icons.timer_outlined, 'Code valable jusqu\'au', _fmt(preview.expiresAt)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        FilledButton(
          onPressed: _loading ? null : _accept,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Rejoindre ce véhicule'),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: _loading ? null : () => setState(() => _step = _Step.enterCode),
          child: const Text('Annuler'),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
