import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/sheet_handle.dart';
import '../../providers/presentation/provider_picker_field.dart';
import '../data/document_repository.dart';
import '../domain/document_types.dart';

/// Used both for creating a document and for renewing one - renewal simply
/// pre-fills the previous version's data (bloc 4, §7.6).
Future<void> showDocumentFormSheet(
  BuildContext context, {
  required String vehicleId,
  Document? renewing,
  DocumentVersion? renewingVersion,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DocumentFormSheet(
      vehicleId: vehicleId,
      renewing: renewing,
      renewingVersion: renewingVersion,
    ),
  );
}

class _DocumentFormSheet extends ConsumerStatefulWidget {
  const _DocumentFormSheet({
    required this.vehicleId,
    this.renewing,
    this.renewingVersion,
  });

  final String vehicleId;
  final Document? renewing;
  final DocumentVersion? renewingVersion;

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
  ServiceProvider? _selectedProvider;
  final _providerTextCtrl = TextEditingController();
  bool _saving = false;

  bool get isRenewal => widget.renewing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.renewing?.type ?? vehicleDocumentTypes.first;
    _numberCtrl.text = widget.renewingVersion?.documentNumber ?? '';
    _costCtrl.text = widget.renewingVersion?.cost?.toString() ?? '';
    _issueDate = DateTime.now();
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
        _expiryDate = picked;
      } else {
        _issueDate = picked;
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
        typedText: _providerTextCtrl.text,
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
              isRenewal ? 'Renouveler le document' : 'Nouveau document',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            if (!isRenewal)
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type *'),
                items: vehicleDocumentTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _numberCtrl,
              decoration: const InputDecoration(labelText: 'Numéro'),
            ),
            const SizedBox(height: AppSpacing.md),
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
            ),
            const SizedBox(height: AppSpacing.md),
            ProviderPickerField(
              label: 'Organisme / prestataire',
              onSelected: (p) => _selectedProvider = p,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _costCtrl,
              decoration: const InputDecoration(labelText: 'Coût'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
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
