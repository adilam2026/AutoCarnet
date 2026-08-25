import 'package:autocarnet/core/widgets/date_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 2026, point 1: "JJ/MM/AAAA" typing mask, applied everywhere a
/// date can be entered manually - TEST 1 and TEST 2 from the mandatory
/// test list.
void main() {
  group('DateInputFormatter (TEST 1: "25082026" -> "25/08/2026")', () {
    TextEditingValue typeDigit(TextEditingValue current, String digit) {
      final formatter = DateInputFormatter();
      final raw = TextEditingValue(
        text: current.text + digit,
        selection: TextSelection.collapsed(offset: current.text.length + 1),
      );
      return formatter.formatEditUpdate(current, raw);
    }

    test('typing digit by digit auto-inserts both slashes, ending on the '
        'exact expected result', () {
      var value = const TextEditingValue(text: '');
      for (final digit in '25082026'.split('')) {
        value = typeDigit(value, digit);
      }
      expect(value.text, '25/08/2026');
    });

    test('the slash appears immediately after the 2nd and 4th digits, '
        'never waiting for a following digit', () {
      var value = const TextEditingValue(text: '');
      value = typeDigit(value, '1');
      expect(value.text, '1');
      value = typeDigit(value, '2');
      expect(value.text, '12/');
      value = typeDigit(value, '0');
      expect(value.text, '12/0');
      value = typeDigit(value, '8');
      expect(value.text, '12/08/');
    });

    test('never lets more than 8 digits through (JJMMAAAA)', () {
      var value = const TextEditingValue(text: '');
      for (final digit in '123456789999'.split('')) {
        value = typeDigit(value, digit);
      }
      expect(value.text, '12/34/5678');
    });

    test('backspacing right after an auto-inserted "/" removes the digit '
        'before it too, instead of getting stuck on the separator', () {
      const formatter = DateInputFormatter.new;
      final afterTyping = formatter().formatEditUpdate(
        const TextEditingValue(text: '1'),
        const TextEditingValue(text: '12', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(afterTyping.text, '12/');

      final afterBackspace = formatter().formatEditUpdate(
        afterTyping,
        TextEditingValue(
          text: afterTyping.text.substring(0, afterTyping.text.length - 1),
          selection: TextSelection.collapsed(offset: afterTyping.text.length - 1),
        ),
      );
      expect(afterBackspace.text, '1');
    });
  });

  group('parseDdMmYyyy / formatDdMmYyyy', () {
    test('a complete, calendar-valid date parses correctly', () {
      final d = parseDdMmYyyy('25/08/2026');
      expect(d, DateTime(2026, 8, 25));
    });

    test('formatDdMmYyyy always zero-pads day and month - never '
        '"5/3/2026"', () {
      expect(formatDdMmYyyy(DateTime(2026, 3, 5)), '05/03/2026');
    });

    test(
      'TEST 2: an invalid date (31 février) is never silently accepted - '
      'it fails to parse rather than rolling over to a nearby real date',
      () {
        expect(parseDdMmYyyy('31/02/2026'), isNull);
      },
    );

    test('an impossible month or a nonsensical year both fail to parse', () {
      expect(parseDdMmYyyy('15/13/2026'), isNull);
      expect(parseDdMmYyyy('15/06/1800'), isNull);
    });

    test('a structurally malformed string (missing digits, wrong shape) '
        'fails to parse rather than guessing', () {
      expect(parseDdMmYyyy('2/8/2026'), isNull);
      expect(parseDdMmYyyy('25/08/26'), isNull);
      expect(parseDdMmYyyy(''), isNull);
    });

    test('leap years are handled correctly (29/02 valid only on a leap '
        'year)', () {
      expect(parseDdMmYyyy('29/02/2024'), DateTime(2024, 2, 29));
      expect(parseDdMmYyyy('29/02/2026'), isNull);
    });
  });

  group('AppDateField widget (TEST 2: invalid date blocks submission)', () {
    Widget pumpableField({
      required GlobalKey<FormState> formKey,
      required bool requiredField,
      ValueChanged<DateTime?>? onChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AppDateField(
              label: 'Date',
              requiredField: requiredField,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      );
    }

    testWidgets('typing a complete, valid date fires onChanged with the '
        'real DateTime', (tester) async {
      DateTime? notified;
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(pumpableField(
        formKey: formKey,
        requiredField: true,
        onChanged: (d) => notified = d,
      ));

      await tester.enterText(find.byType(TextFormField), '25082026');
      await tester.pump();

      expect(notified, DateTime(2026, 8, 25));
      expect(find.text('25/08/2026'), findsOneWidget);
    });

    testWidgets(
      'TEST 2: a structurally invalid date fails form validation instead '
      'of being silently accepted',
      (tester) async {
        final formKey = GlobalKey<FormState>();
        await tester.pumpWidget(pumpableField(formKey: formKey, requiredField: true));

        // 31/02 does not exist - the formatter still lets it be typed (it
        // only auto-inserts slashes, it doesn't calendar-validate as you
        // type), but the field's own validator must catch it at submit.
        await tester.enterText(find.byType(TextFormField), '31022026');
        await tester.pump();

        expect(formKey.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Date invalide (JJ/MM/AAAA)'), findsOneWidget);
      },
    );

    testWidgets('an empty required field fails validation with "Date '
        'requise"', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(pumpableField(formKey: formKey, requiredField: true));

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Date requise'), findsOneWidget);
    });

    testWidgets('an empty NON-required field passes validation (used for '
        'optional dates like a next-due échéance)', (tester) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(pumpableField(formKey: formKey, requiredField: false));

      expect(formKey.currentState!.validate(), isTrue);
    });
  });
}
