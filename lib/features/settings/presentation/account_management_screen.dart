import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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

  /// The real, deliberate dissociation of the currently active account from
  /// this device: a fresh OTP will be required next time, even for this
  /// exact email. Any other account this device also knows is left
  /// completely untouched.
  Future<void> _onDissociateThisDevice(BuildContext context, WidgetRef ref) async {
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
          Text(
            'Actions rares et sensibles. Elles ne suppriment jamais le compte '
            'ni ses données sur le cloud.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text('Dissocier ce compte de cet appareil'),
                  subtitle: const Text(
                      'Retour à l\'écran email - une vérification sera requise pour se reconnecter ici'),
                  onTap: () => _onDissociateThisDevice(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Déconnecter tous les appareils'),
                  subtitle: const Text('Ferme toutes les sessions de ce compte, partout'),
                  onTap: () => _onDisconnectEverywhere(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
