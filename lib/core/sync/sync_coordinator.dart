import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'vehicle_sync_service.dart';

/// Keeps the cloud in near-real-time sync with the local database once the
/// app is unlocked, without ever requiring a manual "Synchroniser" tap:
/// - an immediate pass on start (covers changes made offline since last run)
/// - a periodic safety-net pass (covers anything a realtime event missed)
/// - a Supabase Realtime subscription that reacts within a second or two
///   whenever another device/collaborator changes a shared vehicle
///
/// Started once from [AppGate] when the gate reaches `_GateStep.unlocked`,
/// stopped when the widget owning it is disposed (app closed) - it is not
/// tied to sign-in/sign-out, since [VehicleSyncService.syncNow] already
/// no-ops without a session.
class SyncCoordinator {
  SyncCoordinator(this._syncService, this._client);
  final VehicleSyncService _syncService;
  final SupabaseClient _client;

  Timer? _timer;
  RealtimeChannel? _channel;
  bool _started = false;

  static const _pollInterval = Duration(minutes: 2);

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_syncService.syncNow());
    _timer = Timer.periodic(_pollInterval, (_) => _syncService.syncNow());
    _channel = _client
        .channel('vehicles-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (_) => _syncService.syncNow(),
        )
        .subscribe();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(_client.removeChannel(channel));
    }
    _started = false;
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    ref.watch(vehicleSyncServiceProvider),
    Supabase.instance.client,
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});
