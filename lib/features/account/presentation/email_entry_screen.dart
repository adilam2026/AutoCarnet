import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

/// First step of the account-first flow (bloc 7-9): collect an email (and,
/// for a brand new account, a display name) and request a 6-digit code.
/// Supabase's OTP endpoint itself decides signup vs sign-in - this screen
/// never needs to know in advance which case it's in.
///
/// Deliberately its own top-level widget with its own State, never a
/// branch inside a bigger widget's build() method: when the code is sent,
/// the caller swaps this widget out for [VerifyEmailScreen] entirely, so
/// Flutter mounts/unmounts a clean subtree instead of reconciling one
/// step's fields against another's.
class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({
    super.key,
    required this.onCodeSent,
    required this.onContinueOffline,
  });

  /// Called once the code has actually been sent - never before.
  final void Function(String email, String displayName) onCodeSent;
  final VoidCallback onContinueOffline;

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
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
      await ref.read(accountRepositoryProvider).sendEmailCode(email, displayName: _nameCtrl.text);
      if (mounted) widget.onCodeSent(email, _nameCtrl.text.trim());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  Icon(Icons.directions_car_filled,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Bienvenue sur AutoCarnet',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Connectez-vous avec votre email pour retrouver vos véhicules sur '
                    'tous vos appareils, ou continuez sans connexion. Aucun mot de '
                    'passe : un code vous sera envoyé par email.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: null,
                    decoration: const InputDecoration(labelText: 'Nom et prénom (si nouveau compte)'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    // Deliberately off, same reasoning as every other field
                    // on this screen and the OTP field - see
                    // verify_email_screen.dart's class doc.
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
                        : const Text('Recevoir le code'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: widget.onContinueOffline,
                    child: const Text('Continuer hors connexion'),
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
