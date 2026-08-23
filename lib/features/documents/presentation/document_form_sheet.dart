import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../account/data/account_repository.dart';
import '../../providers/domain/insurance_companies.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/document_repository.dart';
import '../domain/document_renewal_rules.dart';
import '../domain/document_types.dart';

/// Used both for creating a document and for renewing one - renewal simply
/// pre-fills the previous version's data (bloc 4, §7.6). A null [vehicleId]
/// means a driver document (permis de conduire...), shared across the whole
/// garage rather than tied to one vehicle.
Future<void> showDocumentFormSheet(
  BuildContext context, {
  required String? vehicleId,
  Document? renewing,
  DocumentVersion? renewingVersion,
  String? initialType,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DocumentFormSheet(
      vehicleId: vehicleId,
      renewing: renewing,
      renewingVersion: renewingVersion,
      initialType: initialType,
    ),
  );
}

class _DocumentFormSheet extends ConsumerStatefulWidget {
  const _DocumentFormSheet({
    required this.vehicleId,
    this.renewing,
    this.renewingVersion,
    this.initialType,
  });

  final String? vehicleId;
  final Document? renewing;
  final DocumentVersion? renewingVersion;
  final String? initialType;

  @override
  ConsumerState<_DocumentFormSheet> createState() => _DocumentFormSheetState();
}

