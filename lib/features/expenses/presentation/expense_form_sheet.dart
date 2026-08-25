import 'package:flutter/material.dart';
import '../../../core/widgets/date_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../providers/data/provider_repository.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/expense_repository.dart';
import '../domain/expense_categories.dart';

/// Used both to create a new standalone expense and to open/edit/duplicate
/// an existing one. Only ever called for expenses without a
/// linkedMaintenanceId/linkedFuelId - one generated automatically from an
/// operation is edited from that operation instead (single source of truth
/// for its amount).
Future<void> showExpenseFormSheet(
  BuildContext context, {
  required String vehicleId,
  Expense? editing,
  Expense? duplicateFrom,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExpenseFormSheet(
      vehicleId: vehicleId,
      editing: editing,
      duplicateFrom: duplicateFrom,
    ),
  );
}

class _ExpenseFormSheet extends ConsumerStatefulWidget {
  const _ExpenseFormSheet({
    required this.vehicleId,
    this.editing,
    this.duplicateFrom,
  });
  final String vehicleId;
  final Expense? editing;
  final Expense? duplicateFrom;

  @override
  ConsumerState<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<_ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  String _category = expenseCategories.first;
  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  ServiceProvider? _selectedProvider;
  String _providerText = '';
  String? _initialProviderName;
  bool _saving = false;
  bool _deleting = false;
  bool _ready = false;

  Expense? get _source => widget.editing ?? widget.duplicateFrom;
  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
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
    _amountCtrl.text = source.amount.toStringAsFixed(2);
    _commentsCtrl.text = source.comments ?? '';

    if (source.providerId != null) {
      final provider =
          await ref.read(providerRepositoryProvider).getById(source.providerId!);
      _selectedProvider = provider;
      _initialProviderName = provider?.name;
      _providerText = provider?.name ?? '';
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
        typedText: _providerText,
      );
      final repo = ref.read(expenseRepositoryProvider);
      if (_isEditing) {
        await repo.updateExpense(
          id: widget.editing!.id,
          vehicleId: widget.vehicleId,
          category: _category,
          date: _date,
          amount: double.parse(_amountCtrl.text.trim()),
          currency: ref.read(defaultCurrencyProvider),
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
        );
      } else {
        await repo.createExpense(
          vehicleId: widget.vehicleId,
          category: _category,
          date: _date,
          amount: double.parse(_amountCtrl.text.trim()),
          currency: ref.read(defaultCurrencyProvider),
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
        );
      }
      if (mounted) {
        showAppSnackBar(
          context,
          _isEditing ? 'Dépense modifiée' : 'Dépense ajoutée',
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
        title: const Text('Supprimer cette dépense ?'),
        content:
            Text('« $_category » du ${_fmt(_date)} sera déplacée dans la corbeille.'),
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
    await ref.read(expenseRepositoryProvider).softDelete(widget.editing!.id);
    if (mounted) {
      showAppSnackBar(context, 'Dépense supprimée', icon: Icons.delete_outline);
      Navigator.of(context).pop();
    }
  }

  void _duplicate() {
    final source = widget.editing;
    if (source == null) return;
    Navigator.of(context).pop();
    showExpenseFormSheet(
      context,
      vehicleId: widget.vehicleId,
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
                          _isEditing ? 'Modifier la dépense' : 'Nouvelle dépense',
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
                    items: expenseCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
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
                          controller: _amountCtrl,
                          decoration: const InputDecoration(labelText: 'Montant *'),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
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
                    onTextChanged: (text) => _providerText = text,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _commentsCtrl,
                    decoration: const InputDecoration(labelText: 'Commentaires'),
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

  String _fmt(DateTime d) => formatDdMmYyyy(d);
}
