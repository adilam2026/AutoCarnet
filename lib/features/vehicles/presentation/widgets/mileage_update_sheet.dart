import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/utils/mileage_result.dart';
import '../../../../core/widgets/sheet_handle.dart';
import '../../data/vehicle_repository.dart';

/// Implements RG-VEH-005 / Situations A & B from the cahier des charges:
/// a lower mileage that doesn't conflict with history just needs
/// confirmation, one that does gets blocked with the conflicting entries
/// listed so the user can fix them first.
Future<void> showMileageUpdateSheet(
  BuildContext context,
  WidgetRef ref,
  Vehicle vehicle,
) {
  final controller = TextEditingController(
    text: vehicle.currentMileage.toStringAsFixed(0),
  );
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.sm,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
              sheetSystemBottomInset(sheetContext) +
              AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: _MileageUpdateForm(
            vehicle: vehicle,
            controller: controller,
            ref: ref,
          ),
        ),
      );
    },
  );
}

class _MileageUpdateForm extends StatefulWidget {
  const _MileageUpdateForm({
    required this.vehicle,
    required this.controller,
    required this.ref,
  });

  final Vehicle vehicle;
  final TextEditingController controller;
  final WidgetRef ref;

  @override
  State<_MileageUpdateForm> createState() => _MileageUpdateFormState();
}

class _MileageUpdateFormState extends State<_MileageUpdateForm> {
  String? _error;
  List<String>? _blockedConflicts;
  bool _needsConfirmation = false;
  bool _busy = false;

  Future<void> _onSubmit() async {
    final value = double.tryParse(widget.controller.text.trim());
    if (value == null) {
      setState(() => _error = 'Nombre invalide');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
      _blockedConflicts = null;
    });
    final repo = widget.ref.read(vehicleRepositoryProvider);
    final result = await repo.checkMileageChange(widget.vehicle.id, value);
    switch (result) {
      case MileageOk():
        await repo.recordManualMileage(widget.vehicle.id, value);
        if (mounted) {
          showAppSnackBar(context, 'Kilométrage mis à jour', icon: Icons.check_circle_outline);
          Navigator.of(context).pop();
        }
      case MileageNeedsConfirmation():
        setState(() {
          _needsConfirmation = true;
          _busy = false;
        });
      case MileageBlocked(:final conflictingDescriptions):
        setState(() {
          _blockedConflicts = conflictingDescriptions;
          _busy = false;
        });
    }
  }

  Future<void> _confirmAnyway() async {
    final value = double.parse(widget.controller.text.trim());
    setState(() => _busy = true);
    await widget.ref
        .read(vehicleRepositoryProvider)
        .recordManualMileage(widget.vehicle.id, value);
    if (mounted) {
      showAppSnackBar(context, 'Kilométrage mis à jour', icon: Icons.check_circle_outline);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHandle(),
        Text('Mettre à jour le kilométrage',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: widget.controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          decoration: InputDecoration(
            labelText: 'Nouveau kilométrage',
            suffixText: 'km',
            errorText: _error,
          ),
          onChanged: (_) => setState(() {
            _needsConfirmation = false;
            _blockedConflicts = null;
          }),
        ),
        if (_needsConfirmation) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Cette valeur est inférieure au kilométrage actuel. Aucune '
              'opération enregistrée n\'est concernée : vous pouvez confirmer.',
            ),
          ),
        ],
        if (_blockedConflicts != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Impossible d\'enregistrer : des opérations existent à un '
                  'kilométrage supérieur.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final c in _blockedConflicts!) Text('• $c'),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (_needsConfirmation)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _confirmAnyway,
                  child: const Text('Confirmer'),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy || _blockedConflicts != null ? null : _onSubmit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
          ),
      ],
    );
  }
}
