import 'package:flutter/material.dart';

import '../../../core/database/tables.dart';

class DocumentStatusChip extends StatelessWidget {
  const DocumentStatusChip({super.key, required this.status});
  final DocumentVersionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      DocumentVersionStatus.valid => ('Valide', scheme.tertiary),
      DocumentVersionStatus.expiringSoon =>
        ('Expire bientôt', scheme.secondary),
      DocumentVersionStatus.expired => ('Expiré', scheme.error),
      DocumentVersionStatus.archived => ('Archivé', scheme.outline),
      DocumentVersionStatus.replaced => ('Remplacé', scheme.outline),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
