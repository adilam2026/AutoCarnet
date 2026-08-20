import 'package:flutter/material.dart';

import 'email_entry_screen.dart';
import 'verify_email_screen.dart';

/// Entry point for the account-first flow (bloc 7-9): create/sign back
/// into a cloud account with just an email address and a 6-digit code -
/// no password anywhere. [onContinueOffline] is the escape hatch that
/// keeps AutoCarnet usable with no account and no connectivity (bloc 20 -
/// "attention à l'offline first", Principe 9) - it's always reachable, it's
/// never something the user has to fight the UI to find.
///
/// This is a thin coordinator only: each step ([EmailEntryScreen],
/// [VerifyEmailScreen]) is its own independent widget with its own
/// State and controllers. Switching between them means Flutter mounts a
/// genuinely new subtree instead of one widget reconciling a different
/// body against the last one on every rebuild - the previous
/// implementation kept both steps' logic in a single State with an
/// internal enum switch, which turned out to be a real source of
/// instability for the code-entry field.
class AccountGateScreen extends StatefulWidget {
  const AccountGateScreen({
    super.key,
    required this.onAuthenticated,
    required this.onContinueOffline,
  });

  final VoidCallback onAuthenticated;
  final VoidCallback onContinueOffline;

  @override
  State<AccountGateScreen> createState() => _AccountGateScreenState();
}

class _AccountGateScreenState extends State<AccountGateScreen> {
  _PendingVerification? _pending;

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending == null) {
      return EmailEntryScreen(
        onCodeSent: (email, displayName) => setState(() {
          _pending = _PendingVerification(email: email, displayName: displayName);
        }),
        onContinueOffline: widget.onContinueOffline,
      );
    }
    return VerifyEmailScreen(
      // A fresh key per email means retrying with a different address (via
      // "Retour") always gets a fully fresh controller/focus/error state,
      // never one left over from a previous attempt.
      key: ValueKey(pending.email),
      email: pending.email,
      displayName: pending.displayName,
      onAuthenticated: widget.onAuthenticated,
      onBack: () => setState(() => _pending = null),
    );
  }
}

class _PendingVerification {
  const _PendingVerification({required this.email, required this.displayName});
  final String email;
  final String displayName;
}
