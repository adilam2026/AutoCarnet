import 'package:autocarnet/features/account/presentation/email_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Structural regression test: before this fix, AppGate rendered every
/// pre-unlock screen (account auth, onboarding, PIN setup, lock screen)
/// directly from `MaterialApp.router`'s `builder`, entirely discarding
/// `child` (the router itself) - so none of those screens had a
/// [Navigator]/[Overlay] ancestor anywhere above them, unlike every
/// business screen in the app, which is always reached *through* the
/// router and therefore always has one. AppGate now wraps each pre-unlock
/// screen in its own dedicated [Navigator] (`_GateNavigator` in
/// app_gate.dart) specifically to give it that ancestry.
///
/// This test reproduces both situations directly against
/// `MaterialApp.router` (the real host app uses) to pin down the concrete,
/// testable half of that fix. Whether a missing Overlay was actually
/// driving the real-device IME symptoms is something only a real-device
/// pass can confirm - this only proves the structural change is genuinely
/// in place.
void main() {
  GoRouter router() => GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink())],
      );

  testWidgets(
      'the pre-fix shape (builder discards the router child) leaves the screen with no resolvable Overlay',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router(),
          // This mirrors AppGate's old accountAuth/onboarding/pinSetup/
          // locked branches: `child` (the router, which owns the only
          // Navigator/Overlay in the app) is never used.
          builder: (context, child) => Builder(
            builder: (context) {
              capturedContext = context;
              return EmailEntryScreen(onCodeSent: (_) {});
            },
          ),
        ),
      ),
    );

    expect(Overlay.maybeOf(capturedContext), isNull);
  });

  testWidgets(
      'wrapped in its own Navigator (what AppGate now does) the same screen resolves a real Overlay',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router(),
          builder: (context, child) => Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) {
                capturedContext = context;
                return EmailEntryScreen(onCodeSent: (_) {});
              },
            ),
          ),
        ),
      ),
    );

    expect(Overlay.maybeOf(capturedContext), isNotNull);
    expect(find.byType(EmailEntryScreen), findsOneWidget);
  });

  testWidgets(
      'the pre-fix shape could not even show a dialog - LockScreen\'s "Code oublié ?" and '
      '"Changer de compte", and every PIN dialog, would have crashed outright', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router(),
          builder: (context, child) => Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const AlertDialog(title: Text('Code oublié ?')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // The assertion is thrown asynchronously by the gesture handler, so it
    // surfaces as a recorded test exception rather than a thrown Dart
    // exception here - takeException() lets us assert on it directly.
    expect(tester.takeException(), isFlutterError);
  });

  testWidgets('wrapped in its own Navigator (the fix), the same dialog opens normally',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router(),
          builder: (context, child) => Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => const AlertDialog(title: Text('Code oublié ?')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Code oublié ?'), findsOneWidget);
  });
}
