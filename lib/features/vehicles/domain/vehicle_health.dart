import '../../../core/database/database.dart';

enum VehicleHealth { good, attention, critical }

/// Lightweight health signal derived purely from the reminders already
/// computed by the reminders engine (RG-DASH-003: independent from
/// completeness, bloc 16 §16.5) - no new data source, just a read of
/// existing active reminders for the vehicle.
VehicleHealth computeVehicleHealth(List<Reminder> activeReminders) {
  final now = DateTime.now();
  final overdue = activeReminders.any((r) => r.dueDate != null && r.dueDate!.isBefore(now));
  if (overdue) return VehicleHealth.critical;
  final soon = activeReminders.any(
    (r) => r.dueDate != null && r.dueDate!.difference(now).inDays <= 15,
  );
  if (soon) return VehicleHealth.attention;
  return VehicleHealth.good;
}
