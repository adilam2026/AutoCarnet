import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/widgets/section_header.dart';
import '../../onboarding_lock/data/local_profile_repository.dart';
import '../../onboarding_lock/data/pin_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(localProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SectionHeader('Profil'),
          const SizedBox(height: AppSpacing.sm),
          profileAsync.maybeWhen(
            data: (profile) => Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(profile?.displayName ?? '—'),
                subtitle: Text(
                  'Devise : ${profile?.currency ?? '—'} • Unité : ${profile?.distanceUnit ?? '—'}',
                ),
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
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'AutoCarnet fonctionne entièrement hors connexion.\n'
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
