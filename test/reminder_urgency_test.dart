import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/reminders/domain/reminder_urgency.dart';
import 'package:flutter_test/flutter_test.dart';

Reminder _reminder({DateTime? dueDate, double? dueMileage}) => Reminder(
      id: 'r1',
      vehicleId: 'v1',
      sourceType: 'document',
      sourceId: 's1',
      title: 'Test',
      dueDate: dueDate,
      dueMileage: dueMileage,
      priority: 'normal',
      status: ReminderStatus.active,
      snoozedUntil: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pendingSync',
      version: 0,
      createdBy: null,
      updatedBy: null,
    );

void main() {
  group('isReminderDueSoon ("À faire prochainement" filter)', () {
    test('a date-based échéance at J+61 is not shown', () {
      // A little over 61 days, not exactly 61 - .difference().inDays
      // truncates, so a due date exactly 61 days out can read back as 60
      // once the (tiny) time elapsed since it was set is accounted for.
      final r = _reminder(dueDate: DateTime.now().add(const Duration(days: 61, hours: 12)));
      expect(isReminderDueSoon(r), isFalse);
    });

    test('a date-based échéance at J+60 is shown', () {
      final r = _reminder(dueDate: DateTime.now().add(const Duration(days: 60)));
      expect(isReminderDueSoon(r), isTrue);
    });

    test('a mileage-based révision with 1501 km remaining is not shown', () {
      final r = _reminder(dueMileage: 101501);
      expect(isReminderDueSoon(r, currentMileage: 100000), isFalse);
    });

    test('a mileage-based révision with 1500 km remaining is shown', () {
      final r = _reminder(dueMileage: 101500);
      expect(isReminderDueSoon(r, currentMileage: 100000), isTrue);
    });

    test('an overdue date-based échéance is always shown, no matter how overdue', () {
      final r = _reminder(dueDate: DateTime.now().subtract(const Duration(days: 400)));
      expect(isReminderDueSoon(r), isTrue);
    });

    test('an overdue mileage-based révision is always shown, no matter how overdue', () {
      final r = _reminder(dueMileage: 50000);
      expect(isReminderDueSoon(r, currentMileage: 100000), isTrue);
    });

    test('a reminder already done/dismissed never counts as due soon', () {
      final done = Reminder(
        id: 'r2',
        vehicleId: 'v1',
        sourceType: 'document',
        sourceId: 's2',
        title: 'Done',
        dueDate: DateTime.now().subtract(const Duration(days: 5)),
        dueMileage: null,
        priority: 'normal',
        status: ReminderStatus.done,
        snoozedUntil: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: 'pendingSync',
        version: 0,
        createdBy: null,
        updatedBy: null,
      );
      expect(isReminderDueSoon(done), isFalse);
    });

    test('a reminder with neither a date nor a usable mileage is excluded, not guessed at', () {
      final r = _reminder();
      expect(isReminderDueSoon(r, currentMileage: 100000), isFalse);
    });
  });
}
