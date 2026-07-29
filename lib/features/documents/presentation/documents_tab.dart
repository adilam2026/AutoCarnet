import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (docs) {
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun document pour le moment'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final d = docs[i];
              return Card(
                child: ListTile(
                  title: Text(d.document.type),
                  subtitle: Text(
                    d.version?.expiryDate != null
                        ? 'Expire le ${_fmt(d.version!.expiryDate!)}'
                        : (d.version?.documentNumber ?? 'Sans échéance'),
                  ),
                  trailing: DocumentStatusChip(status: d.computedStatus),
                  onTap: () => showDocumentFormSheet(
                    context,
                    vehicleId: vehicleId,
                    renewing: d.document,
                    renewingVersion: d.version,
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
