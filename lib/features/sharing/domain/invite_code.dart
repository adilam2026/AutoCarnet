import 'dart:math';

/// Charset deliberately excludes characters that are easy to misread or
/// mistype from a phone screen (0/O, 1/I/L) - every remaining character is
/// unambiguous even in a small font. 31 symbols, 8 of them per code, so a
/// blind guess without a valid authenticated account (required to even
/// attempt redemption - see 0004_vehicle_sharing.sql) faces 31^8 ≈ 8.5×10^11
/// combinations.
const _charset = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

final _secureRandom = Random.secure();

/// Generates a fresh, cryptographically random invite code - the raw form
/// stored in the database and sent to `preview_vehicle_invite`/
/// `accept_vehicle_invite` (no dash, uppercase, matches the DB's
/// `^[A-Z0-9]{8}$` check constraint).
String generateInviteCode() {
  return List.generate(8, (_) => _charset[_secureRandom.nextInt(_charset.length)]).join();
}

/// The same code, formatted for display/typing (e.g. "Q7K9-M2P4") - never
/// what's actually sent to the backend, purely a readability aid.
String formatInviteCodeForDisplay(String rawCode) {
  if (rawCode.length != 8) return rawCode;
  return '${rawCode.substring(0, 4)}-${rawCode.substring(4)}';
}

/// Normalizes whatever the user typed (with or without the dash, any case,
/// stray spaces) back to the raw form the backend expects. Mirrors the SQL
/// functions' own `upper(regexp_replace(trim(p_code), '[^A-Za-z0-9]', '', 'g'))`
/// so client-side validation never disagrees with the server.
String normalizeInviteCodeInput(String input) {
  return input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
