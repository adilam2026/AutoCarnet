import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../fuel/domain/fuel_types.dart';
import '../../data/vehicle_repository.dart';
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
  late final TextEditingController _vin;
  late final TextEditingController _plate;
  late final TextEditingController _motorization;
  late final TextEditingController _color;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _comments;
  String _brandValue = '';
  int? _year;
  String? _fuelType;
  String? _transmission;
  DateTime? _acquisitionDate;
  DatePrecision _regPrecision = DatePrecision.full;
  DateTime? _firstRegistrationDate;
  int? _firstRegYear;
  int? _firstRegMonth;
  VehicleCondition? _condition;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _brand = TextEditingController(text: v.brand);
    _model = TextEditingController(text: v.model);
    _trim = TextEditingController(text: v.trim ?? '');
    _vin = TextEditingController(text: v.vin ?? '');
    _plate = TextEditingController(text: v.plate ?? '');
    _motorization = TextEditingController(text: v.motorization ?? '');
    _color = TextEditingController(text: v.color ?? '');
    _purchasePrice =
        TextEditingController(text: v.purchasePrice?.toStringAsFixed(0) ?? '');
    _comments = TextEditingController(text: v.comments ?? '');
    _brandValue = v.brand;
    _year = v.year;
    _fuelType = fuelTypes.contains(v.fuelType) ? v.fuelType : null;
    _transmission =
        transmissionTypes.contains(v.transmission) ? v.transmission : null;
    _acquisitionDate = v.acquisitionDate;
    _firstRegistrationDate = v.firstRegistrationDate;
    _regPrecision = v.firstRegistrationDatePrecision ?? DatePrecision.full;
    if (_firstRegistrationDate != null) {
      _firstRegYear = _firstRegistrationDate!.year;
      _firstRegMonth = _firstRegistrationDate!.month;
    }
    _condition = v.condition;
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _trim.dispose();
    _vin.dispose();
    _plate.dispose();
    _motorization.dispose();
    _color.dispose();
    _purchasePrice.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _pickAcquisitionDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _acquisitionDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _acquisitionDate = picked);
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

  /// Never invents a day/month the owner didn't provide (bloc 3): a
  /// "mois et année" or "année seulement" precision anchors to the 1st so
  /// there's a concrete DateTime to compute age from, but callers must
  /// consult [_regPrecision] before trusting the day/month.
  DateTime? get _resolvedFirstRegistrationDate {
    switch (_regPrecision) {
      case DatePrecision.full:
        return _firstRegistrationDate;
      case DatePrecision.monthYear:
        return (_firstRegYear != null && _firstRegMonth != null)
            ? DateTime(_firstRegYear!, _firstRegMonth!, 1)
            : null;
      case DatePrecision.yearOnly:
        return _firstRegYear != null ? DateTime(_firstRegYear!, 1, 1) : null;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final resolvedRegDate = _resolvedFirstRegistrationDate;
      final updated = widget.vehicle.copyWith(
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        trim: Value(_trim.text.trim().isEmpty ? null : _trim.text.trim()),
        year: Value(_year),
        vin: Value(_vin.text.trim().isEmpty ? null : _vin.text.trim()),
        plate: Value(_plate.text.trim().isEmpty ? null : _plate.text.trim()),
        motorization: Value(_motorization.text.trim().isEmpty
            ? null
            : _motorization.text.trim()),
        fuelType: Value(_fuelType),
        transmission: Value(_transmission),
        color: Value(_color.text.trim().isEmpty ? null : _color.text.trim()),
        acquisitionDate: Value(_acquisitionDate),
        purchasePrice: Value(double.tryParse(_purchasePrice.text.trim())),
        firstRegistrationDate: Value(resolvedRegDate),
        firstRegistrationDatePrecision:
            Value(resolvedRegDate != null ? _regPrecision : null),
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
    final currentYear = DateTime.now().year;
    final years = [for (var y = currentYear + 1; y >= 1980; y--) y];

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
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<int>(
            initialValue: years.contains(_year) ? _year : null,
            decoration: const InputDecoration(labelText: 'Année'),
            hint: const Text('Sélectionner'),
            isExpanded: true,
            items: [
              for (final y in years)
                DropdownMenuItem(value: y, child: Text('$y')),
            ],
            onChanged: (v) => setState(() => _year = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Première mise en circulation'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Un véhicule immatriculé en janvier n\'a pas tout à fait le même '
            'âge qu\'un véhicule immatriculé en décembre de la même année : '
            'précisez la date si vous la connaissez.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('Date complète'),
                selected: _regPrecision == DatePrecision.full,
                onSelected: (_) => setState(() => _regPrecision = DatePrecision.full),
              ),
              ChoiceChip(
                label: const Text('Mois et année'),
                selected: _regPrecision == DatePrecision.monthYear,
                onSelected: (_) =>
                    setState(() => _regPrecision = DatePrecision.monthYear),
              ),
              ChoiceChip(
                label: const Text('Année seulement'),
                selected: _regPrecision == DatePrecision.yearOnly,
                onSelected: (_) => setState(() => _regPrecision = DatePrecision.yearOnly),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_regPrecision == DatePrecision.full)
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
            )
          else if (_regPrecision == DatePrecision.monthYear)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _firstRegMonth,
                    decoration: const InputDecoration(labelText: 'Mois'),
                    hint: const Text('Mois'),
                    isExpanded: true,
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_monthLabel(m))),
                    ],
                    onChanged: (v) => setState(() => _firstRegMonth = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: years.contains(_firstRegYear) ? _firstRegYear : null,
                    decoration: const InputDecoration(labelText: 'Année'),
                    hint: const Text('Année'),
                    isExpanded: true,
                    items: [
                      for (final y in years) DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (v) => setState(() => _firstRegYear = v),
                  ),
                ),
              ],
            )
          else
            DropdownButtonFormField<int>(
              initialValue: years.contains(_firstRegYear) ? _firstRegYear : null,
              decoration: const InputDecoration(labelText: 'Année'),
              hint: const Text('Sélectionner'),
              isExpanded: true,
              items: [
                for (final y in years) DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) => setState(() => _firstRegYear = v),
            ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Identification'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
              controller: _vin,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'VIN')),
          const SizedBox(height: AppSpacing.md),
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
          const SectionHeader('Acquisition'),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _pickAcquisitionDate,
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.md),
            ),
            child: Text(
              _acquisitionDate == null
                  ? 'Date d\'acquisition'
                  : 'Acquis le ${_fmt(_acquisitionDate!)}',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _purchasePrice,
            decoration: const InputDecoration(labelText: 'Prix d\'achat'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

  String _monthLabel(int m) => const [
        'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
        'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
      ][m - 1];

  String _conditionLabel(VehicleCondition c) => switch (c) {
        VehicleCondition.excellent => 'Excellent',
        VehicleCondition.veryGood => 'Très bon',
        VehicleCondition.good => 'Bon',
        VehicleCondition.average => 'Moyen',
        VehicleCondition.needsWork => 'À prévoir',
      };
}
