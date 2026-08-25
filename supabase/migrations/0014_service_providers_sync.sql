-- Sync-hardening pass (mission 2026, after the GLC vehicle data-loss
-- report): public.service_providers already existed (0001_init.sql) with
-- owner-only RLS, but the local ServiceProviders table had drifted ahead of
-- it - a "category" column with no remote counterpart, and none of the
-- version/created_by/updated_by columns every other synced table already
-- has (see 0009_collaborative_sync.sql). Prestataires used to be "purely
-- local by design" on the Flutter side; this is the other half of making
-- that real, matching lib/core/database/tables.dart's ServiceProviders and
-- lib/core/sync/provider_sync_service.dart's OCC push/pull.
alter table public.service_providers add column if not exists category text;
alter table public.service_providers add column if not exists version integer not null default 1;
alter table public.service_providers add column if not exists created_by uuid references auth.users (id);
alter table public.service_providers add column if not exists updated_by uuid references auth.users (id);
update public.service_providers set created_by = user_id where created_by is null;
update public.service_providers set updated_by = user_id where updated_by is null;

alter publication supabase_realtime add table public.service_providers;
