import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/data/account_repository.dart';
import '../data/biometric_service.dart';
import '../data/pin_service.dart';
import 'app_gate.dart';

/// RG-USER-003/004: local unlock only. After repeated failures the retry
/// delay grows (bloc 2 §5.6 "temporisation progressive") instead of
/// permanently locking the user out. "Code oublié ?" is the escape hatch:
/// without it, forgetting the local PIN would strand the user in front of
/// this screen forever, even though the PIN was only ever meant to protect
/// local access, never to replace account authentication.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pinCtrl = TextEditingController();
  String? _error;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  bool _checking = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _maybeOfferBiometric();
  }

  /// Auto-prompts biometrics once, right when the lock screen appears, if
  /// the user has previously turned it on and the device still supports
  /// it - the PIN field underneath is always there and always usable
  /// regardless of what happens here, so a cancelled/failed prompt never
  /// strands anyone.
  Future<void> _maybeOfferBiometric() async {
    final biometrics = ref.read(biometricServiceProvider);
    final enabled = await biometrics.isEnabled();
    if (!enabled) return;
    final supported = await biometrics.isDeviceSupported();
    if (!mounted) return;
    setState(() => _biometricAvailable = supported);
    if (!supported) return;
    final ok = await biometrics.authenticate();
    if (ok && mounted) widget.onUnlocked();
  }

  Future<void> _retryBiometric() async {
    final ok = await ref.read(biometricServiceProvider).authenticate();
    if (ok && mounted) widget.onUnlocked();
  }

  Future<void> _submit() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    setState(() => _checking = true);
    final ok = await ref.read(pinServiceProvider).verifyPin(_pinCtrl.text.trim());
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _failedAttempts++;
      _pinCtrl.clear();
      if (_failedAttempts >= 3) {
        final seconds = 5 * (_failedAttempts - 2);
        _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
        _error = 'Trop de tentatives. Réessayez dans $seconds s.';
      } else {
        _error = 'Code incorrect';
      }
    });
  }

  /// Resets the local code only - it protects local access on this device,
  /// nothing more, so forgetting it doesn't need to touch the cloud account
  /// at all: clear it and go straight back in.
  Future<void> _onForgotCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code oublié ?'),
        content: const Text(
          'Votre code d\'accès local sur cet appareil va être réinitialisé. '
          'Vous pourrez en définir un nouveau depuis Compte & sécurité.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(pinServiceProvider).clearPin();
    await ref.read(biometricServiceProvider).setEnabled(false);
    widget.onUnlocked();
  }

  /// Signs out of the current cloud account (if any) and resets the local
  /// code, so whoever logs back in next - same account or a different one -
  /// starts clean on this device.
  Future<void> _onSwitchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer de compte'),
        content: const Text(
          'Vous allez être déconnecté(e) de ce compte sur cet appareil pour '
          'vous connecter avec un autre. Votre code d\'accès local sera '
          'aussi réinitialisé. Vos données restent en sécurité.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final account = ref.read(accountRepositoryProvider);
    if (account.isSignedIn) {
      await account.signOut();
    }
    // PIN/biometric are cleared centrally by AppGate's
    // accountSignOutRequestProvider listener - every real sign-out path
    // goes through it, so it never needs repeating here.
    if (mounted) ref.read(accountSignOutRequestProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    // TextField's own default for autofillHints is
                    // `const []`, NOT null - which still builds a real
                    // (generic, hint-less) AutofillConfiguration and lets
                    // Android's autofill/password-manager layer attach to
                    // this field. Only an explicit `null` here actually
                    // produces AutofillConfiguration.disabled. A local PIN
                    // has no legitimate autofill use case, so it's fully
                    // opted out - never a stale value silently restored.
                    autofillHints: null,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Code'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: (_checking || locked) ? null : _submit,
                    child: const Text('Déverrouiller'),
                  ),
                  if (_biometricAvailable) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : _retryBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Utiliser la biométrie'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: _checking ? null : _onForgotCode,
                        child: const Text('Code oublié ?'),
                      ),
                      TextButton(
                        onPressed: _checking ? null : _onSwitchAccount,
                        child: const Text('Changer de compte'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
