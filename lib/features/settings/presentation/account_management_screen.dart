import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/icon_chip.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/section_header.dart';
import '../../onboarding_lock/presentation/app_gate.dart';

/// "Gestion du compte": the two rare, sensitive actions that really end an
/// account's authorization somewhere - deliberately isolated behind this
/// extra tap and off the main Compte & sécurité page, so they can never be
/// hit by mistake while looking for "Changer de compte" or "Verrouiller"
/// (both of which live elsewhere: the lock screen and the main drawer,
/// respectively). Neither action here ever deletes the account or its
/// cloud data - only this device's local authorization, or every device's.
class AccountManagementScreen extends ConsumerWidget {
  const AccountManagementScreen({super.key});

  /// Mission point 7 ("avertissement avant action destructrice"): a
  /// disconnect/dissociate must never happen while the outbox still has
  /// unsynced local changes, and the app must never let the user believe
  /// everything is already saved when it isn't. Returns true only when it's
  /// safe to proceed straight to the action's own confirmation dialog -
  /// false either cancels outright or only nudges a sync pass, but never
  /// lets the destructive action itself run in the same tap.
  Future<bool> _proceedPastPendingSyncWarning(BuildContext context, WidgetRef ref) async {
    // A direct, awaited query - not syncStatusProvider's stream-backed
    // pendingCount, which can still read 0 on a "cold" first watch before
    // its underlying stream has emitted, even when the outbox genuinely
    // isn't empty. This decision must always see the true count.
    final pendingCount = await ref.read(syncOutboxRepositoryProvider).pendingCount();
    if (pendingCount == 0) return true;
    if (!context.mounted) return false;

    final choice = await showDialog<_PendingSyncChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifications non sauvegardées'),
        content: Text(
          'Certaines modifications ne sont pas encore sauvegardées dans le '
          'cloud ($pendingCount en attente). Continuer maintenant risque de '
          'les perdre sur cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_PendingSyncChoice.cancel),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_PendingSyncChoice.syncNow),
            child: const Text('Synchroniser maintenant'),
          ),
        ],
      ),
    );
    if (choice == _PendingSyncChoice.syncNow) {
      unawaited(ref.read(syncCoordinatorProvider).syncAll());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synchronisation en cours...')),
        );
      }
    }
    return false;
  }

  /// The real, deliberate dissociation of the currently active account from
  /// this device: a fresh OTP will be required next time, even for this
  /// exact email. Any other account this device also knows is left
  /// completely untouched.
  Future<void> _onDissociateThisDevice(BuildContext context, WidgetRef ref) async {
    if (!await _proceedPastPendingSyncWarning(context, ref)) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dissocier ce compte de cet appareil ?'),
        content: const Text(
          'Vous devrez vérifier votre adresse email pour l\'utiliser à nouveau '
          'sur cet appareil. Vos données restent sur le cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Dissocier'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(accountDissociateRequestProvider.notifier).state++;
  }

  /// Revokes every device's session for this account at once - other
  /// devices keep their `devices` row (still listed under "Appareils
  /// connectés") but their cached session can no longer be refreshed.
  Future<void> _onDisconnectEverywhere(BuildContext context, WidgetRef ref) async {
    if (!await _proceedPastPendingSyncWarning(context, ref)) return;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnecter tous les appareils ?'),
        content: const Text(
          'Toutes les sessions de ce compte, sur tous les appareils (y compris '
          'celui-ci), seront fermées. Chaque appareil devra vérifier à nouveau '
          'l\'adresse email pour se reconnecter. Vos données restent sur le '
          'cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Déconnecter tout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(accountDisconnectEverywhereRequestProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestion du compte')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SectionHeader('Actions sensibles'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Actions rares et sensibles. Elles ne suppriment jamais le compte '
            'ni ses données sur le cloud.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ListSurface(
            children: [
              ListTile(
                leading: IconChip(Icons.link_off, color: Theme.of(context).colorScheme.error),
                title: const Text('Dissocier ce compte de cet appareil'),
                subtitle: const Text(
                    'Retour à l\'écran email - une vérification sera requise pour se reconnecter ici'),
                onTap: () => _onDissociateThisDevice(context, ref),
              ),
              ListTile(
                leading: IconChip(Icons.logout, color: Theme.of(context).colorScheme.error),
                title: const Text('Déconnecter tous les appareils'),
                subtitle: const Text('Ferme toutes les sessions de ce compte, partout'),
                onTap: () => _onDisconnectEverywhere(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _PendingSyncChoice { cancel, syncNow }