class _DocumentFormSheetState extends ConsumerState<_DocumentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _type;
  final _numberCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _commentsCtrl = TextEditingController();
  DateTime? _issueDate;
  DateTime? _expiryDate;
  bool _expiryUserEdited = false;
  late int _vignetteYear;
  ServiceProvider? _selectedProvider;
  String _providerText = '';
  bool _saving = false;

  bool get isRenewal => widget.renewing != null;
  bool get isDriverDocument => widget.vehicleId == null;
  List<String> get _availableTypes =>
      isDriverDocument ? driverDocumentTypes : vehicleDocumentTypes;

  /// The type is only ever picked in the generic "Documents -> Ajouter"
  /// entry point. A contextual entry point ("Administratif -> Ajouter
  /// Assurance") already knows the type - it must never ask a second time
  /// (mission point 1/2), and a renewal always keeps the document's own
  /// existing type.
  bool get _typeIsFixed => isRenewal || widget.initialType != null;

  /// Per-type field relevance (mission point 3) - the underlying data model
  /// (documentNumber/issueDate/expiryDate/cost/providerId/comments) is
  /// never extended, only which of those already-existing fields are shown
  /// varies: a "Carte grise" has no expiry or cost, a "Permis de conduire"
  /// has no provider/cost, a "Vignette" has no provider (it's a state tax,
  /// not tied to a prestataire). Any type not explicitly listed here (the
  /// generic-mode types like "Autre", "Facture d'achat"...) keeps every
  /// field, since there's no single right answer for what's irrelevant.
  bool get _showProviderField => switch (_type) {
        'Carte grise' || 'Vignette' || 'Permis de conduire' || 'Pièce d\'identité' => false,
        _ => true,
      };
  bool get _showCostField => switch (_type) {
        'Carte grise' || 'Visite technique' || 'Permis de conduire' || 'Pièce d\'identité' => false,
        _ => true,
      };
  bool get _showExpiryField => _type != 'Carte grise';

  @override
  void initState() {
    super.initState();
    _type = widget.renewing?.type ?? widget.initialType ?? _availableTypes.first;
    _numberCtrl.text = widget.renewingVersion?.documentNumber ?? '';
    _costCtrl.text = widget.renewingVersion?.cost?.toString() ?? '';
    _issueDate = DateTime.now();
    // Renewing a vignette suggests the next civil year after the one just
    // covered: the stored expiry is the grace-period end (31/01 of
    // vignetteYear+1), so that same number is the next year to renew for.
    final priorExpiry = widget.renewingVersion?.expiryDate;
    _vignetteYear = (isCivilYearBound(_type) && priorExpiry != null)
        ? priorExpiry.year
        : DateTime.now().year;
    _applyDefaultExpirySuggestion();
  }

  /// Assurance / visite technique / permis de conduire renew on a fixed
  /// AutoCarnet default (blocs 3-4) - always just a suggestion, never
  /// applied once the owner has picked their own expiry date. The vignette
  /// has no separate date to override - its expiry is always derived from
  /// the selected civil year.
  void _applyDefaultExpirySuggestion() {
    if (isCivilYearBound(_type)) {
      _issueDate = DateTime(_vignetteYear, 1, 1);
      _expiryDate = civilYearDueDate(_vignetteYear);
      return;
    }
    if (_expiryUserEdited) return;
    final issue = _issueDate;
    if (issue == null) return;
    final months = defaultRenewalMonths(_type);
    if (months == null) return;
    _expiryDate = DateTime(issue.year, issue.month + months, issue.day);
  }

  Future<void> _pickDate({required bool isExpiry}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isExpiry) {
        _expiryUserEdited = true;
        _expiryDate = picked;
      } else {
        _issueDate = picked;
        _applyDefaultExpirySuggestion();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final providerId = await resolveOrCreateProvider(
        ref,
        selected: _selectedProvider,
        typedText: _providerText,
        category: _type == 'Assurance' ? ServiceProviderCategory.assurance : null,
      );
      final repo = ref.read(documentRepositoryProvider);
      final cost = double.tryParse(_costCtrl.text.trim());
      if (isRenewal) {
        await repo.renewDocument(
          documentId: widget.renewing!.id,
          documentNumber: _numberCtrl.text.trim().isEmpty
              ? null
              : _numberCtrl.text.trim(),
          issueDate: _issueDate,
          expiryDate: _expiryDate,
          cost: cost,
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
        );
      } else {
        await repo.createDocument(
          vehicleId: widget.vehicleId,
          type: _type,
          documentNumber: _numberCtrl.text.trim().isEmpty
              ? null
              : _numberCtrl.text.trim(),
          issueDate: _issueDate,
          expiryDate: _expiryDate,
          cost: cost,
          providerId: providerId,
          comments: _commentsCtrl.text.trim().isEmpty
              ? null
              : _commentsCtrl.text.trim(),
          currentUserId: ref.read(accountRepositoryProvider).currentUser?.id,
        );
      }
      if (mounted) {
        showAppSnackBar(
          context,
          isRenewal ? 'Document renouvelé' : 'Document ajouté',
          icon: Icons.check_circle_outline,
        );
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
            Text(
              isRenewal
                  ? 'Renouveler le document'
                  : widget.initialType != null
                      ? 'Ajouter · $_type'
                      : 'Nouveau document',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            if (!_typeIsFixed)
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type *'),
                items: _availableTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _type = v!;
                  _applyDefaultExpirySuggestion();
                }),
              ),
            if (!_typeIsFixed) const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _numberCtrl,
              decoration: const InputDecoration(labelText: 'Numéro'),
            ),
            const SizedBox(height: AppSpacing.md),
            if (isCivilYearBound(_type)) ...[
              DropdownButtonFormField<int>(
                initialValue: _vignetteYear,
                decoration: const InputDecoration(labelText: 'Année de la vignette *'),
                items: [
                  for (var y = DateTime.now().year - 1; y <= DateTime.now().year + 1; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() {
                  _vignetteYear = v!;
                  _applyDefaultExpirySuggestion();
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Valable du 1er janvier au 31 décembre $_vignetteYear. '
                  'Délai de grâce accordé par l\'État jusqu\'au 31 janvier '
                  '${_vignetteYear + 1}.',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isExpiry: false),
                      child: Text(_issueDate == null
                          ? 'Date de délivrance'
                          : 'Délivré : ${_fmt(_issueDate!)}'),
                    ),
                  ),
                  if (_showExpiryField) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isExpiry: true),
                        child: Text(_expiryDate == null
                            ? 'Date d\'expiration'
                            : 'Expire : ${_fmt(_expiryDate!)}'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_showExpiryField && !_expiryUserEdited && defaultRenewalMonths(_type) != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Échéance suggérée par AutoCarnet : délivrance + '
                    '${defaultRenewalMonths(_type)} mois (modifiable).',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
            if (_showProviderField) ...[
              const SizedBox(height: AppSpacing.md),
              ProviderPickerField(
                label: switch (_type) {
                  'Assurance' => 'Compagnie d\'assurance',
                  'Visite technique' => 'Centre de contrôle',
                  _ => 'Organisme / prestataire',
                },
                onSelected: (p) => _selectedProvider = p,
                onTextChanged: (text) => _providerText = text,
                category: _type == 'Assurance' ? ServiceProviderCategory.assurance : null,
                presetSuggestions: _type == 'Assurance' ? moroccanAutoInsurers : const [],
              ),
            ],
            if (_showCostField) ...[
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _costCtrl,
                decoration: const InputDecoration(labelText: 'Coût'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _commentsCtrl,
              decoration: const InputDecoration(labelText: 'Commentaires'),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isRenewal ? 'Renouveler' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
