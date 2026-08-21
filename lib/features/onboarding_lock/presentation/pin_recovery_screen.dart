import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/data/account_repository.dart';
import 'pin_setup_screen.dart';

/// "Code d'accès oublié ?" (spec bloc 10): an OTP to the account's *already
/// known* email - no email re-entry, since this device already remembers
/// which account it's authorized for - followed by a mandatory new PIN.
/// Requiring OTP here (rather than just letting anyone tap "oublié" and set
/// a fresh PIN) is what keeps the local PIN a real security control even if
/// someone has physical access to an already-signed-in phone: without it,
/// "forgot code" would be a total bypass.
class PinRecoveryScreen extends ConsumerStatefulWidget {
  const PinRecoveryScreen({
    super.key,
    required this.accountId,
    required this.email,
    required this.onDone,
    required this.onCancel,
  });

  /// Whose PIN gets replaced - passed straight through to the nested
  /// [PinSetupScreen] so the new code is stored under the right account
  /// (spec TEST F).
  final String accountId;
  final String email;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  ConsumerState<PinRecoveryScreen> createState() => _PinRecoveryScreenState();
}

class _PinRecoveryScreenState extends ConsumerState<PinRecoveryScreen> {
  final _codeCtrl = TextEditingController();
  bool _otpVerified = false;
  bool _sending = true;
  bool _busy = false;
  String? _error;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).sendEmailCode(widget.email);
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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

  Future<void> _verify() async {
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
      await ref
          .read(accountRepositoryProvider)
          .verifyEmailCode(email: widget.email, code: value);
      if (mounted) setState(() => _otpVerified = true);
    } on AuthException catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    } catch (_) {
      if (mounted) {
        setState(() { _error = 'Une erreur est survenue. Réessayez.'; _busy = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_otpVerified) {
      // A fresh PIN is mandatory here too (PinSetupScreen has no skip
      // option) - "code oublié" must always end with a real new code, never
      // silently leave the device unprotected.
      return PinSetupScreen(accountId: widget.accountId, onDone: widget.onDone);
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : widget.onCancel,
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
                  Text('Confirmez votre identité',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Un code à 6 chiffres a été envoyé à ${widget.email} pour '
                    'réinitialiser votre code d\'accès sur cet appareil.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _codeCtrl,
                    autofocus: true,
                    enabled: !_busy && !_sending,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofillHints: null,
                    enableSuggestions: false,
                    autocorrect: false,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(labelText: 'Code de vérification', counterText: ''),
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
                    onPressed: (_busy || _sending) ? null : _verify,
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Vérifier'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: (_sending || _resendCooldown > 0) ? null : _sendCode,
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
