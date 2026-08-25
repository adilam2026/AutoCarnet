import 'package:flutter/material.dart';
import '../../../core/widgets/date_field.dart';
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

/// "Mes documents personnels" (mission 2026): documents that belong to the
/// PROFILE, not to any one vehicle - the permis de conduire above all, but
/// architected to take any future personal document the same way (see
/// driverDocumentTypes). Renseigné une seule fois, il vaut pour tous les
/// véhicules du garage - jamais redemandé par voiture, jamais dupliqué.
/// Documents réellement liés à un véhicule (carte grise, assurance, visite
/// technique, vignette, factures, garanties...) restent dans la fiche de ce
/// véhicule (DocumentsTab) - jamais ici.
class PersonalDocumentsScreen extends ConsumerWidget {
  const PersonalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(driverDocumentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes documents personnels')),
      body: docsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
        data: (docs) {
          if (docs.isEmpty) {
            return EmptyState(
              icon: Icons.badge_outlined,
              title: 'Aucun document personnel',
              subtitle: 'Permis de conduire, pièce d\'identité... renseignés ici une '
                  'seule fois, valables pour tous vos véhicules.',
              actionLabel: 'Ajouter un document',
              onAction: () => showDocumentFormSheet(context, vehicleId: null),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              fabSafeBottomPadding(context),
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final d = docs[i];
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
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      d.document.type == 'Permis de conduire'
                          ? Icons.badge_outlined
                          : Icons.description_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 19,
                    ),
                  ),
                  title: Text(d.document.type, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    d.version?.expiryDate != null
                        ? 'Expire le ${_fmt(d.version!.expiryDate!)}'
                        : (d.version?.documentNumber ?? 'Aucune échéance renseignée'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: DocumentStatusChip(status: d.computedStatus),
                  onTap: () => showDocumentFormSheet(
                    context,
                    vehicleId: null,
                    renewing: d.document,
                    renewingVersion: d.version,
                  ),
                ),
              );
              return DismissibleDelete(
                itemKey: ValueKey(d.document.id),
                confirmTitle: 'Supprimer ce document ?',
                confirmMessage: '« ${d.document.type} » sera déplacé dans la corbeille.',
                onConfirmedDelete: () async {
                  await ref.read(documentRepositoryProvider).softDelete(d.document.id);
                  if (context.mounted) {
                    showAppSnackBar(context, 'Document supprimé', icon: Icons.delete_outline);
                  }
                },
                child: card,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDocumentFormSheet(context, vehicleId: null),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un document'),
      ),
    );
  }

  String _fmt(DateTime d) => formatDdMmYyyy(d);
}
