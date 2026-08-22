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

/// Deliberately separate, stricter thresholds from
/// [ReminderUrgencyThresholds] - those drive the "urgent/à surveiller"
/// color classification used on the Alertes screen and the health score;
/// this one single-purposely decides what belongs in the home dashboard's
/// "À faire prochainement" preview, which must only ever show what's
/// actually close, never everything ranked merely "not done yet".
class HomeTodoThresholds {
  static const days = 60;
  static const mileage = 1500.0;
}

/// Whether [r] belongs in "À faire prochainement": overdue (any amount),
/// due within [HomeTodoThresholds.days] days, or due within
/// [HomeTodoThresholds.mileage] km - never merely "not urgent yet". A
/// reminder with neither a due date nor a usable mileage figure has no
/// proximity to judge, so it's excluded rather than guessed at.
bool isReminderDueSoon(Reminder r, {double? currentMileage}) {
  if (r.status == ReminderStatus.done || r.status == ReminderStatus.dismissed) {
    return false;
  }
  if (r.dueDate != null) {
    final days = r.dueDate!.difference(DateTime.now()).inDays;
    return days <= HomeTodoThresholds.days;
  }
  if (r.dueMileage != null && currentMileage != null) {
    final remaining = r.dueMileage! - currentMileage;
    return remaining <= HomeTodoThresholds.mileage;
  }
  return false;
}
