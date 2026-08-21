import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/biometric_service.dart';
import '../data/pin_service.dart';

/// The local access-code screen (spec bloc 5/19 - DEVICE_AUTHORIZED_LOCKED):
/// shown on every normal app launch once a device is authorized, and again
/// after "Verrouiller". Never touches the cloud account itself - it only
/// ever protects local access on this device (spec bloc 1's VERROUILLAGE
/// LOCAL, distinct from CONNEXION and CHANGER DE COMPTE).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({
    super.key,
    required this.accountId,
    required this.email,
    required this.onUnlocked,
    required this.onForgotCode,
    required this.onSwitchAccount,
  });

  /// Whose PIN/biometric this screen checks - the account currently active
  /// on this device. Every PinService/BiometricService call below is
  /// scoped to this id so account A's PIN can never open account B's data
  /// (spec TEST F).
  final String accountId;

  /// The account this device is currently authorized for (spec bloc 5 -
  /// "Bienvenue {email}") - purely cosmetic, never used for any decision.
  final String? email;
  final VoidCallback onUnlocked;
  final VoidCallback onForgotCode;
  final VoidCallback onSwitchAccount;

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
    final enabled = await biometrics.isEnabled(widget.accountId);
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
    final ok = await ref.read(pinServiceProvider).verifyPin(widget.accountId, _pinCtrl.text.trim());
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

  Future<void> _onForgotCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Code d\'accès oublié ?'),
        content: const Text(
          'Un code de vérification va être envoyé à l\'adresse email de ce '
          'compte pour confirmer votre identité, puis vous pourrez définir '
          'un nouveau code d\'accès.',
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
    if (confirmed == true) widget.onForgotCode();
  }

  Future<void> _onSwitchAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Changer de compte sur cet appareil ?'),
        content: const Text(
          'Saisissez l\'adresse email de l\'autre compte. S\'il est déjà '
          'connu sur cet appareil, vous accéderez directement à son code '
          'd\'accès - sinon un code de vérification vous sera envoyé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Changer de compte'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onSwitchAccount();
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
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Bienvenue',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.email != null && widget.email!.isNotEmpty)
                    Text(
                      widget.email!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pinCtrl,
                    autofocus: true,
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
                    decoration: const InputDecoration(labelText: 'Code d\'accès'),
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
