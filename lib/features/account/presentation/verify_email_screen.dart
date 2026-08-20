import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

/// Second step of the account-first flow: enter the 6-digit code that was
/// just emailed. Deliberately the plainest possible Flutter text field -
/// the same technical philosophy as the mileage field elsewhere in the app
/// (see MileageUpdateSheet): one [TextEditingController] owned by this
/// screen, a native numeric keyboard, no OTP library, no autofill hint, no
/// SMS auto-retriever, no secondary state mirroring the typed value. Prior
/// attempts here used a hand-rolled multi-step widget and later the Pinput
/// package - both showed the same real-device symptom (deleted characters
/// reappearing while retyping), so this deliberately drops every layer
/// that isn't the bare minimum: "Vérifier" reads `_codeCtrl.text` exactly
/// once, at the moment it's pressed, and nothing else ever writes into
/// this controller.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.onAuthenticated,
    required this.onBack,
  });

  final String email;
  final String displayName;
  final AsyncCallback onAuthenticated;
  final VoidCallback onBack;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _codeCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _codeCtrl.text.trim();
    if (value.length < 6) {
      setState(() => _error = 'Le code contient 6 chiffres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).verifyEmailCode(email: widget.email, code: value);
      if (!mounted) return;
      // `onAuthenticated` finishes the post-auth chain (creating the
      // local profile, deciding PIN/onboarding, swapping this screen
      // out) - it must be awaited and the button must stay disabled
      // throughout. A code is single-use: if this screen were still
      // showing (even for a moment) with a re-enabled button, a second
      // tap would resend the *same* already-consumed code and Supabase
      // would correctly - but confusingly - reject it as expired/
      // invalid, even though the first attempt had already succeeded.
      await widget.onAuthenticated();
      // No `finally` re-enabling _busy here on purpose: this screen is
      // being replaced right now, and must never flash back to an
      // interactive state in between.
      return;
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    } catch (_) {
      if (mounted) {
        setState(() { _error = 'Une erreur est survenue. Réessayez.'; _busy = false; });
      }
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref
          .read(accountRepositoryProvider)
          .sendEmailCode(widget.email, displayName: widget.displayName);
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// A short resend cooldown - purely to stop accidental double-taps from
  /// spamming the inbox, never a security control.
  void _startCooldown() {
    setState(() => _resendCooldown = 30);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : widget.onBack,
        ),
      ),
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
                  Icon(Icons.mark_email_read_outlined, size: 56, color: scheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Vérifiez votre email',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Un code à 6 chiffres a été envoyé à ${widget.email}.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _codeCtrl,
                    autofocus: true,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    // Deliberately off - see class doc. Flutter's own
                    // default for this parameter is `const []`, which
                    // still builds a real (generic, hint-less)
                    // AutofillConfiguration; only an explicit `null`
                    // fully disables it.
                    autofillHints: null,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Code de vérification',
                      counterText: '',
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Vérifier'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: (_resending || _resendCooldown > 0) ? null : _resend,
                    child: Text(_resendCooldown > 0
                        ? 'Renvoyer le code (${_resendCooldown}s)'
                        : 'Renvoyer le code'),
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
