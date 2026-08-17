import 'package:connectivity_plus/connectivity_plus.dart';

/// Radio-level connectivity only (bloc 20 - never blocks the offline-first
/// experience): used purely to decide whether it's worth even showing the
/// account-auth screen at first launch, never to gate ordinary app usage.
Future<bool> hasConnectivity() async {
  final results = await Connectivity().checkConnectivity();
  return !results.contains(ConnectivityResult.none);
}
