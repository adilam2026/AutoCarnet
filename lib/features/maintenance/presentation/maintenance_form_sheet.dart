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
import '../data/operation_frequency_repository.dart';
import '../domain/maintenance_categories.dart';
import '../domain/operation_recurrence_rules.dart';

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

  ResolvedFrequency? _resolvedFrequency;
  bool _applyingSuggestion = false;
  bool _nextDueMileageUserEdited = false;
  bool _nextDueDateUserEdited = false;

  MaintenanceEntry? get _source => widget.editing ?? widget.duplicateFrom;
  bool get _isEditing => widget.editing != null;
  bool get _isNewEntry => _source == null;

  String get _nextDueLabel {
    final lower = _category.toLowerCase();
    if (lower.contains('vidange')) return 'Prochaine vidange';
    if (lower.contains('révision')) return 'Prochaine révision';
    if (lower.contains('pneu')) return 'Prochain contrôle pneus';
    if (lower.contains('frein') ||
        lower.contains('plaquette') ||
        lower.contains('disque')) {
      return 'Prochain contrôle freinage';
    }
    return 'Prochaine échéance';
  }

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
    _nextDueMileageCtrl.addListener(() {
      if (!_applyingSuggestion) _nextDueMileageUserEdited = true;
    });
    _init();
  }

  Future<void> _init() async {
    final source = _source;
    if (source == null) {
      await _loadFrequencyAndSuggest();
      if (mounted) setState(() => _ready = true);
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

    // The source already carries its own next-due values (or intentionally
    // none). Whether editing may keep recalculating them in place depends on
    // where they came from: a plain "mileage + frequency" formula result may
    // keep auto-following the mileage field as it's corrected (TEST C - bloc
    // 23), but a value the owner deliberately customized must never be
    // silently overwritten. createdAt/insertion order play no role in this
    // decision, only the operation's own mileage/date and the frequency rule
    // currently in force.
    final override = await ref
        .read(operationFrequencyRepositoryProvider)
        .getFor(widget.vehicleId, _category);
    final resolved = resolveFrequency(
      category: _category,
      vehicleFrequencyKm: override?.frequencyKm,
      vehicleFrequencyMonths: override?.frequencyMonths,
    );
    _resolvedFrequency = resolved;

    final formulaDerivedMileage = resolved.frequencyKm != null &&
        source.nextDueMileage != null &&
        (source.nextDueMileage! - (source.mileage + resolved.frequencyKm!))
                .abs() <
            0.5;
    _nextDueMileageUserEdited = !formulaDerivedMileage;

    final formulaDerivedDate = resolved.frequencyMonths != null &&
        source.nextDueDate != null &&
        source.nextDueDate!.isAtSameMomentAs(DateTime(
            _date.year, _date.month + resolved.frequencyMonths!, _date.day));
    _nextDueDateUserEdited = !formulaDerivedDate;

    if (source.providerId != null) {
      final provider =
          await ref.read(providerRepositoryProvider).getById(source.providerId!);
      _selectedProvider = provider;
      _initialProviderName = provider?.name;
    }

    // Both editing and duplicating start from the source's existing parts -
    // duplicating an operation means "this happened again", not "this
    // happened again but I have to retype every part".
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

    if (mounted) setState(() => _ready = true);
  }

  /// Loads the resolved frequency for the current category (vehicle-
  /// specific override or AutoCarnet default) and, only for a brand-new
  /// entry, applies it as the next-due suggestion (bloc 2.1/2.2) - a
  /// vidange or révision periodic category gets a default +10 000 km,
  /// anything else stays empty. When editing, [_applySuggestion] still
  /// refreshes [_resolvedFrequency] so the "Modifier"/recompute affordance
  /// stays available (bloc 23: an edited operation's next-due échéance
  /// must be able to stay coherent with the rule in force) without ever
  /// silently overwriting the operation's own saved value.
  Future<void> _loadFrequencyAndSuggest() async {
    final override =
        await ref.read(operationFrequencyRepositoryProvider).getFor(widget.vehicleId, _category);
    _applySuggestion(
      vehicleFrequencyKm: override?.frequencyKm,
      vehicleFrequencyMonths: override?.frequencyMonths,
    );
  }

  void _applySuggestion({double? vehicleFrequencyKm, int? vehicleFrequencyMonths}) {
    final resolved = resolveFrequency(
      category: _category,
      vehicleFrequencyKm: vehicleFrequencyKm,
      vehicleFrequencyMonths: vehicleFrequencyMonths,
    );
    _resolvedFrequency = resolved;
    if (!_nextDueMileageUserEdited) {
      _applyingSuggestion = true;
      if (resolved.frequencyKm != null) {
        final base = double.tryParse(_mileageCtrl.text.trim()) ?? widget.currentMileage;
        _nextDueMileageCtrl.text = (base + resolved.frequencyKm!).toStringAsFixed(0);
      } else {
        _nextDueMileageCtrl.clear();
      }
      _applyingSuggestion = false;
    }
    if (!_nextDueDateUserEdited) {
      _nextDueDate = resolved.frequencyMonths != null
          ? DateTime(_date.year, _date.month + resolved.frequencyMonths!, _date.day)
          : null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _editFrequency() async {
    final ctrl = TextEditingController(
      text: _resolvedFrequency?.frequencyKm?.toStringAsFixed(0) ?? '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Fréquence pour « $_category » sur ce véhicule'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(),
          decoration: const InputDecoration(labelText: 'Kilomètres', suffixText: 'km'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(double.tryParse(ctrl.text.trim())),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    await ref
        .read(operationFrequencyRepositoryProvider)
        .setFor(widget.vehicleId, _category, frequencyKm: result);
    _nextDueMileageUserEdited = false;
    _applySuggestion(vehicleFrequencyKm: result);
    if (mounted) {
      showAppSnackBar(context, 'Fréquence mémorisée pour ce véhicule',
          icon: Icons.check_circle_outline);
    }
  }

  /// Explicit, user-initiated recompute of the next-due échéance from the
  /// entry's current mileage and the frequency in force - lets an edited
  /// operation's échéance stay coherent with the rule without ever
  /// silently overwriting a value the owner customized on their own.
  void _recalculateNextDue() {
    _nextDueMileageUserEdited = false;
    _nextDueDateUserEdited = false;
    _applySuggestion(
      vehicleFrequencyKm:
          _resolvedFrequency?.isVehicleSpecific == true ? _resolvedFrequency!.frequencyKm : null,
      vehicleFrequencyMonths: _resolvedFrequency?.isVehicleSpecific == true
          ? _resolvedFrequency!.frequencyMonths
          : null,
    );
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
                    onChanged: (v) {
                      setState(() => _category = v!);
                      _loadFrequencyAndSuggest();
                    },
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
                          onChanged: (_) {
                            if (!_nextDueMileageUserEdited) {
                              _applySuggestion(
                                vehicleFrequencyKm:
                                    _resolvedFrequency?.isVehicleSpecific == true
                                        ? _resolvedFrequency!.frequencyKm
                                        : null,
                                vehicleFrequencyMonths:
                                    _resolvedFrequency?.isVehicleSpecific == true
                                        ? _resolvedFrequency!.frequencyMonths
                                        : null,
                              );
                            }
                          },
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
                  Text(_nextDueLabel, style: Theme.of(context).textTheme.titleSmall),
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
                            if (picked != null) {
                              _nextDueDateUserEdited = true;
                              setState(() => _nextDueDate = picked);
                            }
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
                  if (_resolvedFrequency?.isRecurrent ?? false)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _resolvedFrequency!.isVehicleSpecific
                                  ? 'Fréquence de ce véhicule : '
                                      '${_resolvedFrequency!.frequencyKm?.toStringAsFixed(0)} km'
                                  : 'Suggestion AutoCarnet (modifiable) : '
                                      '${_resolvedFrequency!.frequencyKm?.toStringAsFixed(0)} km',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          if (_isEditing)
                            TextButton(
                              onPressed: _recalculateNextDue,
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              child: const Text('Recalculer'),
                            ),
                          TextButton(
                            onPressed: _editFrequency,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero),
                            child: const Text('Modifier'),
                          ),
                        ],
                      ),
                    )
                  else if (_isNewEntry)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Aucune échéance automatique pour cette catégorie. '
                        'Ajoutez-en une seulement si nécessaire.',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
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
