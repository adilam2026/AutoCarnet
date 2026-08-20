import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

/// Second step of the account-first flow: enter the 6-digit code that was
/// just emailed. The digit boxes themselves are [Pinput] - a real,
/// battle-tested TextField under the hood, driven entirely by the device's
/// own native keyboard - rather than a hand-rolled TextField with its own
/// bespoke autofill/formatter configuration. `autofillHints` is explicitly
/// disabled (pinput otherwise defaults to `[AutofillHints.oneTimeCode]`,
/// which real-device testing showed can silently block manual typing on
/// some keyboards) and no [Pinput.smsRetriever] is wired in, so nothing
/// ever writes into this field except the user's own keystrokes.
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
  final VoidCallback onAuthenticated;
  final VoidCallback onBack;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _codeCtrl = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;
  bool _busy = false;
  bool _resending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _focusNode.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit([String? code]) async {
    final value = (code ?? _codeCtrl.text).trim();
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
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        _codeCtrl.clear();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Une erreur est survenue. Réessayez.');
        _codeCtrl.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: Theme.of(context).textTheme.headlineSmall,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: scheme.primary, width: 2),
      ),
    );
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: scheme.error, width: 2),
      ),
    );

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
                  Center(
                    child: Pinput(
                      length: 6,
                      controller: _codeCtrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      enabled: !_busy,
                      defaultPinTheme: defaultPinTheme,
                      focusedPinTheme: focusedPinTheme,
                      errorPinTheme: errorPinTheme,
                      forceErrorState: _error != null,
                      keyboardType: TextInputType.number,
                      // Pinput defaults to [AutofillHints.oneTimeCode] -
                      // explicitly off here, see class doc.
                      autofillHints: null,
                      showCursor: true,
                      onCompleted: _submit,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(),
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
