import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../account/data/account_repository.dart';
import '../data/provider_repository.dart';
import '../domain/service_provider_category.dart';

/// Create AND edit in one screen (same pattern as VehicleEditScreen) -
/// mission point 2: "l'utilisateur doit pouvoir consulter, ajouter,
/// modifier, supprimer" a prestataire from a real form, not only ever
/// implicitly via another module's operation form. Only [name] and
/// [category] are required (mission point 3: "le nom et le type doivent
/// suffire pour enregistrer rapidement un prestataire") - every other
/// field stays optional.
class ProviderFormScreen extends ConsumerStatefulWidget {
  const ProviderFormScreen({super.key, this.editing});

  /// Null to create a new prestataire; non-null to edit an existing one.
  final ServiceProvider? editing;

  @override
  ConsumerState<ProviderFormScreen> createState() => _ProviderFormScreenState();
}

class _ProviderFormScreenState extends ConsumerState<ProviderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _commentsCtrl;
  ServiceProviderCategory? _category;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.editing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _cityCtrl = TextEditingController(text: p?.city ?? '');
    _commentsCtrl = TextEditingController(text: p?.comments ?? '');
    _category = p?.category;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      showAppSnackBar(context, 'Choisissez un type de prestataire', icon: Icons.error_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(providerRepositoryProvider);
      String? orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      if (_isEditing) {
        await repo.updateProvider(
          id: widget.editing!.id,
          name: _nameCtrl.text.trim(),
          category: Value(_category),
          phone: Value(orNull(_phoneCtrl)),
          address: Value(orNull(_addressCtrl)),
          city: Value(orNull(_cityCtrl)),
          comments: Value(orNull(_commentsCtrl)),
        );
      } else {
        final currentUserId = ref.read(accountRepositoryProvider).currentUser?.id;
        await repo.createProvider(
          name: _nameCtrl.text.trim(),
          category: _category,
          phone: orNull(_phoneCtrl),
          address: orNull(_addressCtrl),
          city: orNull(_cityCtrl),
          comments: orNull(_commentsCtrl),
          currentUserId: currentUserId,
        );
      }
      if (mounted) {
        showAppSnackBar(context, _isEditing ? 'Prestataire mis à jour' : 'Prestataire ajouté',
            icon: Icons.check_circle_outline);
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce prestataire ?'),
        content: Text(
          '${widget.editing!.name} ne sera plus proposé dans les listes de sélection. '
          'Les opérations déjà enregistrées le mentionnant restent inchangées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(providerRepositoryProvider).deleteProvider(widget.editing!.id);
    if (mounted) {
      showAppSnackBar(context, 'Prestataire supprimé', icon: Icons.check_circle_outline);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier le prestataire' : 'Ajouter un prestataire'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Supprimer',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom *'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ServiceProviderCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type *'),
              items: [
                for (final c in ServiceProviderCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Type requis' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Téléphone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _cityCtrl,
              decoration: const InputDecoration(labelText: 'Ville'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _commentsCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Enregistrer' : 'Ajouter'),
            ),
          ],
        ),
      ),
    );
  }
}
