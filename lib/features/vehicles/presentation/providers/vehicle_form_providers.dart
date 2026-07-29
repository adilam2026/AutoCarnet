import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../data/vehicle_repository.dart';

/// Completeness score for a given vehicle (RG-VEH-004: independent from the
/// health score, purely about how filled-in the sheet is).
final vehicleCompletenessProvider = Provider.family<double, Vehicle>((ref, v) {
  return ref.watch(vehicleRepositoryProvider).completeness(v);
});
