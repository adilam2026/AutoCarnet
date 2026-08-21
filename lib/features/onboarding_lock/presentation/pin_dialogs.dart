import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pin_service.dart';

/// Reusable "set a new PIN" dialog, used from Settings ("Modifier le code
/// d'accès") to keep the validation rules in one place. [accountId] scopes
/// the new PIN to whichever account is currently active (spec TEST F).
Future<bool> showSetPinDialog(BuildContext context, WidgetRef ref, String accountId) async {
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
    await ref.read(pinServiceProvider).setPin(accountId, pinCtrl.text.trim());
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
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // TextField's own default for autofillHints is `const []`,
            // NOT null - which still builds a real (generic, hint-less)
            // AutofillConfiguration and lets Android's autofill layer
            // attach to this field. Only an explicit `null` here actually
            // disables it. A local PIN has no legitimate autofill use
            // case, so it's fully opted out.
            autofillHints: null,
            enableSuggestions: false,
            autocorrect: false,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Nouveau code'),
          ),
          TextField(
            controller: widget.confirmCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // TextField's own default for autofillHints is `const []`,
            // NOT null - which still builds a real (generic, hint-less)
            // AutofillConfiguration and lets Android's autofill layer
            // attach to this field. Only an explicit `null` here actually
            // disables it. A local PIN has no legitimate autofill use
            // case, so it's fully opted out.
            autofillHints: null,
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
