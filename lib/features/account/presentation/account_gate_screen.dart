import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

enum _Step { emailEntry, verifyEmail }

/// The account-first flow (bloc 7-9): create/sign back into a cloud account
/// with just an email address and a 6-digit code - no password anywhere.
/// [onContinueOffline] is the escape hatch that keeps AutoCarnet usable with
/// no account and no connectivity (bloc 20 - "attention à l'offline first",
/// Principe 9) - it's always reachable, it's never something the user has
/// to fight the UI to find.
class AccountGateScreen extends ConsumerStatefulWidget {
  const AccountGateScreen({
    super.key,
    required this.onAuthenticated,
    required this.onContinueOffline,
  });

  final VoidCallback onAuthenticated;
  final VoidCallback onContinueOffline;

  @override
  ConsumerState<AccountGateScreen> createState() => _AccountGateScreenState();
}

class _AccountGateScreenState extends ConsumerState<AccountGateScreen> {
  _Step _step = _Step.emailEntry;
  String? _error;
  bool _busy = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  // --- TEMPORARY DIAGNOSTIC BUILD - remove once the real cause is found ---
  final _codeFocus = FocusNode();
  final _diagCtrl = TextEditingController();
  int _onChangedCount = 0;
  int _buildCount = 0;
  String _lastOnChanged = '(jamais appelé)';

  @override
  void initState() {
    super.initState();
    _codeFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }
  // --- END TEMPORARY DIAGNOSTIC BUILD additions in initState ---

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  void _goTo(_Step step) => setState(() {
        _step = step;
        _error = null;
      });

  Future<void> _submitEmailEntry() async {
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.sendEmailCode(_emailCtrl.text, displayName: _nameCtrl.text);
      if (mounted) _goTo(_Step.verifyEmail);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitVerifyEmail() async {
    if (_codeCtrl.text.trim().length < 6) {
      setState(() => _error = 'Le code contient 6 chiffres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.verifyEmailCode(email: _emailCtrl.text, code: _codeCtrl.text);
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.sendEmailCode(_emailCtrl.text, displayName: _nameCtrl.text);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose(); // TEMPORARY DIAGNOSTIC BUILD
    _diagCtrl.dispose(); // TEMPORARY DIAGNOSTIC BUILD
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++; // TEMPORARY DIAGNOSTIC BUILD
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
                children: _content(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    switch (_step) {
      case _Step.emailEntry:
        return _emailEntryContent(context);
      case _Step.verifyEmail:
        return _verifyEmailContent(context);
    }
  }

  List<Widget> _emailEntryContent(BuildContext context) => [
        Icon(Icons.directions_car_filled, size: 72, color: Theme.of(context).colorScheme.primary),
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
          decoration: const InputDecoration(labelText: 'Nom et prénom (si nouveau compte)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Adresse email'),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Recevoir le code', _busy ? null : _submitEmailEntry),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: widget.onContinueOffline,
          child: const Text('Continuer hors connexion'),
        ),
      ];

  List<Widget> _verifyEmailContent(BuildContext context) => [
        Icon(Icons.mark_email_read_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Vérifiez votre email',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Un code à 6 chiffres a été envoyé à ${_emailCtrl.text}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _codeCtrl,
          focusNode: _codeFocus, // TEMPORARY DIAGNOSTIC BUILD
          onChanged: (v) {
            // TEMPORARY DIAGNOSTIC BUILD - purely observational, never
            // writes back to the controller.
            setState(() {
              _onChangedCount++;
              _lastOnChanged = v;
            });
          },
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: null,
          enableSuggestions: false,
          autocorrect: false,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(counterText: ''),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.sm),
        _submitButton('Vérifier', _busy ? null : _submitVerifyEmail),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _busy ? null : _resendCode,
          child: const Text('Renvoyer le code'),
        ),
        // ============================================================
        // TEMPORARY DIAGNOSTIC PANEL - remove once the cause is found.
        // ============================================================
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            border: Border.all(color: Colors.amber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('DIAGNOSTIC TEMPORAIRE', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('build #$_buildCount'),
              Text('focus champ OTP: ${_codeFocus.hasFocus} '
                  '(canRequestFocus: ${_codeFocus.canRequestFocus})'),
              Text('onChanged appelé: $_onChangedCount fois, dernière valeur reçue: '
                  '"$_lastOnChanged"'),
              Text('controller.text ACTUEL: "${_codeCtrl.text}"'),
              Text('controller.selection: ${_codeCtrl.selection}'),
              const SizedBox(height: AppSpacing.sm),
              const Text('Champ de test minimal et indépendant '
                  '(nouveau controller, aucun lien avec le champ OTP ci-dessus) :'),
              const SizedBox(height: 4),
              TextField(
                controller: _diagCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Champ minimal',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Text('champ minimal - valeur actuelle: "${_diagCtrl.text}"'),
            ],
          ),
        ),
      ];

  Widget _errorText(BuildContext context) {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }

  Widget _submitButton(String label, VoidCallback? onPressed) {
    return FilledButton(
      onPressed: onPressed,
      child: _busy
          ? const SizedBox(
              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}
