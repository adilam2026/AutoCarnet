import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/utils/connectivity.dart';
import '../../../core/widgets/loading_error_views.dart';
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
    final account = ref.read(accountRepositoryProvider);
    if (profileId == null) {
      // First-time setup on this device (bloc 7-9): a cloud account is the
      // primary path when reachable, but connectivity or the user's own
      // choice can never block using AutoCarnet locally (bloc 20).
      if (!account.isSignedIn && await hasConnectivity()) {
        setState(() => _step = _GateStep.accountAuth);
        return;
      }
      setState(() => _step = _GateStep.onboarding);
      return;
    }
    // The one thing PIN/biometric must never be able to do: silently
    // re-enter a cloud account whose Supabase session is gone (a real
    // sign-out, not just a relock). `lastCloudUserId` is non-null once
    // this device has *ever* completed a real cloud sign-in, and unlike
    // `isSignedIn` it survives that sign-out - so its mere presence
    // alongside a *missing* live session is exactly "was authenticated,
    // isn't anymore" and always routes back through email/OTP. A device
    // that has never had a cloud account at all (null) is unaffected:
    // PIN alone stays a legitimate unlock for it, same as before.
    final everLinked = await account.lastCloudUserId() != null;
    if (mustReauthenticateViaEmail(
      hasEverLinkedCloudAccount: everLinked,
      isSignedIn: account.isSignedIn,
    )) {
      setState(() => _step = _GateStep.accountAuth);
      return;
    }
    final pinService = ref.read(pinServiceProvider);
    // Scoped to the signed-in account (null for a device with no cloud
    // account at all) - see PinService.hasPinSetupBeenOffered: a
    // different account signing in later must still get its own offer.
    final accountId = account.isSignedIn ? account.currentUser!.id : null;
    final offered = await pinService.hasPinSetupBeenOffered(accountId: accountId);
    if (!offered) {
      setState(() => _step = _GateStep.pinSetup);
      return;
    }
    final pinSet = await pinService.isPinSet();
    setState(() => _step = pinSet ? _GateStep.locked : _GateStep.unlocked);
  }

  /// A cloud account was just created/confirmed, or the user signed back in
  /// - possibly on a new device, or possibly a *different* account than
  /// whichever last used this one. Three things need to happen, in order:
  /// reattribute any orphaned local data to whoever actually created it,
  /// remember this account as the current one, then seed/reuse the local
  /// profile - full data sync itself is a separate step, not part of this
  /// gate.
  Future<void> _onAccountAuthenticated() async {
    final account = ref.read(accountRepositoryProvider);
    final currentUserId = account.currentUser!.id;
    final previousUserId = await account.lastCloudUserId();
    if (previousUserId != null && previousUserId != currentUserId) {
      // A different cloud account just signed in on this same device than
      // last time - see each repository's handleAccountSwitch for exactly
      // what gets reattributed/cleared. Nothing is ever deleted.
      await ref.read(vehicleRepositoryProvider).handleAccountSwitch(previousUserId);
      await ref.read(providerRepositoryProvider).handleAccountSwitch(previousUserId);
      await ref.read(documentRepositoryProvider).handleAccountSwitch(previousUserId);
    }
    await account.rememberCloudUserId(currentUserId);

    final localRepo = ref.read(localProfileRepositoryProvider);
    final existing = await localRepo.getOrNull();
    if (existing == null) {
      final displayName =
          account.currentUser?.userMetadata?['display_name'] as String? ??
              account.currentUser?.email?.split('@').first ??
              'Utilisateur';
      await localRepo.create(displayName: displayName);
    }
    // Best-effort: lets collaborators see this account's name/email on a
    // shared vehicle's access screen. Never blocks sign-in if it fails
    // (e.g. offline) - it's retried on every future sign-in.
    unawaited(ref.read(sharingRepositoryProvider).ensureOwnEmailSynced());
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
        // A real account sign-out (Supabase session already closed by the
        // caller - see AccountRepository.signOut/signOutEverywhere) - the
        // local PIN/biometric unlock belonged to *this* account's
        // session and must never carry over silently to whoever
        // authenticates next on this device. Centralized here rather
        // than in each caller (settings screen, "changer de compte" on
        // the lock screen) so no future sign-out path can forget it.
        unawaited(ref.read(pinServiceProvider).clearPin());
        unawaited(ref.read(biometricServiceProvider).setEnabled(false));
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
          _GateStep.accountAuth => _GateNavigator(
              child: AccountGateScreen(
                onAuthenticated: _onAccountAuthenticated,
                onContinueOffline: () => setState(() => _step = _GateStep.onboarding),
              ),
            ),
          _GateStep.onboarding => _GateNavigator(
              child: OnboardingScreen(
                // The profile was just created; no need to wait for the
                // stream to catch up before moving to the next step.
                onDone: () => _evaluate('pending'),
              ),
            ),
          _GateStep.pinSetup => _GateNavigator(
              child: PinSetupScreen(
                onDone: () async {
                  final account = ref.read(accountRepositoryProvider);
                  final accountId = account.isSignedIn ? account.currentUser!.id : null;
                  await ref.read(pinServiceProvider).markPinSetupOffered(accountId: accountId);
                  // Straight into the app - re-locking immediately after the
                  // user just set (or skipped) the PIN would force them to
                  // re-type the code they only just entered.
                  setState(() => _step = _GateStep.unlocked);
                },
              ),
            ),
          _GateStep.locked => _GateNavigator(
              child: LockScreen(
                onUnlocked: () => setState(() => _step = _GateStep.unlocked),
              ),
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

/// Gives every pre-unlock screen (account auth, onboarding, PIN setup,
/// lock screen) its own real [Navigator] - and therefore its own
/// [Overlay].
///
/// [AppGate] sits in `MaterialApp.router`'s `builder`, one level *above*
/// the app's actual router: `widget.child` passed into [AppGate] already
/// *is* that router (with its own Navigator/Overlay inside), but every
/// branch here other than `unlocked` returns a screen built directly,
/// without `widget.child` anywhere in the tree - so until now, every
/// field on every pre-unlock screen rendered with zero Navigator/Overlay
/// ancestor anywhere above it, unlike literally every other screen in the
/// app (all reached through the router, which always provides one).
/// Missing Overlay ancestry is a known source of unreliable text-field/IME
/// behaviour in Flutter (selection handles, the composing-range UI, and
/// related low-level text-input plumbing all expect one) - and it lines
/// up exactly with what real-device testing showed: every field on these
/// screens misbehaved, while every field on every router-hosted business
/// screen (kilométrage included) never did.
class _GateNavigator extends StatelessWidget {
  const _GateNavigator({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => child),
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
