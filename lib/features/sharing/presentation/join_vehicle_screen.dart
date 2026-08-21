import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/sync/vehicle_sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/sharing_models.dart';
import '../data/sharing_repository.dart';

/// "Rejoindre un véhicule" - deliberately its own screen, never confused
/// with "Ajouter mon véhicule": entering a code always previews what it
/// grants (vehicle, owner, permission level) before anything is accepted,
/// and can never create a duplicate/new vehicle - it only ever attaches
/// this account to an existing one.
///
/// Four genuinely separate actions, never blurred together (a real bug
/// found on device): open this screen (no lookup at all), type a code
/// (still no lookup), validate it (read-only preview via
/// [SharingRepository.previewInvite]), confirm joining (the only call that
/// actually mutates anything, via [SharingRepository.acceptInvite]).
class JoinVehicleScreen extends ConsumerStatefulWidget {
  const JoinVehicleScreen({super.key});

  @override
  ConsumerState<JoinVehicleScreen> createState() => _JoinVehicleScreenState();
}

enum _Step { enterCode, preview, success }

class _JoinVehicleScreenState extends ConsumerState<JoinVehicleScreen> {
  final _codeCtrl = TextEditingController();
  _Step _step = _Step.enterCode;
  bool _loading = false;
  String? _error;
  InvitePreview? _preview;
  String? _joinedVehicleId;
  String? _joinedVehicleLabel;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (_loading) return;
    final input = _codeCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Veuillez saisir un code de partage.');
      return;
    }
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
    } catch (e) {
      debugPrint('JoinVehicleScreen.previewInvite failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Une erreur est survenue. Réessayez.';
        _loading = false;
      });
    }
  }

  /// Confirms the actual adhésion - the only call in this whole screen that
  /// mutates anything server-side. On failure this deliberately stays on
  /// the preview step (never silently bounces back to code entry, and
  /// never leaves the joiner wondering whether it worked): the vehicle
  /// card and a clear error stay visible so "Rejoindre" can be retried, or
  /// "Annuler" explicitly re-typed.
  Future<void> _accept() async {
    if (_loading) return;
    final preview = _preview!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invite = await ref.read(sharingRepositoryProvider).acceptInvite(_codeCtrl.text.trim());
      // Kick off a sync right away (don't block reaching the success
      // screen on it) so "Mes véhicules" has the best chance of already
      // reflecting the new vehicle by the time the user gets back there.
      unawaited(ref.read(vehicleSyncServiceProvider).syncNow());
      if (!mounted) return;
      setState(() {
        _joinedVehicleId = invite.vehicleId;
        _joinedVehicleLabel = '${preview.brand} ${preview.model}';
        _step = _Step.success;
        _loading = false;
      });
    } on InviteRedeemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      debugPrint('JoinVehicleScreen.acceptInvite failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Impossible d\'ajouter ce véhicule. Réessayez.';
        _loading = false;
      });
    }
  }

  /// Navigates into a vehicle the account just gained access to, without
  /// ever risking VehicleHomeScreen's `.when` hitting an error state:
  /// nudges a sync first since the vehicle exists on the cloud but hasn't
  /// necessarily reached this device's local mirror yet. Best-effort: if
  /// sync doesn't complete in time (e.g. a slow connection),
  /// VehicleHomeScreen's own "Synchronisation en cours" view (see
  /// vehicle_home_screen.dart) takes over from there rather than crashing.
  Future<void> _openVehicle(String vehicleId) async {
    try {
      await ref.read(vehicleSyncServiceProvider).syncNow();
    } catch (_) {
      // Offline/transient - proceed anyway, VehicleHomeScreen handles it.
    }
    if (!mounted) return;
    context.go('/vehicles/$vehicleId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre un véhicule')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: switch (_step) {
          _Step.enterCode => _buildEnterCode(context),
          _Step.preview => _buildPreview(context),
          _Step.success => _buildSuccess(context),
        },
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
          // Deliberately opts this field out of the Android/keyboard
          // autofill and predictive-suggestion machinery: a real bug
          // found on device had a previously-typed code get silently
          // re-suggested/reinserted into this field by the system
          // keyboard, which is exactly what these three settings (plus
          // `visiblePassword`, which also drops the suggestion bar) exist
          // to prevent for a one-off, never-remembered code field.
          autofillHints: const [],
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
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
    final alreadyHasAccess = preview.alreadyOwner || preview.alreadyMember;
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
                if (!alreadyHasAccess) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _row(context, Icons.timer_outlined, 'Code valable jusqu\'au', _fmt(preview.expiresAt)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (preview.alreadyOwner) ...[
          Text(
            'Vous êtes déjà propriétaire de ce véhicule.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _loading ? null : () => _openVehicle(preview.vehicleId),
            child: const Text('Ouvrir le véhicule'),
          ),
        ] else if (preview.alreadyMember) ...[
          Text(
            'Vous avez déjà accès à ce véhicule.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: _loading ? null : () => _openVehicle(preview.vehicleId),
            child: const Text('Ouvrir le véhicule'),
          ),
        ] else
          FilledButton(
            onPressed: _loading ? null : _accept,
            child: _loading
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Rejoindre ce véhicule'),
          ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _step = _Step.enterCode;
                    _error = null;
                    _codeCtrl.clear();
                  }),
          child: const Text('Annuler'),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Véhicule ajouté', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${_joinedVehicleLabel ?? 'Ce véhicule'} est maintenant disponible dans vos véhicules.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => _openVehicle(_joinedVehicleId!),
            child: const Text('Ouvrir le véhicule'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Retour à mes véhicules'),
          ),
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
