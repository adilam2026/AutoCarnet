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
        // Mission 2026 diagnostic pass: this branch only ever runs for
        // something Supabase's own auth client did NOT wrap into an
        // AuthException (see authErrorMessage's doc - a real network
        // failure normally already comes back as AuthRetryableFetchException/
        // AuthUnknownException, caught above with a friendly message) - so
        // whatever lands here is unexpected by definition. Showing the raw
        // exception too (not just logging it) is deliberate for this
        // TEST-APK cycle: without device log access, this is the only way
        // to get the real cause instead of guessing at it again.
        setState(() { _error = 'Une erreur est survenue : $e'; _busy = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // V2.1 login pass (validated design-review): a compact petrol
              // hero carrying a real automotive identity (an abstract mark,
              // deliberately never an emoji or a cartoon car) - not the
              // earlier oversized flat colour block with no brand presence.
              Container(
                width: double.infinity,
                color: scheme.primary,
                padding: const EdgeInsets.fromLTRB(28, 30, 28, 52),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                      ),
                      child: const Icon(Icons.speed_rounded, size: 24, color: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'AUTOCARNET',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Votre voiture. Son histoire.\nToujours avec vous.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        'Entretiens, dépenses, documents et échéances réunis dans un seul carnet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              // The card floats up over the hero/background boundary
              // (negative top margin) for real depth, and stays genuinely
              // compact - never a near-full-screen sheet.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -32),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: scheme.outlineVariant),
                          boxShadow: AppElevation.raised(scheme),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Accéder à AutoCarnet',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 16),
                            Text(
                              'ADRESSE EMAIL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: scheme.outline,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('email-field'),
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: null,
                              decoration: const InputDecoration(
                                hintText: 'vous@exemple.com',
                                isDense: true,
                              ),
                              onSubmitted: (_) {
                                if (!_busy) _submit();
                              },
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(_error!, style: TextStyle(color: scheme.error)),
                            ],
                            const SizedBox(height: 14),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Continuer'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Un code de vérification vous sera envoyé par email.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11.5, color: scheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -12),
                      child: Column(
                        children: [
                          Text(
                            'Vos données restent privées et sécurisées.',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ReassuranceBadge(icon: Icons.lock_outline, label: 'Sans mot de passe'),
                              const SizedBox(width: 18),
                              _ReassuranceBadge(icon: Icons.sync, label: 'Synchronisé'),
                              const SizedBox(width: 18),
                              _ReassuranceBadge(icon: Icons.shield_outlined, label: 'Sécurisé'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReassuranceBadge extends StatelessWidget {
  const _ReassuranceBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 15, color: scheme.outline),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: scheme.outline)),
      ],
    );
  }
}
