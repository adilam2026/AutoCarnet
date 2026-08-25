import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../providers/data/provider_repository.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/fuel_repository.dart';
import '../domain/fuel_types.dart';

/// Used both to create a new fill-up and to open/edit/duplicate an existing
/// one - the same form serves as the "detail" view. [vehicleFuelType] is
/// the selected vehicle's own fuel type (the fiche's source of truth,
/// mission: never re-ask what AutoCarnet already knows) - it only pre-fills
/// a genuinely new entry, never overrides [editing]/[duplicateFrom]'s own
/// recorded value.
Future<void> showFuelFormSheet(
  BuildContext context, {
  required String vehicleId,
  required double currentMileage,
  String? vehicleFuelType,
  FuelEntry? editing,
  FuelEntry? duplicateFrom,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FuelFormSheet(
      vehicleId: vehicleId,
      currentMileage: currentMileage,
      vehicleFuelType: vehicleFuelType,
      editing: editing,
      duplicateFrom: duplicateFrom,
    ),
  );
}

class _FuelFormSheet extends ConsumerStatefulWidget {
  const _FuelFormSheet({
    required this.vehicleId,
    required this.currentMileage,
    this.vehicleFuelType,
    this.editing,
    this.duplicateFrom,
  });
  final String vehicleId;
  final double currentMileage;
  final String? vehicleFuelType;
  final FuelEntry? editing;
  final FuelEntry? duplicateFrom;

  @override
  ConsumerState<_FuelFormSheet> createState() => _FuelFormSheetState();
}

class _FuelFormSheetState extends ConsumerState<_FuelFormSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _mileageCtrl = TextEditingController();
  String? _fuelType;
  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _isFullTank = true;
  ServiceProvider? _selectedProvider;
  String _providerText = '';
  String? _initialProviderName;
  bool _saving = false;
  bool _deleting = false;
  bool _ready = false;

  FuelEntry? get _source => widget.editing ?? widget.duplicateFrom;
  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
    // The vehicle's own fuel type is the source of truth (mission: never
    // ask again for something AutoCarnet already knows, and never invent
    // one either) - pre-filled only when the vehicle's fuel type is set
    // and is one of the values this picker offers (free-text legacy data
    // aside); left unset otherwise, forcing an explicit choice rather than
    // silently defaulting to "Essence".
    _fuelType = (widget.vehicleFuelType != null && fuelTypes.contains(widget.vehicleFuelType))
        ? widget.vehicleFuelType
        : null;
    _init();
  }

  Future<void> _init() async {
    final source = _source;
    if (source == null) {
      setState(() => _ready = true);
      return;
    }
    _date = _isEditing ? source.date : DateTime.now();
    _mileageCtrl.text = source.mileage.toStringAsFixed(0);
    _fuelType = source.fuelType;
    _quantityCtrl.text = source.quantityLiters.toStringAsFixed(2);
    _priceCtrl.text = source.pricePerLiter.toStringAsFixed(2);
    _isFullTank = source.isFullTank;

    if (source.providerId != null) {
      final provider =
          await ref.read(providerRepositoryProvider).getById(source.providerId!);
      _selectedProvider = provider;
      _initialProviderName = provider?.name;
      _providerText = provider?.name ?? '';
    }
    if (mounted) setState(() => _ready = true);
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
        typedText: _providerText,
        category: ServiceProviderCategory.stationService,
      );
      final repo = ref.read(fuelRepositoryProvider);
      if (_isEditing) {
        await repo.updateEntry(
          id: widget.editing!.id,
          vehicleId: widget.vehicleId,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: double.parse(_mileageCtrl.text.trim()),
          fuelType: _fuelType!,
          quantityLiters: double.parse(_quantityCtrl.text.trim()),
          pricePerLiter: double.parse(_priceCtrl.text.trim()),
          providerId: providerId,
          isFullTank: _isFullTank,
        );
      } else {
        await repo.createEntry(
          vehicleId: widget.vehicleId,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: double.parse(_mileageCtrl.text.trim()),
          fuelType: _fuelType!,
          quantityLiters: double.parse(_quantityCtrl.text.trim()),
          pricePerLiter: double.parse(_priceCtrl.text.trim()),
          providerId: providerId,
          isFullTank: _isFullTank,
        );
      }
      if (mounted) {
        showAppSnackBar(
          context,
          _isEditing ? 'Plein modifié' : 'Plein enregistré',
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
        title: const Text('Supprimer ce plein ?'),
        content: Text('Le plein du ${formatDdMmYyyy(_date)} sera déplacé dans la corbeille.'),
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
    await ref.read(fuelRepositoryProvider).softDelete(widget.editing!.id);
    if (mounted) {
      showAppSnackBar(context, 'Plein supprimé', icon: Icons.delete_outline);
      Navigator.of(context).pop();
    }
  }

  void _duplicate() {
    final source = widget.editing;
    if (source == null) return;
    Navigator.of(context).pop();
    showFuelFormSheet(
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
                          _isEditing ? 'Modifier le plein' : 'Nouveau plein',
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
                  Row(
                    children: [
                      Expanded(
                        child: AppDateField(
                          label: 'Date *',
                          initialDate: _date,
                          requiredField: true,
                          onChanged: (d) {
                            if (d != null) setState(() => _date = d);
                          },
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
                    decoration: const InputDecoration(labelText: 'Carburant *'),
                    hint: const Text('Sélectionner'),
                    isExpanded: true,
                    items: fuelTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _fuelType = v),
                    validator: (v) => v == null ? 'Champ requis' : null,
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
                  Text.rich(
                    TextSpan(
                      text: 'Total : ',
                      style: Theme.of(context).textTheme.titleSmall,
                      children: [
                        TextSpan(
                          text: _total.toStringAsFixed(2),
                          style: AppTypography.mono(
                            context,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ProviderPickerField(
                    label: 'Station-service',
                    initialName: _initialProviderName,
                    onSelected: (p) => _selectedProvider = p,
                    onTextChanged: (text) => _providerText = text,
                    category: ServiceProviderCategory.stationService,
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
}
