import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/section_header.dart';
import '../../account/data/account_repository.dart';
import '../../onboarding_lock/data/biometric_service.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../onboarding_lock/presentation/app_gate.dart';
import '../../onboarding_lock/presentation/pin_dialogs.dart';
import 'devices_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _refreshSecurityState();
  }

  Future<void> _refreshSecurityState() async {
    final biometrics = ref.read(biometricServiceProvider);
    final biometricSupported = await biometrics.isDeviceSupported();
    final biometricEnabled = await biometrics.isEnabled();
    if (!mounted) return;
    setState(() {
      _biometricSupported = biometricSupported;
      _biometricEnabled = biometricEnabled;
      _loading = false;
    });
  }

  /// Biometrics are always a shortcut layered on an existing PIN, never a
  /// standalone credential - enabling it authenticates once immediately
  /// (so a broken sensor or a cancelled prompt is caught right away,
  /// instead of only at the next lock screen), and disabling never
  /// touches the PIN itself.
  Future<void> _onBiometricToggled(bool enable) async {
    final biometrics = ref.read(biometricServiceProvider);
    if (enable) {
      final ok = await biometrics.authenticate();
      if (!ok) {
        if (mounted) {
          showAppSnackBar(context, 'Authentification biométrique impossible',
              icon: Icons.error_outline);
        }
        return;
      }
    }
    await biometrics.setEnabled(enable);
    if (mounted) {
      showAppSnackBar(
        context,
        enable ? 'Déverrouillage biométrique activé' : 'Déverrouillage biométrique désactivé',
        icon: enable ? Icons.fingerprint : Icons.lock_open_outlined,
      );
    }
    await _refreshSecurityState();
  }

  Future<void> _onChangePin() async {
    final changed = await showSetPinDialog(context, ref);
    if (changed && mounted) {
      showAppSnackBar(context, 'Code PIN mis à jour', icon: Icons.check_circle_outline);
    }
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

  /// Reverrouille l'application sur cet appareil - the local PIN check
  /// only, nothing else (spec bloc 1/7's VERROUILLAGE LOCAL). Deliberately
  /// never called "se déconnecter" anywhere in the UI: that verb is
  /// reserved for [_onSwitchAccount]/[_onDisconnectEverywhere], which
  /// really do end the account's authorization. This one only ever
  /// re-locks; the account stays fully signed in and is instantly usable
  /// again with just the PIN/biometric.
  Future<void> _onLockNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verrouiller l\'application ?'),
        content: const Text(
          'AutoCarnet se reverrouille sur cet appareil - le code PIN (ou la '
          'biométrie) sera nécessaire pour rouvrir. Le compte reste '
          'connecté ; vos données restent enregistrées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Verrouiller'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(sessionLockRequestProvider.notifier).state++;
  }

  /// "Changer de compte" (spec bloc 11/15): dissociates this device from
  /// the current account and sends the gate back to the email screen - the
  /// next sign-in, even with this same address, always requires a fresh
  /// OTP. Unlike [_onLockNow], this really does end the account's
  /// authorization on this device, not just the local PIN unlock state.
  Future<void> _onSwitchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Changer de compte sur cet appareil ?'),
        content: const Text(
          'Ce compte sera dissocié de cet appareil. Vous devrez saisir une '
          'adresse email et un code de vérification pour vous reconnecter, '
          'même avec ce même compte. Vos données restent en sécurité.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Changer de compte'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(accountSwitchRequestProvider.notifier).state++;
  }

  /// Revokes every device's session for this account at once (spec bloc
  /// 6) - a distinct, clearly-named security action, not another word for
  /// "déconnexion"/"verrouiller". Other devices keep their `devices` row
  /// (still listed under "Appareils connectés") but their cached session
  /// can no longer be refreshed.
  Future<void> _onDisconnectEverywhere() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnecter tous les appareils ?'),
        content: const Text(
          'Toutes les sessions de ce compte, sur tous les appareils, seront '
          'fermées. Vos données restent sur le cloud.',
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
                    leading: const Icon(Icons.devices_other_outlined),
                    title: const Text('Appareils connectés'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const DevicesScreen())),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Changer de compte'),
                    onTap: _onSwitchAccount,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Déconnecter tous les appareils'),
                    onTap: _onDisconnectEverywhere,
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
                      ListTile(
                        leading: const Icon(Icons.password_outlined),
                        title: const Text('Modifier le code d\'accès'),
                        subtitle: const Text('Protège uniquement l\'accès local sur cet appareil'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _onChangePin,
                      ),
                      if (_biometricSupported) ...[
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('Déverrouillage biométrique'),
                          subtitle: const Text('Empreinte ou reconnaissance faciale, en plus du PIN'),
                          value: _biometricEnabled,
                          onChanged: _onBiometricToggled,
                        ),
                      ],
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.lock_clock_outlined),
                        title: const Text('Verrouiller maintenant'),
                        subtitle: const Text(
                            'Reverrouille l\'application sur cet appareil - le compte reste connecté'),
                        onTap: _onLockNow,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              account.isSignedIn
                  ? 'AutoCarnet fonctionne entièrement hors connexion.\n'
                      'Vos véhicules se synchronisent automatiquement avec '
                      'votre compte dès qu\'une connexion est disponible.'
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
