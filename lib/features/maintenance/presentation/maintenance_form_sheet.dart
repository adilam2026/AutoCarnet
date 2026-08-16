import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../providers/data/provider_repository.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/maintenance_repository.dart';
import '../domain/maintenance_categories.dart';

/// Used both to create a new operation and to open/edit/duplicate an
/// existing one - the same form serves as the "detail" view (Principe: a
/// created record must stay consultable and modifiable).
Future<void> showMaintenanceFormSheet(
  BuildContext context, {
  required String vehicleId,
  required double currentMileage,
  MaintenanceEntry? editing,
  MaintenanceEntry? duplicateFrom,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MaintenanceFormSheet(
      vehicleId: vehicleId,
      currentMileage: currentMileage,
      editing: editing,
      duplicateFrom: duplicateFrom,
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
    this.editing,
    this.duplicateFrom,
  });
  final String vehicleId;
  final double currentMileage;
  final MaintenanceEntry? editing;
  final MaintenanceEntry? duplicateFrom;

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
  String? _initialProviderName;
  final List<_PartRow> _parts = [];
  bool _createExpense = true;
  bool _saving = false;
  bool _deleting = false;
  bool _ready = false;
  DateTime? _nextDueDate;
  final _nextDueMileageCtrl = TextEditingController();

  MaintenanceEntry? get _source => widget.editing ?? widget.duplicateFrom;
  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
    _init();
  }

  Future<void> _init() async {
    final source = _source;
    if (source == null) {
      setState(() => _ready = true);
      return;
    }
    _category = source.category;
    _date = _isEditing ? source.date : DateTime.now();
    _mileageCtrl.text = source.mileage.toStringAsFixed(0);
    _laborCtrl.text = source.laborCost.toStringAsFixed(2);
    _commentsCtrl.text = source.comments ?? '';
    _createExpense = source.linkedExpenseId != null;
    _nextDueDate = source.nextDueDate;
    _nextDueMileageCtrl.text = source.nextDueMileage?.toStringAsFixed(0) ?? '';

    if (source.providerId != null) {
      final provider =
          await ref.read(providerRepositoryProvider).getById(source.providerId!);
      _selectedProvider = provider;
      _initialProviderName = provider?.name;
    }

    if (_isEditing) {
      final existingParts =
          await ref.read(maintenanceRepositoryProvider).watchParts(source.id).first;
      for (final p in existingParts) {
        final row = _PartRow();
        row.designationCtrl.text = p.designation;
        row.quantityCtrl.text = p.quantity.toStringAsFixed(
            p.quantity == p.quantity.roundToDouble() ? 0 : 2);
        row.unitPriceCtrl.text = p.unitPrice.toStringAsFixed(2);
        _parts.add(row);
      }
    }

    if (mounted) setState(() => _ready = true);
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
      final nextDueMileage = double.tryParse(_nextDueMileageCtrl.text.trim());
      final repo = ref.read(maintenanceRepositoryProvider);
      if (_isEditing) {
        await repo.updateEntry(
          id: widget.editing!.id,
          vehicleId: widget.vehicleId,
          category: _category,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: double.parse(_mileageCtrl.text.trim()),
          providerId: providerId,
          laborCost: double.tryParse(_laborCtrl.text) ?? 0,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
          nextDueDate: _nextDueDate,
          nextDueMileage: nextDueMileage,
          parts: parts,
          createLinkedExpense: _createExpense,
        );
      } else {
        await repo.createEntry(
          vehicleId: widget.vehicleId,
          category: _category,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: double.parse(_mileageCtrl.text.trim()),
          providerId: providerId,
          laborCost: double.tryParse(_laborCtrl.text) ?? 0,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
          nextDueDate: _nextDueDate,
          nextDueMileage: nextDueMileage,
          parts: parts,
          createLinkedExpense: _createExpense,
        );
      }
      if (mounted) {
        showAppSnackBar(
          context,
          _isEditing ? 'Entretien modifié' : 'Entretien enregistré',
          icon: Icons.check_circle_outline,
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cet entretien ?'),
        content: Text(
            '« $_category » du ${_fmt(_date)} sera déplacé dans la corbeille.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    await ref.read(maintenanceRepositoryProvider).softDelete(widget.editing!.id);
    if (mounted) {
      showAppSnackBar(context, 'Entretien supprimé', icon: Icons.delete_outline);
      Navigator.of(context).pop();
    }
  }

  void _duplicate() {
    final source = widget.editing;
    if (source == null) return;
    Navigator.of(context).pop();
    showMaintenanceFormSheet(
      context,
      vehicleId: widget.vehicleId,
      currentMileage: widget.currentMileage,
      duplicateFrom: source,
    );
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
      child: !_ready
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const SheetHandle(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEditing ? 'Modifier l\'entretien' : 'Nouvel entretien',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (_isEditing) ...[
                        IconButton(
                          tooltip: 'Dupliquer',
                          icon: const Icon(Icons.copy_outlined),
                          onPressed: _saving || _deleting ? null : _duplicate,
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _saving || _deleting ? null : _delete,
                        ),
                      ],
                    ],
                  ),
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
                    initialName: _initialProviderName,
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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _commentsCtrl,
                    decoration: const InputDecoration(labelText: 'Commentaires'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Prochaine échéance',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _nextDueMileageCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Kilométrage', suffixText: 'km'),
                          keyboardType: const TextInputType.numberWithOptions(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _nextDueDate ?? _date,
                              firstDate: DateTime(1990),
                              lastDate: DateTime(2100),
                            );
                            setState(() => _nextDueDate = picked);
                          },
                          child: Text(
                            _nextDueDate == null
                                ? 'Date'
                                : _fmt(_nextDueDate!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
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
                    onPressed: (_saving || _deleting) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEditing ? 'Enregistrer les modifications' : 'Enregistrer'),
                  ),
                ],
              ),
            ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
