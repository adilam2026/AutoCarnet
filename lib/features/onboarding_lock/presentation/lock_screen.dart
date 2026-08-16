import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/pin_service.dart';

/// RG-USER-003/004: local unlock only. After repeated failures the retry
/// delay grows (bloc 2 §5.6 "temporisation progressive") instead of
/// permanently locking the user out.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pinCtrl = TextEditingController();
  String? _error;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _tryBiometricAtStart();
  }

  Future<void> _tryBiometricAtStart() async {
    final service = ref.read(pinServiceProvider);
    if (await service.isBiometricEnabled()) {
      final ok = await service.authenticateWithBiometrics();
      if (ok && mounted) widget.onUnlocked();
    }
  }

  Future<void> _submit() async {
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) return;
    setState(() => _checking = true);
    final ok = await ref.read(pinServiceProvider).verifyPin(_pinCtrl.text.trim());
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _failedAttempts++;
      _pinCtrl.clear();
      if (_failedAttempts >= 3) {
        final seconds = 5 * (_failedAttempts - 2);
        _lockedUntil = DateTime.now().add(Duration(seconds: seconds));
        _error = 'Trop de tentatives. Réessayez dans $seconds s.';
      } else {
        _error = 'Code incorrect';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
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
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    enabled: !locked,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: 'Code'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: (_checking || locked) ? null : _submit,
                    child: const Text('Déverrouiller'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await ref
                          .read(pinServiceProvider)
                          .authenticateWithBiometrics();
                      if (ok) widget.onUnlocked();
                    },
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Utiliser la biométrie'),
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
