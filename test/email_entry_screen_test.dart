import 'package:autocarnet/features/account/presentation/email_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec bloc 2: a device with no account association shows *only* an email
/// field - no name field, no "continue without an account" escape hatch
/// (spec bloc 12 - AutoCarnet requires an account, full stop).
void main() {
  testWidgets('an email without @ is rejected before any network call is attempted',
      (tester) async {
    var codeSentCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EmailEntryScreen(
            onCodeSent: (_) => codeSentCalled = true,
            onAuthenticated: () async {},
          ),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Adresse email'), 'not-an-email');
    await tester.tap(find.text('Continuer'));
    await tester.pump();

    expect(find.text('Adresse email invalide'), findsOneWidget);
    expect(codeSentCalled, isFalse);
  });

  testWidgets('there is no name field and no way to continue without an account', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EmailEntryScreen(onCodeSent: (_) {}, onAuthenticated: () async {}),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Adresse email'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('hors connexion'), findsNothing);
    expect(find.textContaining('Nom'), findsNothing);
  });
}
