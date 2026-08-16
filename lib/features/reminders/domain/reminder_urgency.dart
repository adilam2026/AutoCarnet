import '../../../core/database/database.dart';

enum ReminderUrgency { urgent, upcoming, later, done }

/// Shared thresholds so "urgent" and "à surveiller" mean the same thing on
/// the Alertes screen, the vehicle dashboard's "À faire" section and the
/// health score - one definition, not three.
class ReminderUrgencyThresholds {
  static const urgentDays = 7;
  static const upcomingDays = 30;
  static const urgentMileage = 300.0;
  static const upcomingMileage = 2000.0;
}

/// Classifies a single reminder. [currentMileage] is only needed for
/// mileage-only reminders (no due date) - pass null if unknown, the
/// reminder then falls back to [ReminderUrgency.later].
ReminderUrgency reminderUrgency(Reminder r, {double? currentMileage}) {
  if (r.status == ReminderStatus.done || r.status == ReminderStatus.dismissed) {
    return ReminderUrgency.done;
  }
  if (r.dueDate != null) {
    final days = r.dueDate!.difference(DateTime.now()).inDays;
    if (days < 0 || days <= ReminderUrgencyThresholds.urgentDays) {
      return ReminderUrgency.urgent;
    }
    if (days <= ReminderUrgencyThresholds.upcomingDays) {
      return ReminderUrgency.upcoming;
    }
    return ReminderUrgency.later;
  }
  if (r.dueMileage != null && currentMileage != null) {
    final remaining = r.dueMileage! - currentMileage;
    if (remaining <= ReminderUrgencyThresholds.urgentMileage) {
      return ReminderUrgency.urgent;
    }
    if (remaining <= ReminderUrgencyThresholds.upcomingMileage) {
      return ReminderUrgency.upcoming;
    }
    return ReminderUrgency.later;
  }
  return ReminderUrgency.later;
}
