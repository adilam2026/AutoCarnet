import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/utils/connectivity.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../account/data/account_repository.dart';
import '../../account/presentation/account_gate_screen.dart';
import '../data/local_profile_repository.dart';
import '../data/pin_service.dart';
import 'lock_screen.dart';
import 'onboarding_screen.dart';
import 'pin_setup_screen.dart';

enum _GateStep { loading, accountAuth, onboarding, pinSetup, locked, unlocked }

/// Bumped by "Se déconnecter" (Compte & sécurité) to force the app back to
/// its lock screen on this device - reverifies the local PIN only,
/// the cloud account session (if any) is left untouched. Local data is
/// never touched either way.
final sessionLockRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped by "Se déconnecter du compte" (bloc 6/9): the Supabase session
/// itself is closed first (see AccountRepository.signOut/signOutEverywhere),
/// then this sends the gate back to account authentication rather than just
/// the local PIN screen. Local data is never touched.
final accountSignOutRequestProvider = StateProvider<int>((ref) => 0);

/// Root gatekeeper: onboarding (first launch) -> optional PIN setup ->
/// PIN lock on every subsequent launch -> the actual app. Wraps
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
      // First-time setup on this device (bloc 7-9): a cloud account is the
      // primary path when reachable, but connectivity or the user's own
      // choice can never block using AutoCarnet locally (bloc 20).
      final alreadySignedIn = ref.read(accountRepositoryProvider).isSignedIn;
      if (!alreadySignedIn && await hasConnectivity()) {
        setState(() => _step = _GateStep.accountAuth);
        return;
      }
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

  /// A cloud account was just created/confirmed, or the user signed back in
  /// on a new device - seed a local profile from it if this device doesn't
  /// have one yet, so the rest of the app (currency, display name...) works
  /// exactly as it already does for a local-only user. Full data sync is a
  /// separate step, not part of this gate.
  Future<void> _onAccountAuthenticated() async {
    final localRepo = ref.read(localProfileRepositoryProvider);
    final existing = await localRepo.getOrNull();
    if (existing == null) {
      final account = ref.read(accountRepositoryProvider);
      final displayName =
          account.currentUser?.userMetadata?['display_name'] as String? ??
              account.currentUser?.email?.split('@').first ??
              'Utilisateur';
      await localRepo.create(displayName: displayName);
    }
    await _evaluate('pending');
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(localProfileProvider);

    ref.listen<int>(sessionLockRequestProvider, (previous, next) {
      if (previous != null && next != previous) {
        _evaluate(profileAsync.valueOrNull?.id);
      }
    });
    ref.listen<int>(accountSignOutRequestProvider, (previous, next) {
      if (previous != null && next != previous) {
        setState(() => _step = _GateStep.accountAuth);
      }
    });

    return profileAsync.when(
      loading: () => const _Splash(),
      error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
      data: (profile) {
        if (_step == _GateStep.loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _evaluate(profile?.id);
          });
          return const _Splash();
        }
        return switch (_step) {
          _GateStep.loading => const _Splash(),
          _GateStep.accountAuth => AccountGateScreen(
              onAuthenticated: _onAccountAuthenticated,
              onContinueOffline: () => setState(() => _step = _GateStep.onboarding),
            ),
          _GateStep.onboarding => OnboardingScreen(
              // The profile was just created; no need to wait for the
              // stream to catch up before moving to the next step.
              onDone: () => _evaluate('pending'),
            ),
          _GateStep.pinSetup => PinSetupScreen(
              onDone: () async {
                await ref.read(pinServiceProvider).markPinSetupOffered();
                // Straight into the app - re-locking immediately after the
                // user just set (or skipped) the PIN would force them to
                // re-type the code they only just entered.
                setState(() => _step = _GateStep.unlocked);
              },
            ),
          _GateStep.locked => LockScreen(
              onUnlocked: () => setState(() => _step = _GateStep.unlocked),
            ),
          _GateStep.unlocked => _UnlockedApp(child: widget.child),
        };
      },
    );
  }
}

/// Starts the cloud sync coordinator exactly once per app-unlocked session
/// (the very moment collaboration data could matter), never before the
/// gate settles - starting it during onboarding/auth would just mean every
/// pass no-ops until a session exists, so this simply avoids the churn.
class _UnlockedApp extends ConsumerStatefulWidget {
  const _UnlockedApp({required this.child});
  final Widget child;

  @override
  ConsumerState<_UnlockedApp> createState() => _UnlockedAppState();
}

class _UnlockedAppState extends ConsumerState<_UnlockedApp> {
  @override
  void initState() {
    super.initState();
    ref.read(syncCoordinatorProvider).start();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.directions_car_filled,
            size: 32,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
