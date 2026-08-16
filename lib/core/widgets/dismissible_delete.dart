import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Swipe-to-delete wrapper shared by every list item that can be removed
/// (documents, maintenance, expenses, fuel entries). Always confirms first
/// (Principe 7: never destroy data silently) and gives a clear visual cue
/// while swiping.
class DismissibleDelete extends StatelessWidget {
  const DismissibleDelete({
    super.key,
    required this.itemKey,
    required this.child,
    required this.onConfirmedDelete,
    required this.confirmTitle,
    required this.confirmMessage,
  });

  final Key itemKey;
  final Widget child;
  final Future<void> Function() onConfirmedDelete;
  final String confirmTitle;
  final String confirmMessage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: itemKey,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(confirmTitle),
            content: Text(confirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) => onConfirmedDelete(),
      child: child,
    );
  }
}
