/// Supabase project connection info. The anon key is meant to be embedded
/// in a client app - Supabase's security model relies entirely on Row
/// Level Security in Postgres, never on keeping this key secret (see
/// supabase/migrations/0001_init.sql). The service_role key, which DOES
/// bypass RLS, must never appear here or anywhere in the app.
class SupabaseConfig {
  const SupabaseConfig._();

  // AutoCarnetV2 - replaces the original project, which got stuck in a state
  // where dashboard settings (Confirm email, custom SMTP) stopped being
  // picked up by its auth server even after a restart. No real user data
  // was lost - only test/schema data existed there.
  static const url = 'https://ugrypnavzzqsvuyxkphl.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVncnlwbmF2enpxc3Z1eXhrcGhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwNjY1NjIsImV4cCI6MjEwMjY0MjU2Mn0.W7SdC2ztHtn5hvJUptNOP5Q4OhYxxOHXZgfz6S2Rfw4';
}
