import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/fuel_repository.dart';
import '../domain/fuel_types.dart';

Future<void> showFuelFormSheet(
  BuildContext context, {
  required String vehicleId,
  required double currentMileage,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FuelFormSheet(
      vehicleId: vehicleId,
      currentMileage: currentMileage,
    ),
  );
}

class _FuelFormSheet extends ConsumerStatefulWidget {
  const _FuelFormSheet({required this.vehicleId, required this.currentMileage});
  final String vehicleId;
  final double currentMileage;

  @override
  ConsumerState<_FuelFormSheet> createState() => _FuelFormSheetState();
}

class _FuelFormSheetState extends ConsumerState<_FuelFormSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _mileageCtrl = TextEditingController();
  String _fuelType = fuelTypes.first;
  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _isFullTank = true;
  ServiceProvider? _selectedProvider;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
  }

  double get _total {
    final q = double.tryParse(_quantityCtrl.text) ?? 0;
    final p = double.tryParse(_priceCtrl.text) ?? 0;
    return q * p;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final providerId = await resolveOrCreateProvider(
        ref,
        selected: _selectedProvider,
        typedText: '',
      );
      await ref.read(fuelRepositoryProvider).createEntry(
            vehicleId: widget.vehicleId,
            date: _date,
            currency: ref.read(defaultCurrencyProvider),
            mileage: double.parse(_mileageCtrl.text.trim()),
            fuelType: _fuelType,
            quantityLiters: double.parse(_quantityCtrl.text.trim()),
            pricePerLiter: double.parse(_priceCtrl.text.trim()),
            providerId: providerId,
            isFullTank: _isFullTank,
          );
      if (mounted) {
        showAppSnackBar(context, 'Plein enregistré', icon: Icons.check_circle_outline);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            sheetSystemBottomInset(context) +
            AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            const SheetHandle(),
            Text('Nouveau plein', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    child: Text('Date : ${_fmt(_date)}'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _mileageCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Kilométrage *', suffixText: 'km'),
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Requis'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _fuelType,
              decoration: const InputDecoration(labelText: 'Carburant'),
              items: fuelTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _fuelType = v!),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Quantité *', suffixText: 'L'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Requis'
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Prix / L *'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Requis'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Total : ${_total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            ProviderPickerField(
              label: 'Station-service',
              onSelected: (p) => _selectedProvider = p,
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Plein complet'),
              value: _isFullTank,
              onChanged: (v) => setState(() => _isFullTank = v),
            ),
            const SizedBox(height: AppSpacing.md),
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

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
