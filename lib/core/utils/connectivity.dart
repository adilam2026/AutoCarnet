import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';

/// Radio-level connectivity only (bloc 20 - never blocks the offline-first
/// experience): used purely to decide whether it's worth even showing the
/// account-auth screen at first launch, never to gate ordinary app usage.
///
/// Mission 2026, real-device incident report (a vehicle - and, separately,
/// a different account's vehicle - created while genuinely signed in never
/// reached Supabase, with zero trace of any push ever being attempted):
/// this call sits BEFORE the try/catch in every *SyncService.syncNow()
/// (see e.g. VehicleSyncService.syncNow), on purpose - a sync pass isn't
/// even worth starting without radio connectivity. But that means this
/// function throwing for ANY reason (a platform channel hiccup, an OEM
/// quirk, anything - `connectivity_plus`'s own doc already says "can throw
/// a PlatformException") used to propagate completely unguarded: no
/// markFailed, no recordError, no retry_count, nothing - the pending row
/// would just sit there forever with no trace an attempt was ever even
/// made. Fail-open instead: if connectivity itself can't be determined,
/// the safest default is to still ATTEMPT the actual push/pull (which
/// have their own robust, tested error handling and automatic retry), not
/// to silently give up with zero record of it - see mission point 8/9's
/// "aucune erreur ne doit jamais être absorbée silencieusement".
Future<bool> hasConnectivity() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  } catch (e) {
    developer.log(
      'hasConnectivity() itself threw ($e) - failing open (assuming '
      'connectivity is present) so the caller still attempts the real '
      'push/pull instead of silently skipping it forever',
      name: 'connectivity',
    );
    return true;
  }
}
