import 'package:autocarnet/core/utils/connectivity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026, real-device incident report (a vehicle created while
/// genuinely signed in never reached Supabase, with zero trace of any push
/// attempt): confirmed audit finding - `hasConnectivity()` sat BEFORE the
/// try/catch in every single *SyncService.syncNow() (all 9, identical
/// pattern). If the connectivity_plus platform channel throws for ANY
/// reason (its own docs already say "Can throw a PlatformException"), that
/// exception used to propagate completely unguarded: no markFailed, no
/// recordError, no retry_count, nothing - the row would sit pendingSync
/// forever with zero trace an attempt was ever made, indistinguishable
/// from "hasn't gotten to it yet" even after months.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  test(
      'a connectivity_plus platform channel that throws no longer crashes '
      'hasConnectivity() uncaught - it fails open (assumes connectivity is '
      'present) so the caller still attempts the real push instead of '
      'silently giving up forever', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => throw PlatformException(
        code: 'UNAVAILABLE',
        message: 'connectivity plugin not available on this device',
      ),
    );

    final result = await hasConnectivity();

    expect(result, isTrue,
        reason: 'fail-open: an undeterminable connectivity state must never '
            'silently block every future sync attempt');
  });

  test('a normal "wifi" response still reports connectivity present, '
      'unaffected by the fail-open path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );

    expect(await hasConnectivity(), isTrue);
  });

  test('a normal "none" response still correctly reports no connectivity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['none'] : null,
    );

    expect(await hasConnectivity(), isFalse);
  });
}
