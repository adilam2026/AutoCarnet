import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../account/data/account_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../../vehicles/domain/vehicle_ownership.dart';
import '../data/document_repository.dart';
import 'document_form_sheet.dart';
import 'document_status_chip.dart';

class DocumentsTab extends ConsumerStatefulWidget {
  const DocumentsTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<DocumentsTab> {
  DocumentVersionStatus? _statusFilter;
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(vehicleDocumentsProvider(widget.vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(widget.vehicleId));
    final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
    final canEdit = vehicleAsync.maybeWhen(
      data: (v) => v != null && canEditVehicle(v, currentUserId),
      orElse: () => false,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: docsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
        data: (docs) {
          if (docs.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: 'Aucun document pour le moment',
              subtitle: canEdit
                  ? 'Carte grise, assurance, contrôle technique... ajoutez '
                        'les documents de ce véhicule pour ne plus jamais les '
                        'chercher.'
                  : 'Vous avez un accès en lecture seule à ce véhicule.',
              actionLabel: canEdit ? 'Ajouter un document' : null,
              onAction: !canEdit
                  ? null
                  : () => showDocumentFormSheet(
                      context,
                      vehicleId: widget.vehicleId,
                    ),
            );
          }
          final types = {for (final d in docs) d.document.type}.toList()
            ..sort();
          final filtered = docs
              .where(
                (d) =>
                    _statusFilter == null || d.computedStatus == _statusFilter,
              )
              .where(
                (d) => _typeFilter == null || d.document.type == _typeFilter,
              )
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Tous'),
                            selected: _statusFilter == null,
                            onSelected: (_) =>
                                setState(() => _statusFilter = null),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Valides'),
                            selected:
                                _statusFilter == DocumentVersionStatus.valid,
                            onSelected: (_) => setState(
                              () => _statusFilter = DocumentVersionStatus.valid,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Expirent bientôt'),
                            selected:
                                _statusFilter ==
                                DocumentVersionStatus.expiringSoon,
                            onSelected: (_) => setState(
                              () => _statusFilter =
                                  DocumentVersionStatus.expiringSoon,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Expirés'),
                            selected:
                                _statusFilter == DocumentVersionStatus.expired,
                            onSelected: (_) => setState(
                              () =>
                                  _statusFilter = DocumentVersionStatus.expired,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Archivés'),
                            selected:
                                _statusFilter == DocumentVersionStatus.archived,
                            onSelected: (_) => setState(
                              () => _statusFilter =
                                  DocumentVersionStatus.archived,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (types.length > 1) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Tous types'),
                              selected: _typeFilter == null,
                              onSelected: (_) =>
                                  setState(() => _typeFilter = null),
                            ),
                            const SizedBox(width: 8),
                            for (final t in types) ...[
                              ChoiceChip(
                                label: Text(t),
                                selected: _typeFilter == t,
                                onSelected: (_) =>
                                    setState(() => _typeFilter = t),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Aucun résultat pour ces filtres',
                        subtitle: 'Essayez un autre statut ou type.',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          fabSafeBottomPadding(context),
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final d = filtered[i];
                          final card = Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.description_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 19,
                                ),
                              ),
                              title: Text(
                                d.document.type,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                d.version?.expiryDate != null
                                    ? 'Expire le ${_fmt(d.version!.expiryDate!)}'
                                    : (d.version?.documentNumber ??
                                          'Sans échéance'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: DocumentStatusChip(
                                status: d.computedStatus,
                              ),
                              onTap: !canEdit
                                  ? null
                                  : () => showDocumentFormSheet(
                                      context,
                                      vehicleId: widget.vehicleId,
                                      renewing: d.document,
                                      renewingVersion: d.version,
                                    ),
                            ),
                          );
                          if (!canEdit) return card;
                          return DismissibleDelete(
                            itemKey: ValueKey(d.document.id),
                            confirmTitle: 'Supprimer ce document ?',
                            confirmMessage:
                                '« ${d.document.type} » sera déplacé dans la '
                                'corbeille.',
                            onConfirmedDelete: () async {
                              await ref
                                  .read(documentRepositoryProvider)
                                  .softDelete(d.document.id);
                              if (context.mounted) {
                                showAppSnackBar(
                                  context,
                                  'Document supprimé',
                                  icon: Icons.delete_outline,
                                );
                              }
                            },
                            child: card,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: !canEdit
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  showDocumentFormSheet(context, vehicleId: widget.vehicleId),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un document'),
            ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
