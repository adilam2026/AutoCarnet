-- Enables Supabase Realtime on public.vehicles so VehicleSyncService's
-- Realtime subscription (lib/core/sync/sync_coordinator.dart) actually
-- receives postgres_changes events. Without this, onPostgresChanges()
-- subscribes successfully but never fires - RLS still applies to realtime
-- broadcasts exactly as it does to normal selects, so a user only ever
-- receives events for rows they're allowed to see.
alter publication supabase_realtime add table public.vehicles;
