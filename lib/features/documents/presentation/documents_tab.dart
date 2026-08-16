import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../data/document_repository.dart';
import 'document_form_sheet.dart';
import 'document_status_chip.dart';

class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(vehicleDocumentsProvider(vehicleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: docsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (docs) {
          if (docs.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: 'Aucun document pour le moment',
              subtitle:
                  'Carte grise, assurance, contrôle technique... ajoutez '
                  'les documents de ce véhicule pour ne plus jamais les '
                  'chercher.',
              actionLabel: 'Ajouter un document',
              onAction: () => showDocumentFormSheet(context, vehicleId: vehicleId),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final d = docs[i];
              return DismissibleDelete(
                itemKey: ValueKey(d.document.id),
                confirmTitle: 'Supprimer ce document ?',
                confirmMessage:
                    '« ${d.document.type} » sera déplacé dans la corbeille.',
                onConfirmedDelete: () async {
                  await ref
                      .read(documentRepositoryProvider)
                      .softDelete(d.document.id);
                  if (context.mounted) {
                    showAppSnackBar(context, 'Document supprimé',
                        icon: Icons.delete_outline);
                  }
                },
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.6),
                      child: Icon(
                        Icons.description_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
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
                          : (d.version?.documentNumber ?? 'Sans échéance'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: DocumentStatusChip(status: d.computedStatus),
                    onTap: () => showDocumentFormSheet(
                      context,
                      vehicleId: vehicleId,
                      renewing: d.document,
                      renewingVersion: d.version,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDocumentFormSheet(context, vehicleId: vehicleId),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
