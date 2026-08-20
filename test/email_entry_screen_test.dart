import 'package:autocarnet/features/account/presentation/email_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an email without @ is rejected before any network call is attempted',
      (tester) async {
    var codeSentCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EmailEntryScreen(
            onCodeSent: (_, _) => codeSentCalled = true,
            onContinueOffline: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'not-an-email');
    await tester.tap(find.text('Recevoir le code'));
    await tester.pump();

    expect(find.text('Adresse email invalide'), findsOneWidget);
    expect(codeSentCalled, isFalse);
  });

  testWidgets('"Continuer hors connexion" is always reachable', (tester) async {
    var offlineCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EmailEntryScreen(
            onCodeSent: (_, _) {},
            onContinueOffline: () => offlineCalled = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Continuer hors connexion'));
    await tester.pump();

    expect(offlineCalled, isTrue);
  });
}
