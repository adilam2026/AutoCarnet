import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/widgets/section_header.dart';
import '../../data/vehicle_repository.dart';

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
  late final TextEditingController _year;
  late final TextEditingController _vin;
  late final TextEditingController _plate;
  late final TextEditingController _motorization;
  late final TextEditingController _fuelType;
  late final TextEditingController _transmission;
  late final TextEditingController _color;
  late final TextEditingController _comments;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _brand = TextEditingController(text: v.brand);
    _model = TextEditingController(text: v.model);
    _trim = TextEditingController(text: v.trim ?? '');
    _year = TextEditingController(text: v.year?.toString() ?? '');
    _vin = TextEditingController(text: v.vin ?? '');
    _plate = TextEditingController(text: v.plate ?? '');
    _motorization = TextEditingController(text: v.motorization ?? '');
    _fuelType = TextEditingController(text: v.fuelType ?? '');
    _transmission = TextEditingController(text: v.transmission ?? '');
    _color = TextEditingController(text: v.color ?? '');
    _comments = TextEditingController(text: v.comments ?? '');
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _trim.dispose();
    _year.dispose();
    _vin.dispose();
    _plate.dispose();
    _motorization.dispose();
    _fuelType.dispose();
    _transmission.dispose();
    _color.dispose();
    _comments.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = widget.vehicle.copyWith(
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        trim: Value(_trim.text.trim().isEmpty ? null : _trim.text.trim()),
        year: Value(int.tryParse(_year.text.trim())),
        vin: Value(_vin.text.trim().isEmpty ? null : _vin.text.trim()),
        plate: Value(_plate.text.trim().isEmpty ? null : _plate.text.trim()),
        motorization: Value(_motorization.text.trim().isEmpty
            ? null
            : _motorization.text.trim()),
        fuelType: Value(
            _fuelType.text.trim().isEmpty ? null : _fuelType.text.trim()),
        transmission: Value(_transmission.text.trim().isEmpty
            ? null
            : _transmission.text.trim()),
        color: Value(_color.text.trim().isEmpty ? null : _color.text.trim()),
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
          TextField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Marque')),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _model,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Modèle')),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _trim,
              decoration: const InputDecoration(labelText: 'Version / finition')),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _year,
            decoration: const InputDecoration(labelText: 'Année'),
            keyboardType: TextInputType.number,
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
          TextField(
              controller: _fuelType,
              decoration: const InputDecoration(labelText: 'Carburant')),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _transmission,
              decoration: const InputDecoration(labelText: 'Transmission')),
          const SizedBox(height: AppSpacing.md),
          TextField(
              controller: _color,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Couleur')),
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
}
