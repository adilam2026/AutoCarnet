-- Phase 4: real multi-table collaboration.
-- ---------------------------------------------------------------------------
-- Phase 3 only shared the vehicle sheet itself (public.vehicles) - every
-- other module (entretien, carburant, dépenses, documents, rappels,
-- kilométrage, fréquences) stayed purely local, so a collaborator invited
-- onto a vehicle could see it appear, but none of its actual data. This
-- migration gives each of those tables its own remote mirror, RLS matching
-- the vehicle's viewer/editor role, and the same optimistic-concurrency
-- columns (version/created_by/updated_by) vehicles gets upgraded to below -
-- so two devices editing the same record are always detected, never
-- silently overwritten (see lib/core/sync/occ_sync.dart for the client side).
--
-- document_attachments is deliberately NOT included: its rows only ever
-- hold a local filesystem path (no Supabase Storage integration exists
-- yet), so syncing the row would just be a dead path on every other
-- device. timeline_events is deliberately NOT synced as raw rows either -
-- it is a derived aggregation (see its own class doc), regenerated locally
-- from whichever business table produced it so it always renders using
-- this device's own locale/labels; syncing the source tables is what makes
-- a collaborator's timeline/reminders appear correctly.
-- ---------------------------------------------------------------------------

-- 0. Shared helper: a caller's effective role on a vehicle, reusing exactly
--    the same policies vehicles/vehicle_members already enforce (owner if
--    vehicles.user_id = auth.uid(), otherwise whatever vehicle_members says)
--    so every child table below can gate on one call instead of repeating
--    the owner-or-member `exists` shape eight more times.
create or replace function public.vehicle_role(p_vehicle_id uuid)
returns text
language sql
security definer set search_path = public
stable
as $$
  select coalesce(
    (select 'owner' from public.vehicles v where v.id = p_vehicle_id and v.user_id = auth.uid()),
    (select vm.role from public.vehicle_members vm
      where vm.vehicle_id = p_vehicle_id and vm.user_id = auth.uid())
  );
$$;

-- 1. Upgrade vehicles itself from last-write-wins-by-timestamp to the same
--    version-based optimistic concurrency every table below uses, and add
--    the attribution columns needed to show "modifié par X" anywhere.
alter table public.vehicles add column if not exists version integer not null default 1;
alter table public.vehicles add column if not exists created_by uuid references auth.users (id);
alter table public.vehicles add column if not exists updated_by uuid references auth.users (id);
update public.vehicles set created_by = user_id where created_by is null;
update public.vehicles set updated_by = user_id where updated_by is null;

