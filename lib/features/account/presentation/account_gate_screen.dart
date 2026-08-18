import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../data/account_repository.dart';

enum _Step {
  choice,
  phoneEntry,
  verifyPhone,
  emailChoice,
  signUp,
  verifyEmail,
  login,
  forgotEmail,
  forgotCode,
  forgotNewPassword,
}

/// A short, non-exhaustive list of country codes for the phone entry step
/// (RG - "le téléphone doit être saisi à partir d'un indicatif, jamais en
/// texte libre, pour éviter les numéros erronés"). Morocco first since it's
/// this app's home market (see the MAD default currency elsewhere).
const _countryCodes = <(String flag, String code, String label)>[
  ('🇲🇦', '+212', 'Maroc'),
  ('🇫🇷', '+33', 'France'),
  ('🇪🇸', '+34', 'Espagne'),
  ('🇩🇿', '+213', 'Algérie'),
  ('🇹🇳', '+216', 'Tunisie'),
  ('🇧🇪', '+32', 'Belgique'),
  ('🇨🇭', '+41', 'Suisse'),
  ('🇬🇧', '+44', 'Royaume-Uni'),
  ('🇩🇪', '+49', 'Allemagne'),
  ('🇮🇹', '+39', 'Italie'),
  ('🇳🇱', '+31', 'Pays-Bas'),
  ('🇺🇸', '+1', 'États-Unis/Canada'),
];

