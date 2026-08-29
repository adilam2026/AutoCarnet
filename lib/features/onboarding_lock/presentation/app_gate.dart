import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Bumped by "Changer de compte" (LockScreen or Compte & sécurité): pure
/// navigation to the email screen - nothing is forgotten. Whichever email
/// is typed next resolves on its own (spec CAS 1/2/3): an account already
/// known on this device switches straight to its own PIN with no OTP, a
/// genuinely new one goes through email/OTP as usual. Deliberately does
/// *not* disconnect anything - a device can know several already-
/// authorized accounts at once (spec: "changer de compte n'est pas
/// forcément nouvel appareil").
final accountSwitchRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped by "Dissocier ce compte de cet appareil" (Compte & sécurité):
/// the real, deliberate action that makes the *currently active* account
/// require a fresh OTP again on this device - even re-entering this exact
/// same email (spec bloc 15's "RÉVOQUER/DISSOCIER"). Other accounts this
/// device also knows are never affected.
final accountDissociateRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped by "Déconnecter tous les appareils" (Compte & sécurité): the same
/// local effect as [accountDissociateRequestProvider] for the currently
/// active account, but also revokes every other device's session for it
/// (spec bloc 6).
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

  /// Whose PIN/biometric the current pre-HOME screen (pinSetup/locked/
  /// pinRecovery) is about - always non-null whenever `_step` is one of
  /// those three (see resolveGateState: they're only reached when
  /// `deviceAuthorized` is true, which is exactly when this gets set).
  String? _activeAccountId;

  /// Bound on each individual local read (secure storage) that decides the
  /// very first screen. Local reads should complete in milliseconds; this
  /// is a hard ceiling, not a realistic expectation - see [_bounded].
  static const _localStepTimeout = Duration(seconds: 4);

  /// Bound on the background, online-only device-authorization check - see
  /// [_reconcileDeviceAuthorization]. Generous because it's never on the
  /// critical path to a visible screen any more.
  static const _backgroundCheckTimeout = Duration(seconds: 10);

  /// Absolute ceiling on the entire local-only decision phase (mission
  /// bloc 5's "fail-safe global AppGate") - belt-and-suspenders on top of
  /// the per-step [_localStepTimeout]s: even an unanticipated hang inside
  /// [_resolveLocalGateInputs] itself (not just one of its awaited calls)
  /// can never keep this screen up past this ceiling.
  static const _bootstrapFailsafeTimeout = Duration(seconds: 10);

  void _log(String stage, String message) {
    developer.log('APP_GATE $stage - $message', name: 'AppGate');
  }

  /// Runs [action] with a hard timeout and a safe [fallback] instead of
  /// ever letting AppGate hang on it - logs the start, the outcome (success/
  /// timeout/error) and how long it actually took, exactly what's needed to
  /// tell from a device's logs which single step is responsible if this
  /// ever regresses again (mission bloc 1/6: full traceability, audit every
  /// await on the gate's critical path).
  Future<T> _bounded<T>(
    String stage,
    String label,
    Future<T> Function() action,
    T fallback, {
    Duration timeout = _localStepTimeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    _log(stage, '$label - start');
    try {
      final result = await action().timeout(timeout);
      _log(stage, '$label - success (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } on TimeoutException {
      _log(
        stage,
        '$label - TIMEOUT after ${stopwatch.elapsedMilliseconds}ms (limit '
        '${timeout.inSeconds}s) - falling back to $fallback',
      );
      return fallback;
    } catch (e) {
      _log(
        stage,
        '$label - ERROR after ${stopwatch.elapsedMilliseconds}ms ($e) - '
        'falling back to $fallback',
      );
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  /// The single function that decides which screen this device shows right
  /// now (spec bloc 19). Called exactly at three kinds of moment: app
  /// start, right after any account becomes active (fresh OTP *or* a
  /// silent same-device restore), and right after a revocation is
  /// discovered - never on every rebuild, and never raced against another
  /// listener deciding something else.
  ///
  /// Offline-first by construction (mission 2026, post-launch-hang
  /// incident): the very first decision is made from LOCAL data only -
  /// device id, sign-in state and PIN presence, all local reads - and is
  /// never gated on any network call. Whether this exact device has since
  /// been revoked from another one is checked in the background, after a
  /// screen is already showing (see [_reconcileDeviceAuthorization]) - a
  /// slow, unreachable or non-responding Supabase project can visibly delay
  /// that *reconciliation*, but can never again keep the app itself stuck
  /// on the loading splash.
  Future<void> _evaluate() async {
    _log('01', 'start');
    // Transparent, idempotent migration for vehicles that predate
    // per-vehicle dashboard card colours (schema v8) - fire-and-forget so a
    // slow database can never delay the gate itself; see
    // VehicleRepository.backfillMissingCardColors. Guarded with a plain
    // try/catch (not just unawaited) because reading the provider itself
    // can throw synchronously - vehicleRepositoryProvider also wires
    // vehicleSyncServiceProvider, which reaches for Supabase.instance.client
    // eagerly; a widget test that renders AppGate without a Supabase
    // session (or without overriding the provider) must never have the
    // gate itself get stuck on this best-effort migration.
    try {
      unawaited(ref.read(vehicleRepositoryProvider).backfillMissingCardColors());
    } catch (_) {}

    final inputs = await _resolveLocalGateInputs().timeout(
      _bootstrapFailsafeTimeout,
      onTimeout: () {
        _log(
          'FAILSAFE',
          'local bootstrap exceeded ${_bootstrapFailsafeTimeout.inSeconds}s total - '
          'forcing the safest decision (email screen) instead of staying on the splash',
        );
        return const (deviceUserId: null, authorizedLocally: false, pinSet: false, email: null);
      },
    );

    final state =
        resolveGateState(deviceAuthorized: inputs.authorizedLocally, pinSet: inputs.pinSet);
    _log('06', 'local route decision: $state (authorized=${inputs.authorizedLocally})');
    if (!mounted) return;
    setState(() {
      _activeAccountId = inputs.authorizedLocally ? inputs.deviceUserId : null;
      _lockedEmail = inputs.email;
      _step = switch (state) {
        GateState.email => _GateStep.email,
        GateState.pinSetup => _GateStep.pinSetup,
        GateState.locked => _GateStep.locked,
      };
    });
    _log('07', 'route applied: $_step');

    if (inputs.authorizedLocally) {
      unawaited(_reconcileDeviceAuthorization(inputs.deviceUserId!));
    }
  }

  /// Everything needed to pick the first screen, from local reads alone -
  /// no network. Extracted so [_evaluate] can wrap the *whole* sequence in
  /// one hard ceiling ([_bootstrapFailsafeTimeout]) on top of each read's
  /// own bound.
  Future<
      ({
        String? deviceUserId,
        bool authorizedLocally,
        bool pinSet,
        String? email,
      })> _resolveLocalGateInputs() async {
    final account = ref.read(accountRepositoryProvider);
    final deviceUserId = await _bounded(
      '02',
      'device id (secure storage)',
      account.deviceAuthorizedUserId,
      null,
    );
    final authorizedLocally = deviceUserId != null &&
        account.isSignedIn &&
        account.currentUser?.id == deviceUserId;
    _log('03', 'local authorization=$authorizedLocally (deviceUserId=$deviceUserId)');

    final pinSet = authorizedLocally
        ? await _bounded(
            '04',
            'pin set check (secure storage)',
            () => ref.read(pinServiceProvider).isPinSet(deviceUserId),
            false,
          )
        : false;
    final email = authorizedLocally
        ? await _bounded(
            '05',
            'device email (secure storage)',
            account.deviceAuthorizedEmail,
            null,
          )
        : null;
    return (
      deviceUserId: deviceUserId,
      authorizedLocally: authorizedLocally,
      pinSet: pinSet,
      email: email,
    );
  }

  /// Best-effort, online-only: has the account owner revoked this exact
  /// device from "Appareils connectés" since it last checked in? Runs
  /// strictly AFTER a screen is already showing (see [_evaluate]) - never
  /// blocks offline use, and a non-responding Supabase project only ever
  /// delays this reconciliation, never the app's own bootstrap. On a
  /// confirmed revocation, forces the device back to the email screen
  /// exactly like [_onPinAccepted]'s identical, pre-existing reactive check.
  Future<void> _reconcileDeviceAuthorization(String deviceUserId) async {
    final account = ref.read(accountRepositoryProvider);
    final stillAuthorized = await _bounded(
      '08',
      'background device authorization check',
      () => account.isDeviceStillAuthorized(userId: deviceUserId),
      true,
      timeout: _backgroundCheckTimeout,
    );
    _log('09', 'background device authorization result: $stillAuthorized');
    if (!stillAuthorized && mounted) {
      await account.disconnectFromThisDevice();
      if (!mounted) return;
      _log('10', 'device revoked remotely - forcing back to the email screen');
      setState(() => _step = _GateStep.email);
    }
  }

  /// An account just became active on this device - either a genuinely
  /// fresh email/OTP pass (a new account, or a known account this exact
  /// installation had never seen before), or a silent same-device restore
  /// for an account already known here (spec CAS 3 - no OTP was involved
  /// at all). Both paths converge here: reattribute any orphaned local
  /// data to whoever actually used this device most recently, register/
  /// refresh this device's association, then seed/reuse the local profile
  /// - nothing is ever deleted. `_evaluate()` naturally sends a brand new
  /// account+device pairing to PIN setup (no PIN stored yet) and a
  /// restored, already-known one straight to its own PIN entry (spec bloc
  /// 3/19: OTP success never skips straight to HOME either way).
  Future<void> _onAccountAuthenticated() async {
    final account = ref.read(accountRepositoryProvider);
    // A code can be verified successfully by Supabase and yet the session
    // it should have created is already gone by the time this runs (a
    // token that expires immediately after a "successful" auth). Without
    // this check that read a null `currentUser` through a `!`, crashing
    // with an unhandled TypeError that VerifyEmailScreen's generic catch
    // still displayed as "Une erreur est survenue" - but left the
    // already-consumed code with no way to retry except starting over.
    final currentUserId = account.currentUser?.id;
    if (currentUserId == null) {
      throw AuthException('Votre session a expiré. Veuillez réessayer.');
    }
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

  /// The real, deliberate dissociation of the *currently active* account
  /// from this device (spec bloc 15's "RÉVOQUER/DISSOCIER"/"VRAIE
  /// DÉCONNEXION") - forgets its stored refresh token and its own PIN, so
  /// a fresh OTP is required next time even for that exact email. Any
  /// *other* account this device also knows about is left completely
  /// untouched. The state flip happens as early as possible - right after
  /// the one quick local read needed to know whose PIN to clear, before
  /// any Supabase/network call - so there is never a frame where business
  /// screens are still mounted next to a session that's already gone.
  Future<void> _disconnect({required bool everywhere}) async {
    final account = ref.read(accountRepositoryProvider);
    final accountId = await account.deviceAuthorizedUserId();
    setState(() => _step = _GateStep.email);
    if (everywhere) {
      await account.disconnectFromAllDevices();
    } else {
      await account.disconnectFromThisDevice();
    }
    if (accountId != null) {
      await ref.read(pinServiceProvider).clearPin(accountId);
      await ref.read(biometricServiceProvider).setEnabled(accountId, false);
    }
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
      await ref.read(pinServiceProvider).clearPin(userId);
      await ref.read(biometricServiceProvider).setEnabled(userId, false);
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
      // Pure navigation - see this provider's own doc for why nothing is
      // disconnected here.
      if (previous != null && next != previous) setState(() => _step = _GateStep.email);
    });
    ref.listen<int>(accountDissociateRequestProvider, (previous, next) {
      if (previous != null && next != previous) unawaited(_disconnect(everywhere: false));
    });
    ref.listen<int>(accountDisconnectEverywhereRequestProvider, (previous, next) {
      if (previous != null && next != previous) unawaited(_disconnect(everywhere: true));
    });

    return switch (_step) {
      _GateStep.loading => const _Splash(),
      _GateStep.email => _GateNavigator(
          // Every branch below shares the exact same widget type
          // (_GateNavigator wrapping a bare Navigator) with no key, Flutter
          // would otherwise treat a transition between two of them (e.g.
          // locked -> pinRecovery) as an *update* of the same Element
          // rather than a fresh mount - and a bare Navigator's
          // onGenerateRoute is only ever consulted for its *initial*
          // route, so it would keep showing whatever screen it first
          // mounted forever, no matter how many times _step changes
          // afterwards. This was a real, confirmed bug (see
          // gate_navigator_key_regression_test.dart): "Code oublié ?"/
          // "Changer de compte" changed `_step` correctly but the screen
          // never visibly moved on. A distinct key per step forces a
          // genuine remount on every transition.
          key: const ValueKey(_GateStep.email),
          child: AccountGateScreen(onAuthenticated: _onAccountAuthenticated),
        ),
      _GateStep.pinSetup => _GateNavigator(
          key: const ValueKey(_GateStep.pinSetup),
          child: PinSetupScreen(accountId: _activeAccountId!, onDone: _goUnlocked),
        ),
      _GateStep.locked => _GateNavigator(
          key: const ValueKey(_GateStep.locked),
          child: LockScreen(
            accountId: _activeAccountId!,
            email: _lockedEmail,
            onUnlocked: _onPinAccepted,
            onForgotCode: () => setState(() => _step = _GateStep.pinRecovery),
            onSwitchAccount: () => ref.read(accountSwitchRequestProvider.notifier).state++,
          ),
        ),
      _GateStep.pinRecovery => _GateNavigator(
          key: const ValueKey(_GateStep.pinRecovery),
          child: PinRecoveryScreen(
            accountId: _activeAccountId!,
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
  const _GateNavigator({super.key, required this.child});
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