-- 2. maintenance_entries (+ maintenance_parts, which always rides along
--    with its parent: the app replaces a maintenance entry's whole parts
--    list on every edit, so parts never carry their own version). ---------
create table public.maintenance_entries (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  date timestamptz not null,
  mileage double precision not null,
  provider_id uuid,
  parts_cost double precision not null default 0,
  labor_cost double precision not null default 0,
  currency text not null default 'MAD',
  warranty_months integer,
  comments text,
  next_due_date timestamptz,
  next_due_mileage double precision,
  linked_expense_id uuid,
  is_deleted boolean not null default false,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index maintenance_entries_vehicle_id_idx on public.maintenance_entries (vehicle_id);
alter table public.maintenance_entries enable row level security;
create policy "vehicle members read maintenance" on public.maintenance_entries
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write maintenance" on public.maintenance_entries
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
create policy "editors update maintenance" on public.maintenance_entries
  for update using (public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.maintenance_entries;

create table public.maintenance_parts (
  id uuid primary key,
  maintenance_entry_id uuid not null references public.maintenance_entries (id) on delete cascade,
  designation text not null,
  reference text,
  brand text,
  quantity double precision not null default 1,
  unit_price double precision not null default 0,
  comments text
);
create index maintenance_parts_entry_id_idx on public.maintenance_parts (maintenance_entry_id);
alter table public.maintenance_parts enable row level security;
create policy "vehicle members read parts" on public.maintenance_parts
  for select using (exists (
    select 1 from public.maintenance_entries m
    where m.id = maintenance_entry_id and public.vehicle_role(m.vehicle_id) is not null
  ));
create policy "editors write parts" on public.maintenance_parts
  for all using (exists (
    select 1 from public.maintenance_entries m
    where m.id = maintenance_entry_id and public.vehicle_role(m.vehicle_id) in ('owner', 'editor')
  )) with check (exists (
    select 1 from public.maintenance_entries m
    where m.id = maintenance_entry_id and public.vehicle_role(m.vehicle_id) in ('owner', 'editor')
  ));

-- 3. expenses ---------------------------------------------------------------
create table public.expenses (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  date timestamptz not null,
  amount double precision not null,
  currency text not null default 'MAD',
  provider_id uuid,
  mileage double precision,
  payment_method text,
  comments text,
  linked_maintenance_id uuid,
  linked_fuel_id uuid,
  linked_document_version_id uuid,
  is_deleted boolean not null default false,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index expenses_vehicle_id_idx on public.expenses (vehicle_id);
alter table public.expenses enable row level security;
create policy "vehicle members read expenses" on public.expenses
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write expenses" on public.expenses
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
create policy "editors update expenses" on public.expenses
  for update using (public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.expenses;

-- 4. fuel_entries -------------------------------------------------------
create table public.fuel_entries (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  date timestamptz not null,
  mileage double precision not null,
  provider_id uuid,
  fuel_type text not null,
  quantity_liters double precision not null,
  price_per_liter double precision not null,
  total_amount double precision not null,
  is_full_tank boolean not null default true,
  comments text,
  linked_expense_id uuid,
  is_deleted boolean not null default false,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index fuel_entries_vehicle_id_idx on public.fuel_entries (vehicle_id);
alter table public.fuel_entries enable row level security;
create policy "vehicle members read fuel" on public.fuel_entries
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write fuel" on public.fuel_entries
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
create policy "editors update fuel" on public.fuel_entries
  for update using (public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.fuel_entries;

-- 5. documents (+ document_versions) - a null vehicle_id is a personal
--    "driver document" (permis...), visible only to whoever created it,
--    never vehicle-shared. -------------------------------------------------
create table public.documents (
  id uuid primary key,
  vehicle_id uuid references public.vehicles (id) on delete cascade,
  type text not null,
  holder text,
  current_version_id uuid,
  is_deleted boolean not null default false,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index documents_vehicle_id_idx on public.documents (vehicle_id);
alter table public.documents enable row level security;
create policy "read own or shared vehicle documents" on public.documents
  for select using (
    (vehicle_id is null and created_by = auth.uid())
    or (vehicle_id is not null and public.vehicle_role(vehicle_id) is not null)
  );
create policy "write own or editor documents" on public.documents
  for insert with check (
    (vehicle_id is null and created_by = auth.uid())
    or (vehicle_id is not null and public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  );
create policy "update own or editor documents" on public.documents
  for update using (
    (vehicle_id is null and created_by = auth.uid())
    or (vehicle_id is not null and public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  ) with check (
    (vehicle_id is null and created_by = auth.uid())
    or (vehicle_id is not null and public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  );
alter publication supabase_realtime add table public.documents;

create table public.document_versions (
  id uuid primary key,
  document_id uuid not null references public.documents (id) on delete cascade,
  document_number text,
  issue_date timestamptz,
  expiry_date timestamptz,
  cost double precision,
  provider_id uuid,
  comments text,
  status text not null default 'valid',
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index document_versions_document_id_idx on public.document_versions (document_id);
alter table public.document_versions enable row level security;
create policy "read versions of visible documents" on public.document_versions
  for select using (exists (
    select 1 from public.documents d where d.id = document_id
      and ((d.vehicle_id is null and d.created_by = auth.uid())
        or (d.vehicle_id is not null and public.vehicle_role(d.vehicle_id) is not null))
  ));
create policy "write versions of writable documents" on public.document_versions
  for all using (exists (
    select 1 from public.documents d where d.id = document_id
      and ((d.vehicle_id is null and d.created_by = auth.uid())
        or (d.vehicle_id is not null and public.vehicle_role(d.vehicle_id) in ('owner', 'editor')))
  )) with check (exists (
    select 1 from public.documents d where d.id = document_id
      and ((d.vehicle_id is null and d.created_by = auth.uid())
        or (d.vehicle_id is not null and public.vehicle_role(d.vehicle_id) in ('owner', 'editor')))
  ));
alter publication supabase_realtime add table public.document_versions;

-- 6. reminders ------------------------------------------------------------
create table public.reminders (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  source_type text not null,
  source_id text not null,
  title text not null,
  due_date timestamptz,
  due_mileage double precision,
  priority text not null default 'normal',
  status text not null default 'active',
  snoozed_until timestamptz,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  created_at timestamptz not null,
  updated_at timestamptz not null
);
create index reminders_vehicle_id_idx on public.reminders (vehicle_id);
alter table public.reminders enable row level security;
create policy "vehicle members read reminders" on public.reminders
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write reminders" on public.reminders
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
create policy "editors update reminders" on public.reminders
  for update using (public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.reminders;

-- 7. mileage_entries - append-only history (RG-VEH-005/006/007: a value is
--    versioned, never overwritten in place), so no update policy or
--    version column is needed: two devices recording different readings
--    are not a conflict, they are two different facts. ---------------------
create table public.mileage_entries (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  value double precision not null,
  recorded_at timestamptz not null,
  source text not null,
  source_id text,
  note text,
  created_by uuid references auth.users (id),
  created_at timestamptz not null
);
create index mileage_entries_vehicle_id_idx on public.mileage_entries (vehicle_id);
alter table public.mileage_entries enable row level security;
create policy "vehicle members read mileage" on public.mileage_entries
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write mileage" on public.mileage_entries
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.mileage_entries;

-- 8. operation_frequency_preferences ---------------------------------------
create table public.operation_frequency_preferences (
  id uuid primary key,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  frequency_km double precision,
  frequency_months integer,
  version integer not null default 1,
  created_by uuid references auth.users (id),
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null,
  unique (vehicle_id, category)
);
alter table public.operation_frequency_preferences enable row level security;
create policy "vehicle members read frequency prefs" on public.operation_frequency_preferences
  for select using (public.vehicle_role(vehicle_id) is not null);
create policy "editors write frequency prefs" on public.operation_frequency_preferences
  for insert with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
create policy "editors update frequency prefs" on public.operation_frequency_preferences
  for update using (public.vehicle_role(vehicle_id) in ('owner', 'editor'))
  with check (public.vehicle_role(vehicle_id) in ('owner', 'editor'));
alter publication supabase_realtime add table public.operation_frequency_preferences;
