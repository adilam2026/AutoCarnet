import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../account/data/account_repository.dart';
import '../../account/presentation/account_gate_screen.dart';
import '../../documents/data/document_repository.dart';
import '../../providers/data/provider_repository.dart';
import '../../sharing/data/sharing_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/biometric_service.dart';
import '../data/local_profile_repository.dart';
import '../data/pin_service.dart';
import '../domain/gate_decision.dart';
import 'lock_screen.dart';
import 'pin_recovery_screen.dart';
import 'pin_setup_screen.dart';

enum _GateStep { loading, email, pinSetup, locked, pinRecovery, unlocked }

/// Bumped by "Verrouiller" (Compte & sécurité): purely local, reverifies
/// the PIN only - the cloud account session is left completely untouched
/// and local data is never touched either (spec bloc 1's VERROUILLAGE
/// LOCAL, spec bloc 7).
final sessionLockRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped by "Changer de compte" (LockScreen or Compte & sécurité): closes
/// the Supabase session on this device and clears this device's
/// authorization, so the very next email typed always requires a fresh OTP
/// - even the same address (spec bloc 11/15).
final accountSwitchRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped by "Déconnecter tous les appareils" (Compte & sécurité): the same
/// as [accountSwitchRequestProvider], but also revokes every other device's
/// session for this account (spec bloc 6).
final accountDisconnectEverywhereRequestProvider = StateProvider<int>((ref) => 0);

