import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Isolates the exact mechanism behind a real device bug: AppGate renders
/// every pre-unlock step (email/OTP, PIN setup, locked, PIN recovery)
/// through the same widget shape - a stateless wrapper around a bare
/// `Navigator(onGenerateRoute: ...)` - swapped via a `switch (_step)`
/// expression. Without a distinct `key` per step, two different steps
/// produce the same (runtimeType, key) pair, so Flutter's element diffing
/// treats a transition between them as an *update* of the same Element
/// rather than a fresh mount. A bare Navigator's `onGenerateRoute` is only
/// ever consulted for its *initial* route - it is never re-invoked just
/// because the widget's `onGenerateRoute` closure changed on a later
/// rebuild - so the Navigator kept showing whatever screen it first
/// mounted, no matter how many times the outer step changed afterwards.
///
/// This is exactly why "Code oublié ?" and "Changer de compte" from the
/// lock screen visibly did nothing on a real device: `_step` genuinely
/// changed in AppGate's state, the dialog genuinely closed, but the
/// Navigator hosting the lock screen never regenerated its route to show
/// the next screen. The very first transition after a cold start
/// (`_Splash` -> a real step) was never affected, since `_Splash` is a
/// different widget type - which is why the initial email->OTP->PIN
/// setup->locked journey worked while any *subsequent* transition between
/// two pre-unlock steps within the same session silently froze.
///
/// See app_gate.dart's `_GateNavigator(key: const ValueKey(_GateStep...))`
/// for the actual fix - this test guards the general mechanism so the
/// same anti-pattern (a bare Navigator swapped without a key) can never be
/// silently reintroduced anywhere in the gate.
class _BareNavigator extends StatelessWidget {
  const _BareNavigator({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => child),
    );
  }
}

class _Harness extends StatefulWidget {
  const _Harness({required this.useKeys});
  final bool useKeys;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _second = false;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (context, state) => const SizedBox.shrink())],
    );
    return MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => Scaffold(
        body: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _second = true),
              child: const Text('advance'),
            ),
            Expanded(
              child: _second
                  ? _BareNavigator(
                      key: widget.useKeys ? const ValueKey('B') : null,
                      child: const Text('SCREEN B'),
                    )
                  : _BareNavigator(
                      key: widget.useKeys ? const ValueKey('A') : null,
                      child: const Text('SCREEN A'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
      'without a distinct key per step, a bare Navigator freezes on whatever screen it first '
      'mounted - reproducing the exact real-device bug', (tester) async {
    await tester.pumpWidget(const _Harness(useKeys: false));
    expect(find.text('SCREEN A'), findsOneWidget);

    await tester.tap(find.text('advance'));
    await tester.pumpAndSettle();

    expect(find.text('SCREEN A'), findsOneWidget,
        reason: 'reproduces the bug: the old screen never gets replaced');
    expect(find.text('SCREEN B'), findsNothing);
  });

  testWidgets('with a distinct key per step (the actual fix), the Navigator correctly shows '
      'the new screen', (tester) async {
    await tester.pumpWidget(const _Harness(useKeys: true));
    expect(find.text('SCREEN A'), findsOneWidget);

    await tester.tap(find.text('advance'));
    await tester.pumpAndSettle();

    expect(find.text('SCREEN B'), findsOneWidget, reason: 'keying forces a real remount');
    expect(find.text('SCREEN A'), findsNothing);
  });
}