/// The account-first flow (bloc 7-9): create/verify a cloud account, or sign
/// back in on a new device. [onContinueOffline] is the escape hatch that
/// keeps AutoCarnet usable with no account and no connectivity (bloc 20 -
/// "attention à l'offline first", Principe 9) - it's always reachable, it's
/// never something the user has to fight the UI to find.
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
  _Step _step = _Step.choice;
  String? _error;
  bool _busy = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _newPasswordConfirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _countryCode = _countryCodes.first.$2;
  // The verified E.164 number for this session - fixed once the OTP step
  // starts, so a code sent to one number can never be typed in against a
  // different one.
  String? _verifyingPhone;

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  void _goTo(_Step step) => setState(() {
        _step = step;
        _error = null;
      });

  Future<void> _run(Future<void> Function() action, {required _Step onSuccess}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) _goTo(onSuccess);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSignUp() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Indiquez votre nom et prénom');
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 8 caractères');
      return;
    }
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.signUp(
        displayName: _nameCtrl.text,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      // If the project doesn't require email confirmation, signUp() already
      // returns a live session - there's no code to enter, so skip straight
      // to the app instead of showing a verify-email step that would just
      // wait forever for an email that was never sent.
      if (_repo.isSignedIn) {
        widget.onAuthenticated();
      } else {
        _goTo(_Step.verifyEmail);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPhoneEntry() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      setState(() => _error = 'Numéro de téléphone invalide');
      return;
    }
    // Local numbers are often typed with a leading trunk 0 (e.g. "0612345678")
    // which must be dropped for the E.164 form Supabase expects.
    final localDigits = digits.startsWith('0') ? digits.substring(1) : digits;
    final phone = '$_countryCode$localDigits';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.sendPhoneCode(phone, displayName: _nameCtrl.text);
      if (!mounted) return;
      _verifyingPhone = phone;
      _goTo(_Step.verifyPhone);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitVerifyPhone() async {
    if (_codeCtrl.text.trim().length < 6) {
      setState(() => _error = 'Le code contient 6 chiffres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.verifyPhoneCode(phone: _verifyingPhone!, code: _codeCtrl.text);
      if (mounted) widget.onAuthenticated();
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
      await _repo.confirmSignUp(email: _emailCtrl.text, code: _codeCtrl.text);
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitLogin() async {
    if (!_emailCtrl.text.contains('@') || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email ou mot de passe manquant');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.signInWithPassword(email: _emailCtrl.text, password: _passwordCtrl.text);
      if (!mounted) return;
      if (_repo.isEmailVerified) {
        widget.onAuthenticated();
      } else {
        // Account exists but was never confirmed - finish that step instead
        // of leaving the user stuck.
        _goTo(_Step.verifyEmail);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Une erreur est survenue : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitForgotEmail() async {
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    await _run(() => _repo.sendPasswordResetCode(_emailCtrl.text), onSuccess: _Step.forgotCode);
  }

  Future<void> _submitForgotCode() async {
    if (_codeCtrl.text.trim().length < 6) {
      setState(() => _error = 'Le code contient 6 chiffres');
      return;
    }
    await _run(
      () => _repo.verifyPasswordResetCode(email: _emailCtrl.text, code: _codeCtrl.text),
      onSuccess: _Step.forgotNewPassword,
    );
  }

  Future<void> _submitNewPassword() async {
    if (_newPasswordCtrl.text.length < 8) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 8 caractères');
      return;
    }
    if (_newPasswordCtrl.text != _newPasswordConfirmCtrl.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // verifyPasswordResetCode already opened a recovery session, so
      // updating the password leaves the user fully signed in.
      await _repo.updatePassword(_newPasswordCtrl.text);
      if (mounted) widget.onAuthenticated();
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
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    _newPasswordConfirmCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
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
      case _Step.choice:
        return _choiceContent(context);
      case _Step.phoneEntry:
        return _phoneEntryContent(context);
      case _Step.verifyPhone:
        return _verifyPhoneContent(context);
      case _Step.emailChoice:
        return _emailChoiceContent(context);
      case _Step.signUp:
        return _signUpContent(context);
      case _Step.verifyEmail:
        return _verifyEmailContent(context);
      case _Step.login:
        return _loginContent(context);
      case _Step.forgotEmail:
        return _forgotEmailContent(context);
      case _Step.forgotCode:
        return _forgotCodeContent(context);
      case _Step.forgotNewPassword:
        return _forgotNewPasswordContent(context);
    }
  }

  List<Widget> _choiceContent(BuildContext context) => [
        Icon(Icons.directions_car_filled, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Bienvenue sur AutoCarnet',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Connectez-vous avec votre numéro pour retrouver vos véhicules sur '
          'tous vos appareils, ou continuez sans connexion.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () => _goTo(_Step.phoneEntry),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Continuer avec WhatsApp'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => _goTo(_Step.emailChoice),
          child: const Text('Utiliser une adresse email à la place'),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          onPressed: widget.onContinueOffline,
          child: const Text('Continuer hors connexion'),
        ),
      ];

  List<Widget> _phoneEntryContent(BuildContext context) => [
        _BackButton(onPressed: () => _goTo(_Step.choice)),
        Icon(Icons.chat_bubble_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Continuer avec WhatsApp',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Un code de vérification à 6 chiffres vous sera envoyé par WhatsApp.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom et prénom (facultatif)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: _countryCode,
              items: _countryCodes
                  .map((c) => DropdownMenuItem(value: c.$2, child: Text('${c.$1} ${c.$2}')))
                  .toList(),
              onChanged: (v) => setState(() => _countryCode = v ?? _countryCode),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Numéro de téléphone'),
              ),
            ),
          ],
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Recevoir le code par WhatsApp', _busy ? null : _submitPhoneEntry),
      ];

  List<Widget> _verifyPhoneContent(BuildContext context) => [
        Icon(Icons.chat_bubble_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Vérifiez votre WhatsApp',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Un code à 6 chiffres a été envoyé à ${_verifyingPhone ?? ''} par WhatsApp.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(counterText: ''),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.sm),
        _submitButton('Vérifier', _busy ? null : _submitVerifyPhone),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: _busy || _verifyingPhone == null
              ? null
              : () => _run(
                    () => _repo.sendPhoneCode(_verifyingPhone!, displayName: _nameCtrl.text),
                    onSuccess: _Step.verifyPhone,
                  ),
          child: const Text('Renvoyer le code'),
        ),
      ];

  List<Widget> _emailChoiceContent(BuildContext context) => [
        _BackButton(onPressed: () => _goTo(_Step.choice)),
        Text('Compte par email', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: () => _goTo(_Step.signUp), child: const Text('Créer un compte')),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(onPressed: () => _goTo(_Step.login), child: const Text('Se connecter')),
      ];

  List<Widget> _signUpContent(BuildContext context) => [
        _BackButton(onPressed: () => _goTo(_Step.choice)),
        Text('Créer un compte', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nom et prénom'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Adresse email'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mot de passe (8 caractères min.)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Créer le compte', _busy ? null : _submitSignUp),
      ];

  List<Widget> _verifyEmailContent(BuildContext context) => [
        Icon(Icons.mark_email_read_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Vérifiez votre adresse email',
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
          keyboardType: TextInputType.number,
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
          onPressed: _busy
              ? null
              : () => _run(() => _repo.resendSignUpCode(_emailCtrl.text), onSuccess: _Step.verifyEmail),
          child: const Text('Renvoyer le code'),
        ),
      ];

  List<Widget> _loginContent(BuildContext context) => [
        _BackButton(onPressed: () => _goTo(_Step.choice)),
        Text('Se connecter', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Adresse email'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mot de passe'),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Se connecter', _busy ? null : _submitLogin),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => _goTo(_Step.forgotEmail),
          child: const Text('Mot de passe oublié ?'),
        ),
      ];

  List<Widget> _forgotEmailContent(BuildContext context) => [
        _BackButton(onPressed: () => _goTo(_Step.login)),
        Text('Mot de passe oublié', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Indiquez votre adresse email, un code de vérification vous sera envoyé.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Adresse email'),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Envoyer le code', _busy ? null : _submitForgotEmail),
      ];

  List<Widget> _forgotCodeContent(BuildContext context) => [
        Text('Code de vérification', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Un code à 6 chiffres a été envoyé à ${_emailCtrl.text}.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: const InputDecoration(counterText: ''),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Vérifier', _busy ? null : _submitForgotCode),
      ];

  List<Widget> _forgotNewPasswordContent(BuildContext context) => [
        Text('Nouveau mot de passe', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _newPasswordConfirmCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
        ),
        _errorText(context),
        const SizedBox(height: AppSpacing.md),
        _submitButton('Enregistrer', _busy ? null : _submitNewPassword),
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

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }
}
