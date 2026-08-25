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
import '../domain/adblue_rules.dart';

/// A dedicated, purpose-built sheet for "Plein AdBlue" (mission 2026, point
/// 2) - deliberately NOT [showFuelFormSheet] with a fuel-type switch: an
/// AdBlue fill's primary input is a direct montant (quantité is only "si
/// connue", never required), whereas a real fill-up always requires both a
/// quantity and a price/liter. Reusing that form's validators would force
/// an AdBlue entry to fake a quantity/price it may not have. Under the
/// hood this still creates a plain [FuelEntry] with [adblueFuelType] as its
/// fuelType (see fuel_repository.dart's doc comment) - only the UI differs.
Future<void> showAdblueFormSheet(
  BuildContext context, {
  required String vehicleId,
  required double currentMileage,
  FuelEntry? editing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AdblueFormSheet(
      vehicleId: vehicleId,
      currentMileage: currentMileage,
      editing: editing,
    ),
  );
}

class _AdblueFormSheet extends ConsumerStatefulWidget {
  const _AdblueFormSheet({
    required this.vehicleId,
    required this.currentMileage,
    this.editing,
  });
  final String vehicleId;
  final double currentMileage;
  final FuelEntry? editing;

  @override
  ConsumerState<_AdblueFormSheet> createState() => _AdblueFormSheetState();
}

class _AdblueFormSheetState extends ConsumerState<_AdblueFormSheet> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _mileageCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  ServiceProvider? _selectedProvider;
  String _providerText = '';
  String? _initialProviderName;
  bool _saving = false;
  bool _deleting = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _mileageCtrl.text = widget.currentMileage.toStringAsFixed(0);
    final source = widget.editing;
    if (source != null) {
      _date = source.date;
      _mileageCtrl.text = source.mileage.toStringAsFixed(0);
      _amountCtrl.text = source.totalAmount.toStringAsFixed(2);
      _quantityCtrl.text =
          source.quantityLiters > 0 ? source.quantityLiters.toStringAsFixed(2) : '';
      _commentsCtrl.text = source.comments ?? '';
      if (source.providerId != null) {
        _loadProvider(source.providerId!);
      }
    }
  }

  Future<void> _loadProvider(String providerId) async {
    final provider = await ref.read(providerRepositoryProvider).getById(providerId);
    if (!mounted) return;
    setState(() {
      _selectedProvider = provider;
      _initialProviderName = provider?.name;
      _providerText = provider?.name ?? '';
    });
  }

  @override
  void dispose() {
    _mileageCtrl.dispose();
    _amountCtrl.dispose();
    _quantityCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
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
      final quantity = double.tryParse(_quantityCtrl.text.trim()) ?? 0;
      final amount = double.parse(_amountCtrl.text.trim());
      final mileage = double.parse(_mileageCtrl.text.trim());
      if (_isEditing) {
        await repo.updateEntry(
          id: widget.editing!.id,
          vehicleId: widget.vehicleId,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: mileage,
          fuelType: adblueFuelType,
          quantityLiters: quantity,
          pricePerLiter: 0,
          totalAmountOverride: amount,
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty ? null : _commentsCtrl.text.trim(),
        );
      } else {
        await repo.createEntry(
          vehicleId: widget.vehicleId,
          date: _date,
          currency: ref.read(defaultCurrencyProvider),
          mileage: mileage,
          fuelType: adblueFuelType,
          quantityLiters: quantity,
          pricePerLiter: 0,
          totalAmountOverride: amount,
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty ? null : _commentsCtrl.text.trim(),
        );
      }
      if (mounted) {
        showAppSnackBar(
          context,
          _isEditing ? 'Plein AdBlue modifié' : 'Plein AdBlue enregistré',
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
        title: const Text('Supprimer ce plein AdBlue ?'),
        content: Text(
            'Le plein AdBlue du ${formatDdMmYyyy(_date)} sera déplacé dans la corbeille.'),
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
      showAppSnackBar(context, 'Plein AdBlue supprimé', icon: Icons.delete_outline);
      Navigator.of(context).pop();
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Modifier le plein AdBlue' : 'Nouveau plein AdBlue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _saving || _deleting ? null : _delete,
                  ),
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
                    decoration: const InputDecoration(labelText: 'Kilométrage *', suffixText: 'km'),
                    keyboardType: const TextInputType.numberWithOptions(),
                    validator: (v) =>
                        (v == null || double.tryParse(v) == null) ? 'Requis' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Montant *',
                      suffixText: ref.read(defaultCurrencyProvider),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) =>
                        (v == null || double.tryParse(v) == null) ? 'Requis' : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _quantityCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Quantité (si connue)', suffixText: 'L'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ProviderPickerField(
              label: 'Station-service',
              initialName: _initialProviderName,
              onSelected: (p) => _selectedProvider = p,
              onTextChanged: (text) => _providerText = text,
              category: ServiceProviderCategory.stationService,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _commentsCtrl,
              decoration: const InputDecoration(labelText: 'Commentaire'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
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
