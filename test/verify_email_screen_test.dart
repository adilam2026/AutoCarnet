import 'package:autocarnet/features/account/presentation/verify_email_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the exact real-device scenario reported after
/// two failed fix attempts (a hand-rolled TextField, then Pinput): typing
/// digits, deleting some, then typing more could bring back characters
/// that were already deleted. The verification field is now the plainest
/// possible Flutter TextField - this pins down that its controller only
/// ever reflects exactly what was typed, nothing restored, nothing from a
/// previous state.
void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: VerifyEmailScreen(
              email: 'test@example.com',
              displayName: 'Test',
              onAuthenticated: () async {},
              onBack: () {},
            ),
          ),
        ),
      );

  Finder codeField() => find.widgetWithText(TextField, 'Code de vérification');

  testWidgets(
      '"123" -> delete "3" -> delete "2" -> "1" left -> type "7" -> result is exactly "17", '
      'never "1237" and never a restored "2" or "3"', (tester) async {
    await pump(tester);

    await tester.enterText(codeField(), '123');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, '123');

    // Backspace once: "12" -> "1" (simulating two consecutive deletions).
    await tester.enterText(codeField(), '12');
    await tester.pump();
    await tester.enterText(codeField(), '1');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, '1');

    // Type "7" on top of the remaining "1".
    await tester.enterText(codeField(), '17');
    await tester.pump();

    expect(tester.widget<TextField>(codeField()).controller!.text, '17');
  });

  testWidgets('clearing the field entirely leaves it really empty, then typing "9" gives "9"',
      (tester) async {
    await pump(tester);

    await tester.enterText(codeField(), '17');
    await tester.pump();
    await tester.enterText(codeField(), '');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, isEmpty);

    await tester.enterText(codeField(), '9');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, '9');
  });

  testWidgets(
      'filling all 6 digits, partially deleting, then retyping never brings back a deleted digit',
      (tester) async {
    await pump(tester);

    await tester.enterText(codeField(), '482913');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, '482913');

    // Delete down to "482".
    await tester.enterText(codeField(), '482');
    await tester.pump();
    expect(tester.widget<TextField>(codeField()).controller!.text, '482');

    // Retype a different tail.
    await tester.enterText(codeField(), '482756');
    await tester.pump();

    expect(tester.widget<TextField>(codeField()).controller!.text, '482756');
  });

  testWidgets('non-digit characters are rejected by the input formatter', (tester) async {
    await pump(tester);

    await tester.enterText(codeField(), '12a3b4');
    await tester.pump();

    expect(tester.widget<TextField>(codeField()).controller!.text, '1234');
  });
}
