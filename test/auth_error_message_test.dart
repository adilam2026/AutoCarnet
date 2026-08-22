import 'package:autocarnet/core/utils/auth_error_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression coverage for a raw exception leaking straight into the UI:
/// a real-device screenshot showed "ClientException: Software caused
/// connection abort, uri=.../auth/v1/otp?" on the email entry screen. That
/// text is `AuthRetryableFetchException.message`, which gotrue sets to
/// `originalError.toString()` for any network-level failure - never meant
/// to be user-facing (see gotrue's fetch.dart). authErrorMessage() is the
/// single choke point every email/OTP screen must use before showing an
/// AuthException's message.
void main() {
  test('a network-level AuthRetryableFetchException never surfaces its raw message', () {
    final e = AuthRetryableFetchException(
      message: 'ClientException: Software caused connection abort, uri=https://x.supabase.co/auth/v1/otp?',
    );
    final message = authErrorMessage(e);
    expect(message, isNot(contains('ClientException')));
    expect(message, contains('connexion'));
  });

  test('an AuthUnknownException (wraps an arbitrary originalError) never surfaces its raw message', () {
    final e = AuthUnknownException(message: 'SocketException: Failed host lookup', originalError: 'boom');
    final message = authErrorMessage(e);
    expect(message, isNot(contains('SocketException')));
  });

  test('a genuine, Supabase-curated AuthApiException message is shown as-is', () {
    const e = AuthApiException('Email rate limit exceeded', statusCode: '429');
    expect(authErrorMessage(e), 'Email rate limit exceeded');
  });
}
