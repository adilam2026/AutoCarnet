import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/section_header.dart';
import '../../account/data/account_repository.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../onboarding_lock/data/pin_service.dart';
import '../../onboarding_lock/presentation/app_gate.dart';
import '../../onboarding_lock/presentation/pin_dialogs.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _pinEnabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _refreshSecurityState();
  }

  Future<void> _refreshSecurityState() async {
    final service = ref.read(pinServiceProvider);
    final results = await Future.wait([
      service.isPinSet(),
      service.canUseBiometrics(),
      service.isBiometricEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _pinEnabled = results[0];
      _biometricAvailable = results[1];
      _biometricEnabled = results[2];
      _loading = false;
    });
  }

  Future<void> _onPinToggled(bool enable) async {
    final service = ref.read(pinServiceProvider);
    if (enable) {
      final created = await showSetPinDialog(context, ref);
      if (created && mounted) {
        showAppSnackBar(context, 'Code PIN activé', icon: Icons.lock_outline);
      }
    } else {
      final confirmed = await showConfirmCurrentPinDialog(context, ref);
      if (confirmed) {
        await service.clearPin();
        if (mounted) {
          showAppSnackBar(context, 'Code PIN désactivé', icon: Icons.lock_open_outlined);
        }
      }
    }
    await _refreshSecurityState();
  }

  Future<void> _onChangePin() async {
    final changed = await showSetPinDialog(context, ref);
    if (changed && mounted) {
      showAppSnackBar(context, 'Code PIN mis à jour', icon: Icons.check_circle_outline);
    }
  }

  Future<void> _onBiometricToggled(bool enable) async {
    await ref.read(pinServiceProvider).setBiometricEnabled(enable);
    if (!mounted) return;
    setState(() => _biometricEnabled = enable);
    showAppSnackBar(
      context,
      enable ? 'Déverrouillage biométrique activé' : 'Déverrouillage biométrique désactivé',
      icon: Icons.check_circle_outline,
    );
  }

  Future<void> _onEditDisplayName(LocalProfile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nom et prénom'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom affiché'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == profile.displayName) return;
    await ref
        .read(localProfileRepositoryProvider)
        .updatePreferences(profile.id, displayName: newName);
    if (mounted) {
      showAppSnackBar(context, 'Nom mis à jour', icon: Icons.check_circle_outline);
    }
  }

  /// Reverrouille l'application sur cet appareil (bloc 6) - la donnée
  /// locale n'est jamais touchée, seul l'état de déverrouillage l'est.
  /// "Se déconnecter de tous les appareils" nécessite le compte cloud à
  /// venir et n'est donc pas proposé tant qu'il n'existe pas.
  Future<void> _onLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'L\'application se reverrouille sur cet appareil. Vos données '
          'restent enregistrées et ne sont pas supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(sessionLockRequestProvider.notifier).state++;
  }

  /// Closes the Supabase account session (bloc 6/9) - unlike [_onLogout],
  /// this actually invalidates the cloud session's tokens, not just the
  /// local PIN unlock state, and sends the gate back to account
  /// authentication rather than the PIN screen.
  Future<void> _onAccountSignOut({required bool everywhere}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(everywhere
            ? 'Se déconnecter de tous les appareils ?'
            : 'Se déconnecter du compte ?'),
        content: Text(everywhere
            ? 'Toutes les sessions de ce compte, sur tous les appareils, '
                'seront fermées. Vos données restent sur le cloud.'
            : 'La session de ce compte sera fermée sur cet appareil. Vos '
                'données restent sur le cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final account = ref.read(accountRepositoryProvider);
    if (everywhere) {
      await account.signOutEverywhere();
    } else {
      await account.signOut();
    }
    ref.read(accountSignOutRequestProvider.notifier).state++;
  }

  Future<void> _onChangeCurrency(LocalProfile profile, String currency) async {
    if (currency == profile.currency) return;
    await ref
        .read(localProfileRepositoryProvider)
        .updatePreferences(profile.id, currency: currency);
    if (mounted) {
      showAppSnackBar(context, 'Devise mise à jour', icon: Icons.check_circle_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(localProfileProvider);
    // Watched purely to rebuild this screen when the session changes -
    // isSignedIn below always reflects the current Supabase state.
    ref.watch(authStateChangesProvider);
    final account = ref.read(accountRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Compte & sécurité')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (account.isSignedIn) ...[
            const SectionHeader('Compte'),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.alternate_email),
                    title: Text(account.currentUser?.email ?? ''),
                    subtitle: const Text('Compte AutoCarnet'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Se déconnecter du compte'),
                    onTap: () => _onAccountSignOut(everywhere: false),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.devices_other_outlined),
                    title: const Text('Se déconnecter de tous les appareils'),
                    onTap: () => _onAccountSignOut(everywhere: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          const SectionHeader('Profil'),
          const SizedBox(height: AppSpacing.sm),
          profileAsync.maybeWhen(
            data: (profile) => profile == null
                ? const SizedBox.shrink()
                : Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(profile.displayName),
                          subtitle: const Text('Nom et prénom'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _onEditDisplayName(profile),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: const Text('Devise'),
                          subtitle: Text(profile.currency),
                          trailing: DropdownButton<String>(
                            value: availableCurrencies.contains(profile.currency)
                                ? profile.currency
                                : availableCurrencies.first,
                            underline: const SizedBox.shrink(),
                            items: availableCurrencies
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) _onChangeCurrency(profile, v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Sécurité'),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.lock_outline),
                        title: const Text('Verrouillage par code PIN'),
                        subtitle: const Text('Protège uniquement l\'accès local'),
                        value: _pinEnabled,
                        onChanged: _onPinToggled,
                      ),
                      if (_pinEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.password_outlined),
                          title: const Text('Modifier le code'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _onChangePin,
                        ),
                      ],
                      if (_pinEnabled && _biometricAvailable) ...[
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('Déverrouillage biométrique'),
                          value: _biometricEnabled,
                          onChanged: _onBiometricToggled,
                        ),
                      ],
                      if (_pinEnabled) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Se déconnecter'),
                          subtitle: const Text(
                              'Reverrouille l\'application sur cet appareil'),
                          onTap: _onLogout,
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              account.isSignedIn
                  ? 'AutoCarnet fonctionne entièrement hors connexion.\n'
                      'La synchronisation entre appareils n\'est pas encore '
                      'active - vos données restent sur cet appareil pour '
                      'le moment.'
                  : 'AutoCarnet fonctionne entièrement hors connexion.\n'
                      'Vos données restent stockées sur cet appareil.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}
