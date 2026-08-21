import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'email_entry_screen.dart';
import 'verify_email_screen.dart';

/// Entry point for the account-first flow (spec bloc 2-4): create/sign back
/// into a cloud account with just an email address and a 6-digit code - no
/// password anywhere, and no way to bypass it (spec bloc 12 - AutoCarnet
/// requires an account, full stop).
///
/// Thin coordinator only: each step ([EmailEntryScreen], [VerifyEmailScreen])
/// is its own independent widget with its own State and controllers -
/// switching between them mounts a genuinely new subtree instead of one
/// widget reconciling a different body against the last one, which was a
/// real source of instability for the code-entry field in an earlier
/// version of this screen.
class AccountGateScreen extends StatefulWidget {
  const AccountGateScreen({super.key, required this.onAuthenticated});

  final AsyncCallback onAuthenticated;

  @override
  State<AccountGateScreen> createState() => _AccountGateScreenState();
}

class _AccountGateScreenState extends State<AccountGateScreen> {
  String? _pendingEmail;

  @override
  Widget build(BuildContext context) {
    final email = _pendingEmail;
    if (email == null) {
      return EmailEntryScreen(
        onCodeSent: (sentTo) => setState(() => _pendingEmail = sentTo),
        onAuthenticated: widget.onAuthenticated,
      );
    }
    return VerifyEmailScreen(
      // A fresh key per email means retrying with a different address (via
      // "Retour") always gets a fully fresh controller/focus/error state,
      // never one left over from a previous attempt.
      key: ValueKey(email),
      email: email,
      onAuthenticated: widget.onAuthenticated,
      onBack: () => setState(() => _pendingEmail = null),
    );
  }
}
