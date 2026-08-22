import 'package:supabase_flutter/supabase_flutter.dart';

/// Never show a raw network/technical exception to the end user.
/// [AuthRetryableFetchException] and [AuthUnknownException] set their
/// `message` to `originalError.toString()` internally (see gotrue's
/// fetch.dart) - e.g. "ClientException: Software caused connection abort,
/// uri=...". Genuine API-provided messages (AuthApiException and similar)
/// are curated by Supabase and safe to show as-is.
String authErrorMessage(AuthException e) {
  if (e is AuthRetryableFetchException || e is AuthUnknownException) {
    return 'Connexion impossible. Vérifiez votre connexion internet et réessayez.';
  }
  return e.message;
}
