import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/vehicle_card_color.dart';
import '../widgets/brand_model_fields.dart';
import '../widgets/card_color_picker.dart';

/// Principe 2 (saisie minimale): brand, model, current mileage and a card
/// colour are asked upfront - four fields, a few seconds. Finition,
/// motorisation, carburant, immatriculation, etc. (including the resale
/// valuation engine's finition input) all stay reachable from the fiche
/// complète and can be filled in later ("palette plus vive" pass, 2026:
/// finition removed from this quick-create screen on purpose, never from
/// the data model - see [Vehicle.finishLevel]).
class VehicleCreateScreen extends ConsumerStatefulWidget {
  const VehicleCreateScreen({super.key});

  @override
  ConsumerState<VehicleCreateScreen> createState() =>
      _VehicleCreateScreenState();
}

class _VehicleCreateScreenState extends ConsumerState<VehicleCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();
  String _brand = '';
  // Pre-filled from the same deterministic, least-used-first assignment
  // createVehicle would otherwise apply on its own (spec point 7: "ne pas
  // toujours attribuer le bleu pétrole par défaut") - this placeholder is
  // only ever shown for the instant before that lookup resolves.
  VehicleCardColor _cardColor = VehicleCardColor.bluePetrole;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadProposedColor();
  }

  Future<void> _loadProposedColor() async {
    final proposed = await ref.read(vehicleRepositoryProvider).nextCardColor();
    if (mounted) setState(() => _cardColor = proposed);
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _mileageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(vehicleRepositoryProvider).createVehicle(
            brand: _brandCtrl.text.trim(),
            model: _modelCtrl.text.trim(),
            currentMileage: double.parse(_mileageCtrl.text.trim()),
            cardColor: _cardColor,
          );
      if (!mounted) return;
      showAppSnackBar(context, 'Véhicule ajouté', icon: Icons.check_circle_outline);
      // pushReplacement (not go) so the shell stays underneath on the
      // navigation stack and the back button returns to "Mes véhicules".
      context.pushReplacement('/vehicles/$id');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau véhicule')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_filled,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Quatre informations suffisent pour commencer. Vous pourrez '
              'compléter la fiche plus tard.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            BrandField(
              controller: _brandCtrl,
              onChanged: (v) => setState(() => _brand = v),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            ModelField(
              controller: _modelCtrl,
              brand: _brand,
              onChanged: (_) => setState(() {}),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _mileageCtrl,
              decoration: const InputDecoration(
                labelText: 'Kilométrage actuel *',
                suffixText: 'km',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Champ requis';
                if (double.tryParse(v.trim()) == null) {
                  return 'Nombre invalide';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Couleur de la carte', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            CardColorPicker(
              selected: _cardColor,
              vehicleLabel: _brandCtrl.text.trim().isEmpty && _modelCtrl.text.trim().isEmpty
                  ? 'Votre véhicule'
                  : '${_brandCtrl.text.trim()} ${_modelCtrl.text.trim()}'.trim(),
              onChanged: (c) => setState(() => _cardColor = c),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
