import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/maintenance_repository.dart';
import '../domain/maintenance_categories.dart';

Future<void> showMaintenanceFormSheet(
  BuildContext context, {
  required String vehicleId,
  required double currentMileage,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MaintenanceFormSheet(
      vehicleId: vehicleId,
      currentMileage: currentMileage,
    ),
  );
}

class _PartRow {
  final designationCtrl = TextEditingController();
  final quantityCtrl = TextEditingController(text: '1');
  final unitPriceCtrl = TextEditingController(text: '0');
}

class _MaintenanceFormSheet extends ConsumerStatefulWidget {
  const _MaintenanceFormSheet({
    required this.vehicleId,
    required this.currentMileage,
  });
  final String vehicleId;
  final double currentMileage;

  @override
  ConsumerState<_MaintenanceFormSheet> createState() =>
      _MaintenanceFormSheetState();
}

class _MaintenanceFormSheetState extends ConsumerState<_MaintenanceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  String _category = maintenanceCategories.first;
  DateTime _date = DateTime.now();
  final _mileageCtrl = TextEditingController();
  final _laborCtrl = TextEditingController(text: '0');
  final _commentsCtrl = TextEditingController();
  ServiceProvider? _selectedProvider;
  final List<_PartRow> _parts = [];
  bool _createExpense = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
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
      final parts = _parts
          .where((p) => p.designationCtrl.text.trim().isNotEmpty)
          .map((p) => NewMaintenancePart(
                designation: p.designationCtrl.text.trim(),
                quantity: double.tryParse(p.quantityCtrl.text) ?? 1,
                unitPrice: double.tryParse(p.unitPriceCtrl.text) ?? 0,
              ))
          .toList();
      await ref.read(maintenanceRepositoryProvider).createEntry(
            vehicleId: widget.vehicleId,
            category: _category,
            date: _date,
            mileage: double.parse(_mileageCtrl.text.trim()),
            providerId: providerId,
            laborCost: double.tryParse(_laborCtrl.text) ?? 0,
            comments: _commentsCtrl.text.trim().isEmpty
                ? null
                : _commentsCtrl.text.trim(),
            parts: parts,
            createLinkedExpense: _createExpense,
          );
      if (mounted) Navigator.of(context).pop();
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
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Nouvel entretien',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Catégorie *'),
              items: maintenanceCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
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
                    keyboardType: const TextInputType.numberWithOptions(),
                    validator: (v) => (v == null || double.tryParse(v) == null)
                        ? 'Requis'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ProviderPickerField(
              onSelected: (p) => _selectedProvider = p,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Pièces remplacées',
                    style: Theme.of(context).textTheme.titleSmall),
                TextButton.icon(
                  onPressed: () => setState(() => _parts.add(_PartRow())),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
            for (final part in _parts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: part.designationCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Désignation'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: part.quantityCtrl,
                        decoration: const InputDecoration(labelText: 'Qté'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: part.unitPriceCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Prix unit.'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _parts.remove(part)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _laborCtrl,
              decoration:
                  const InputDecoration(labelText: 'Main-d\'œuvre'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _commentsCtrl,
              decoration: const InputDecoration(labelText: 'Commentaires'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Créer automatiquement une dépense liée'),
              value: _createExpense,
              onChanged: (v) => setState(() => _createExpense = v),
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
