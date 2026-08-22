import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/auth_error_message.dart';
import '../data/account_repository.dart';

/// First (and, per spec bloc 6, normally the *only*) screen a device with
/// no account association ever shows: a single email field, nothing else
/// (spec bloc 2 - "Ne pas demander le nom. Le nom pourra être demandé plus
/// tard dans le profil si nécessaire."). AutoCarnet has no guest/offline
/// mode (spec bloc 12): there is no escape hatch here on purpose.
///
/// Also the single place that implements spec bloc 19's CAS 1/2/3 decision:
/// submitting first tries a silent, OTP-free restore for this exact email
/// on this exact device (spec CAS 3 - an already-known account, even one
/// reached via "Changer de compte" rather than a brand new install) before
/// ever sending a code (spec CAS 1/2).
class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({super.key, required this.onCodeSent, required this.onAuthenticated});

  /// Called once a code has actually been sent - never before.
  final ValueChanged<String> onCodeSent;

  /// Called directly, skipping the OTP screen entirely, when this device
  /// already has a valid, known association for the typed email (spec CAS
  /// 3 - "NE PAS envoyer d'OTP").
  final AsyncCallback onAuthenticated;

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = ref.read(accountRepositoryProvider);
      // Spec CAS 3: an email this exact device already knows (whether
      // that's a fresh install's first account, or an account reached
      // through "Changer de compte") never sends an OTP - it goes
      // straight through, skipping the OTP screen entirely.
      final restoredUserId = await account.tryRestoreDeviceSession(email);
      if (restoredUserId != null) {
        if (!mounted) return;
        await widget.onAuthenticated();
        // No re-enabling _busy on purpose, same reasoning as
        // VerifyEmailScreen - this screen is about to be replaced.
        return;
      }
      await account.sendEmailCode(email);
      if (mounted) widget.onCodeSent(email);
    } on AuthException catch (e) {
      debugPrint('EmailEntryScreen._submit: $e');
      if (mounted) setState(() { _error = authErrorMessage(e); _busy = false; });
    } catch (e) {
      debugPrint('EmailEntryScreen._submit: $e');
      if (mounted) {
        setState(() { _error = 'Une erreur est survenue. Réessayez.'; _busy = false; });
      }
    }
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
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.directions_car_filled,
                          size: 40, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Bienvenue sur AutoCarnet',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Connectez-vous avec votre email pour retrouver vos véhicules sur '
                    'tous vos appareils. Aucun mot de passe : un code vous sera envoyé '
                    'par email.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: null,
                    decoration: const InputDecoration(labelText: 'Adresse email'),
                    onSubmitted: (_) {
                      if (!_busy) _submit();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Continuer'),
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
