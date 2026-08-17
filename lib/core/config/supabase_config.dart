/// Supabase project connection info. The anon key is meant to be embedded
/// in a client app - Supabase's security model relies entirely on Row
/// Level Security in Postgres, never on keeping this key secret (see
/// supabase/migrations/0001_init.sql). The service_role key, which DOES
/// bypass RLS, must never appear here or anywhere in the app.
class SupabaseConfig {
  const SupabaseConfig._();

  static const url = 'https://gecqlxxhflnxlpderkyu.supabase.co';
  static const anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdlY3FseHhoZmxueGxwZGVya3l1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYzMTk3MzIsImV4cCI6MjEwMTg5NTczMn0.teWibXTc5oQlo6T3lhwadsxe7pvyp70hHEpuCq1orG8';
}