/// Root gatekeeper and the *only* place in the app that decides which of
/// email / PIN-setup / locked / PIN-recovery / the real app is shown (spec
/// bloc 19: one central state machine, no concurrent decision-makers).
/// Wraps the router as MaterialApp.router's `builder` so navigation state
/// is untouched by the lock flow.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> {
  _GateStep _step = _GateStep.loading;
  String? _lockedEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  /// The single function that decides which screen this device shows right
  /// now (spec bloc 19). Called exactly at three kinds of moment: app
  /// start, right after a fresh OTP success, and right after a revocation
  /// is discovered - never on every rebuild, and never raced against
  /// another listener deciding something else.
  Future<void> _evaluate() async {
    final account = ref.read(accountRepositoryProvider);
    final deviceUserId = await account.deviceAuthorizedUserId();
    var authorized = deviceUserId != null &&
        account.isSignedIn &&
        account.currentUser?.id == deviceUserId;
    if (authorized) {
      // Best-effort, online-only: has the account owner revoked this exact
      // device from "Appareils connectés" since it last checked in? Never
      // blocks offline use - see AccountRepository.isDeviceStillAuthorized.
      final stillAuthorized = await account.isDeviceStillAuthorized(userId: deviceUserId);
      if (!stillAuthorized) {
        await account.disconnectFromThisDevice();
        authorized = false;
      }
    }
    final pinSet = authorized ? await ref.read(pinServiceProvider).isPinSet() : false;
    final email = authorized ? await account.deviceAuthorizedEmail() : null;
    final state = resolveGateState(deviceAuthorized: authorized, pinSet: pinSet);
    if (!mounted) return;
    setState(() {
      _lockedEmail = email;
      _step = switch (state) {
        GateState.email => _GateStep.email,
        GateState.pinSetup => _GateStep.pinSetup,
        GateState.locked => _GateStep.locked,
      };
    });
  }

  /// A cloud account was just created/confirmed via email/OTP - possibly a
  /// brand new device for an existing account, possibly a *different*
  /// account than whichever last used this one. Reattributes any orphaned
  /// local data to whoever actually created it, registers this device as
  /// authorized, then seeds/reuses the local profile - nothing is ever
  /// deleted. Always leads to PIN setup next (spec bloc 3/19: OTP success
  /// never skips straight to HOME).
  Future<void> _onAccountAuthenticated() async {
    final account = ref.read(accountRepositoryProvider);
    final currentUserId = account.currentUser!.id;
    // Deliberately `lastDeviceUserId`, not `deviceAuthorizedUserId`: a
    // "Changer de compte" already cleared the latter (see _disconnect)
    // before this device ever reaches the email screen again, so it would
    // always read null here and this reattribution would never fire for
    // the exact case it exists for. `lastDeviceUserId` survives that
    // clear - see AccountRepository's doc for why.
    final previousDeviceUserId = await account.lastDeviceUserId();
    if (previousDeviceUserId != null && previousDeviceUserId != currentUserId) {
      await ref.read(vehicleRepositoryProvider).handleAccountSwitch(previousDeviceUserId);
      await ref.read(providerRepositoryProvider).handleAccountSwitch(previousDeviceUserId);
      await ref.read(documentRepositoryProvider).handleAccountSwitch(previousDeviceUserId);
      await ref.read(localProfileRepositoryProvider).handleAccountSwitch(previousDeviceUserId);
    }
    await account.registerThisDevice();

    final localRepo = ref.read(localProfileRepositoryProvider);
    final existing = await localRepo.getOrNull(currentUserId: currentUserId);
    if (existing == null) {
      final displayName = account.currentUser?.email?.split('@').first ?? 'Utilisateur';
      await localRepo.create(displayName: displayName, ownerId: currentUserId);
    } else if (existing.ownerId == null) {
      await localRepo.claimOwnership(existing.id, currentUserId);
    }
    // Best-effort: lets collaborators see this account's name/email on a
    // shared vehicle's access screen. Never blocks sign-in if it fails
    // (e.g. offline) - it's retried on every future sign-in.
    unawaited(ref.read(sharingRepositoryProvider).ensureOwnEmailSynced());
    await _evaluate();
  }

  /// Signs out of Supabase and clears this device's authorization (spec
  /// bloc 11/15), then lands back on the email screen. The state flip
  /// happens *first*, synchronously - before any async Supabase/storage
  /// call - so there is never a frame where business screens are still
  /// mounted next to a session/profile that's already gone (the exact bug
  /// this replaces: the old flow signed out *then* changed screens,
  /// leaving a window where the avatar could show "?" while vehicles were
  /// still on screen).
  Future<void> _disconnect({required bool everywhere}) async {
    setState(() => _step = _GateStep.email);
    final account = ref.read(accountRepositoryProvider);
    if (everywhere) {
      await account.disconnectFromAllDevices();
    } else {
      await account.disconnectFromThisDevice();
    }
    await ref.read(pinServiceProvider).clearPin();
    await ref.read(biometricServiceProvider).setEnabled(false);
  }

  /// The only way `_step` ever becomes [_GateStep.unlocked] - always forces
  /// the router back to the home route first (spec bloc 9: never restore an
  /// old vehicle/profile/form screen after PIN setup, unlock, or PIN
  /// recovery - every arrival into the app starts at ACCUEIL).
  void _goUnlocked() {
    ref.read(appRouterProvider).go('/');
    setState(() => _step = _GateStep.unlocked);
  }

  /// What a correct PIN (or successful biometric) actually triggers - not
  /// [_goUnlocked] directly, so a revocation from another device is caught
  /// the moment someone next tries to get back in, not only on the next
  /// cold start (spec bloc 14/20 scenario I). Still best-effort/fail-open
  /// (see AccountRepository.isDeviceStillAuthorized): offline, this always
  /// unlocks exactly as before.
  Future<void> _onPinAccepted() async {
    final account = ref.read(accountRepositoryProvider);
    final userId = await account.deviceAuthorizedUserId();
    if (userId != null && !await account.isDeviceStillAuthorized(userId: userId)) {
      await account.disconnectFromThisDevice();
      await ref.read(pinServiceProvider).clearPin();
      await ref.read(biometricServiceProvider).setEnabled(false);
      if (mounted) setState(() => _step = _GateStep.email);
      return;
    }
    _goUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(sessionLockRequestProvider, (previous, next) {
      if (previous != null && next != previous) {
        // Safe to flip synchronously and unconditionally: `unlocked` can
        // only ever be reached with a PIN already set (see _goUnlocked),
        // so a locked screen is always valid to fall back to here.
        setState(() => _step = _GateStep.locked);
      }
    });
    ref.listen<int>(accountSwitchRequestProvider, (previous, next) {
      if (previous != null && next != previous) unawaited(_disconnect(everywhere: false));
    });
    ref.listen<int>(accountDisconnectEverywhereRequestProvider, (previous, next) {
      if (previous != null && next != previous) unawaited(_disconnect(everywhere: true));
    });

    return switch (_step) {
      _GateStep.loading => const _Splash(),
      _GateStep.email => _GateNavigator(
          child: AccountGateScreen(onAuthenticated: _onAccountAuthenticated),
        ),
      _GateStep.pinSetup => _GateNavigator(
          child: PinSetupScreen(onDone: _goUnlocked),
        ),
      _GateStep.locked => _GateNavigator(
          child: LockScreen(
            email: _lockedEmail,
            onUnlocked: _onPinAccepted,
            onForgotCode: () => setState(() => _step = _GateStep.pinRecovery),
            onSwitchAccount: () => ref.read(accountSwitchRequestProvider.notifier).state++,
          ),
        ),
      _GateStep.pinRecovery => _GateNavigator(
          child: PinRecoveryScreen(
            email: _lockedEmail ?? '',
            onDone: _goUnlocked,
            onCancel: () => setState(() => _step = _GateStep.locked),
          ),
        ),
      _GateStep.unlocked => _UnlockedApp(child: widget.child),
    };
  }
}

/// Starts the cloud sync coordinator exactly once per app-unlocked session
/// (the very moment collaboration data could matter), never before the
/// gate settles - starting it during email/PIN screens would just mean
/// every pass no-ops until a session exists, so this simply avoids the
/// churn.
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

/// Gives every pre-unlock screen (email/OTP, PIN setup, lock, PIN recovery)
/// its own real [Navigator] - and therefore its own [Overlay], which
/// several low-level text-input behaviours (selection handles, the
/// composing-range UI) depend on - plus a [PopScope] that refuses to pop:
/// since [AppGate] only ever mounts *one* of these branches or the real
/// app at a time (never both), there is nothing to reveal underneath, but
/// this is a deliberate second guarantee (spec bloc 8/21) that the Android
/// back button can never be used to slip past a pre-unlock screen.
class _GateNavigator extends StatelessWidget {
  const _GateNavigator({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => child),
      ),
    );
  }
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
