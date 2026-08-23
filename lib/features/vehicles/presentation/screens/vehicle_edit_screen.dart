import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../fuel/domain/fuel_types.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/vehicle_card_color.dart';
import '../../domain/vehicle_reference_data.dart';
import '../widgets/brand_model_fields.dart';

/// Every field beyond the 3 required at creation lives here - the fiche is
/// completed progressively, never all at once (Principe 2).
class VehicleEditScreen extends ConsumerStatefulWidget {
  const VehicleEditScreen({super.key, required this.vehicle});
  final Vehicle vehicle;

  @override
  ConsumerState<VehicleEditScreen> createState() => _VehicleEditScreenState();
}

class _VehicleEditScreenState extends ConsumerState<VehicleEditScreen> {
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _trim;
  late final TextEditingController _plate;
  late final TextEditingController _motorization;
  late final TextEditingController _color;
  late final TextEditingController _comments;
  String _brandValue = '';
  String? _fuelType;
  String? _transmission;
  DateTime? _firstRegistrationDate;
  VehicleCondition? _condition;
  late VehicleCardColor _cardColor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _brand = TextEditingController(text: v.brand);
    _model = TextEditingController(text: v.model);
    _trim = TextEditingController(text: v.trim ?? '');
    _plate = TextEditingController(text: v.plate ?? '');
    _motorization = TextEditingController(text: v.motorization ?? '');
    _color = TextEditingController(text: v.color ?? '');
    _comments = TextEditingController(text: v.comments ?? '');
    _brandValue = v.brand;
    _fuelType = fuelTypes.contains(v.fuelType) ? v.fuelType : null;
    _transmission =
        transmissionTypes.contains(v.transmission) ? v.transmission : null;
    _firstRegistrationDate = v.firstRegistrationDate;
    _condition = v.condition;
    _cardColor = VehicleCardColor.fromKey(v.cardColorKey);
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _trim.dispose();
    _plate.dispose();
    _motorization.dispose();
    _color.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _pickFirstRegistrationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstRegistrationDate ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _firstRegistrationDate = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.vehicle.copyWith(
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        trim: Value(_trim.text.trim().isEmpty ? null : _trim.text.trim()),
        // Année unique source de vérité : dérivée de la date de première
        // mise en circulation, jamais saisie séparément (bloc 23).
        year: Value(_firstRegistrationDate?.year ?? widget.vehicle.year),
        plate: Value(_plate.text.trim().isEmpty ? null : _plate.text.trim()),
        motorization: Value(_motorization.text.trim().isEmpty
            ? null
            : _motorization.text.trim()),
        fuelType: Value(_fuelType),
        transmission: Value(_transmission),
        color: Value(_color.text.trim().isEmpty ? null : _color.text.trim()),
        cardColorKey: Value(_cardColor.storageKey),
        firstRegistrationDate: Value(_firstRegistrationDate),
        firstRegistrationDatePrecision: const Value(null),
        condition: Value(_condition),
        comments: Value(
            _comments.text.trim().isEmpty ? null : _comments.text.trim()),
      );
      await ref.read(vehicleRepositoryProvider).updateVehicle(updated);
      if (mounted) {
        showAppSnackBar(context, 'Fiche mise à jour', icon: Icons.check_circle_outline);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier la fiche'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SectionHeader('Identité'),
          const SizedBox(height: AppSpacing.sm),
          BrandField(
            controller: _brand,
            onChanged: (v) => setState(() => _brandValue = v),
          ),
          const SizedBox(height: AppSpacing.md),
          ModelField(controller: _model, brand: _brandValue, onChanged: (_) {}),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _trim,
              decoration: const InputDecoration(labelText: 'Version / finition')),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Couleur de la carte'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'La couleur qui identifie ce véhicule sur l\'accueil - sans lien '
            'avec sa couleur de carrosserie.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          _CardColorPicker(
            selected: _cardColor,
            vehicleLabel: '${_brand.text.trim().isEmpty ? widget.vehicle.brand : _brand.text.trim()} '
                '${_model.text.trim().isEmpty ? widget.vehicle.model : _model.text.trim()}',
            onChanged: (c) => setState(() => _cardColor = c),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Première mise en circulation'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Source unique de vérité : l\'année du véhicule est calculée '
            'automatiquement à partir de cette date.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _pickFirstRegistrationDate,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
            ),
            child: Text(
              _firstRegistrationDate == null
                  ? 'Date de première mise en circulation'
                  : 'Mise en circulation le ${_fmt(_firstRegistrationDate!)}',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Identification'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
              controller: _plate,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Immatriculation')),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Caractéristiques'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
              controller: _motorization,
              decoration: const InputDecoration(labelText: 'Motorisation')),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _fuelType,
            decoration: const InputDecoration(labelText: 'Carburant'),
            hint: const Text('Sélectionner'),
            isExpanded: true,
            items: [
              for (final f in fuelTypes) DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) => setState(() => _fuelType = v),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _transmission,
            decoration: const InputDecoration(labelText: 'Boîte de vitesses'),
            hint: const Text('Sélectionner'),
            isExpanded: true,
            items: [
              for (final t in transmissionTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _transmission = v),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _color,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Couleur')),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<VehicleCondition>(
            initialValue: _condition,
            decoration: const InputDecoration(labelText: 'État général'),
            hint: const Text('Sélectionner'),
            isExpanded: true,
            items: [
              for (final c in VehicleCondition.values)
                DropdownMenuItem(value: c, child: Text(_conditionLabel(c))),
            ],
            onChanged: (v) => setState(() => _condition = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Notes'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _comments,
            decoration: const InputDecoration(labelText: 'Commentaires'),
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String _conditionLabel(VehicleCondition c) => switch (c) {
        VehicleCondition.excellent => 'Excellent',
        VehicleCondition.veryGood => 'Très bon',
        VehicleCondition.good => 'Bon',
        VehicleCondition.average => 'Moyen',
        VehicleCondition.needsWork => 'À prévoir',
      };
}

/// A small, self-contained "couleur de la carte" picker (bloc 9/11): a live
/// preview of the identity band in the currently-selected colour, then the
/// AutoCarnet palette as tappable pastilles - deliberately not a full
/// configurator, just enough to answer "à quoi ressemblera ma carte ?".
class _CardColorPicker extends StatelessWidget {
  const _CardColorPicker({
    required this.selected,
    required this.vehicleLabel,
    required this.onChanged,
  });

  final VehicleCardColor selected;
  final String vehicleLabel;
  final ValueChanged<VehicleCardColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: AppMotion.fast,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected.color,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.directions_car_filled, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  vehicleLabel,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in VehicleCardColor.values)
              _ColorSwatch(
                color: c,
                selected: c == selected,
                onTap: () => onChanged(c),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          selected.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  final VehicleCardColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: color.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
                : null,
          ),
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.color),
            child: selected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
