import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pin_service.dart';

/// Reusable "set a new PIN" dialog used both by first-launch onboarding
/// (as a full screen) and from Settings (as a dialog) to keep the same
/// validation rules in one place.
Future<bool> showSetPinDialog(BuildContext context, WidgetRef ref) async {
  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _SetPinDialog(
      pinCtrl: pinCtrl,
      confirmCtrl: confirmCtrl,
    ),
  );
  if (result == true) {
    await ref.read(pinServiceProvider).setPin(pinCtrl.text.trim());
    return true;
  }
  return false;
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog({required this.pinCtrl, required this.confirmCtrl});
  final TextEditingController pinCtrl;
  final TextEditingController confirmCtrl;

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  String? _error;

  void _submit() {
    final pin = widget.pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      setState(() => _error = 'Le code doit contenir 4 à 6 chiffres');
      return;
    }
    if (pin != widget.confirmCtrl.text.trim()) {
      setState(() => _error = 'Les deux codes ne correspondent pas');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Définir un code PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.text,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // Never let Android's autofill/passcode-suggestion overlay
            // hijack this field - on some devices it silently replaces
            // whatever the user is mid-typing with a cached value on
            // backspace.
            autofillHints: const [],
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Nouveau code'),
          ),
          TextField(
            controller: widget.confirmCtrl,
            obscureText: true,
            keyboardType: TextInputType.text,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // Never let Android's autofill/passcode-suggestion overlay
            // hijack this field - on some devices it silently replaces
            // whatever the user is mid-typing with a cached value on
            // backspace.
            autofillHints: const [],
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Confirmer'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Valider')),
      ],
    );
  }
}

/// Asks the user to re-enter their current PIN before a sensitive change
/// (disabling the lock) - a light form of the reauthentication required by
/// the cahier des charges (bloc 2, §5.6).
Future<bool> showConfirmCurrentPinDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final ctrl = TextEditingController();
  final service = ref.read(pinServiceProvider);
  String? error;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        return AlertDialog(
          title: const Text('Confirmez votre code'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            keyboardType: TextInputType.text,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // Never let Android's autofill/passcode-suggestion overlay
            // hijack this field - on some devices it silently replaces
            // whatever the user is mid-typing with a cached value on
            // backspace.
            autofillHints: const [],
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 6,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Code actuel',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await service.verifyPin(ctrl.text.trim());
                if (ok) {
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } else {
                  setState(() => error = 'Code incorrect');
                }
              },
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    ),
  );
  return result ?? false;
}
