import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pin_service.dart';

/// The local access code that protects this device, required once per
/// account+device pairing right after email/OTP succeeds (spec bloc 5/19 -
/// DEVICE_AUTHORIZED_NEEDS_PIN_SETUP always leads to CREATE_PIN, never
/// straight to HOME) - there is no "skip" here on purpose, an authorized
/// device without a PIN isn't a state this app's flow allows.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      setState(() => _error = 'Le code doit contenir 4 à 6 chiffres');
      return;
    }
    if (pin != _confirmCtrl.text.trim()) {
      setState(() => _error = 'Les deux codes ne correspondent pas');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await ref.read(pinServiceProvider).setPin(pin);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
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
                    'Protégez l\'accès à l\'application',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Ce code ne protège que l\'accès local à AutoCarnet sur cet '
                    'appareil.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    // TextField's own default for autofillHints is
                    // `const []`, NOT null - which still builds a real
                    // (generic, hint-less) AutofillConfiguration and lets
                    // Android's autofill layer attach to this field. Only
                    // an explicit `null` here actually disables it. A
                    // local PIN has no legitimate autofill use case, so
                    // it's fully opted out.
                    autofillHints: null,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Code (4 à 6 chiffres)'),
                  ),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    // TextField's own default for autofillHints is
                    // `const []`, NOT null - which still builds a real
                    // (generic, hint-less) AutofillConfiguration and lets
                    // Android's autofill layer attach to this field. Only
                    // an explicit `null` here actually disables it. A
                    // local PIN has no legitimate autofill use case, so
                    // it's fully opted out.
                    autofillHints: null,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Confirmer le code'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Activer le code'),
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
