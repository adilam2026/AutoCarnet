import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_profile_repository.dart';
import '../data/pin_service.dart';
import 'lock_screen.dart';
import 'onboarding_screen.dart';
import 'pin_setup_screen.dart';

enum _GateStep { loading, onboarding, pinSetup, locked, unlocked }

/// Root gatekeeper: onboarding (first launch) -> optional PIN setup ->
/// PIN/biometric lock on every subsequent launch -> the actual app. Wraps
/// the router as MaterialApp.router's `builder` so navigation state is
/// untouched by the lock flow.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  _GateStep _step = _GateStep.loading;

  Future<void> _evaluate(String? profileId) async {
    if (profileId == null) {
      setState(() => _step = _GateStep.onboarding);
      return;
    }
    final pinService = ref.read(pinServiceProvider);
    final offered = await pinService.hasPinSetupBeenOffered();
    if (!offered) {
      setState(() => _step = _GateStep.pinSetup);
      return;
    }
    final pinSet = await pinService.isPinSet();
    setState(() => _step = pinSet ? _GateStep.locked : _GateStep.unlocked);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(localProfileProvider);

    return profileAsync.when(
      loading: () => const _Splash(),
      error: (e, _) => Scaffold(body: Center(child: Text('Erreur : $e'))),
      data: (profile) {
        if (_step == _GateStep.loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _evaluate(profile?.id);
          });
          return const _Splash();
        }
        return switch (_step) {
          _GateStep.loading => const _Splash(),
          _GateStep.onboarding => OnboardingScreen(
              // The profile was just created; no need to wait for the
              // stream to catch up before moving to the next step.
              onDone: () => _evaluate('pending'),
            ),
          _GateStep.pinSetup => PinSetupScreen(
              onDone: () async {
                await ref.read(pinServiceProvider).markPinSetupOffered();
                await _evaluate('pending');
              },
            ),
          _GateStep.locked => LockScreen(
              onUnlocked: () => setState(() => _step = _GateStep.unlocked),
            ),
          _GateStep.unlocked => widget.child,
        };
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
