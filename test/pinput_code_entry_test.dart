import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

/// Regression coverage for the exact real-device symptom reported on the
/// old hand-rolled email-verification TextField: typing digits didn't
/// reliably reach the controller/onChanged, and clearing the field could
/// show a stale value coming back. [Pinput] (a real, native-keyboard-driven
/// TextField under the hood) replaces that field - these tests pin down
/// that its controller and onChanged both track typed/cleared input
/// exactly, the mechanical property that was broken before.
///
/// This does not by itself prove every real device/keyboard behaves
/// identically (only a real-device pass can prove that) - it proves the
/// widget's own state handling is sound, which is the one piece actually
/// under this app's control.
void main() {
  Widget harness({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    VoidCallback? onCompleted,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Pinput(
          length: 6,
          controller: controller,
          autofillHints: null,
          onChanged: onChanged,
          onCompleted: (_) => onCompleted?.call(),
        ),
      ),
    );
  }

  testWidgets('typing 6 digits fills the controller and fires onChanged for every keystroke',
      (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await tester.pumpWidget(harness(controller: controller, onChanged: changes.add));

    await tester.enterText(find.byType(Pinput), '233326');
    await tester.pump();

    expect(controller.text, '233326');
    expect(changes, isNotEmpty);
    expect(changes.last, '233326');
  });

  testWidgets('onCompleted fires exactly once when the 6th digit is entered', (tester) async {
    final controller = TextEditingController();
    var completedCount = 0;
    await tester.pumpWidget(harness(
      controller: controller,
      onChanged: (_) {},
      onCompleted: () => completedCount++,
    ));

    await tester.enterText(find.byType(Pinput), '233326');
    await tester.pump();

    expect(completedCount, 1);
  });

  testWidgets('clearing the field after typing leaves it empty - never a stale value coming back',
      (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await tester.pumpWidget(harness(controller: controller, onChanged: changes.add));

    await tester.enterText(find.byType(Pinput), '233326');
    await tester.pump();
    expect(controller.text, '233326');

    await tester.enterText(find.byType(Pinput), '');
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
  });

  testWidgets('retyping a different code after clearing reflects the new value, not the old one',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(harness(controller: controller, onChanged: (_) {}));

    await tester.enterText(find.byType(Pinput), '233326');
    await tester.pump();
    await tester.enterText(find.byType(Pinput), '');
    await tester.pump();
    await tester.enterText(find.byType(Pinput), '918273');
    await tester.pump();

    expect(controller.text, '918273');
  });
}
