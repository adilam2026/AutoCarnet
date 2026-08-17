-- AutoCarnet - cloud schema v1
-- ---------------------------------------------------------------------------
-- Mirrors the local Drift (SQLite) schema so every table syncs 1:1 with its
-- on-device counterpart. Entity ids are the exact same uuid v4 strings the
-- app already generates locally (see lib/core/utils/id_generator.dart), so a
-- row created offline keeps the same id once it reaches the cloud - no id
-- remapping needed anywhere in the sync engine.
--
-- Security model (bloc 19 - "ne jamais faire confiance uniquement aux
-- contrôles de l'app Flutter"): every table carries its own user_id and Row
-- Level Security is enabled everywhere, so a user can only ever see or write
-- their own rows - enforced by Postgres itself, not by client-side checks.
-- user_id defaults to auth.uid() so the app never has to set it explicitly,
-- and RLS's `with check` still rejects any attempt to write a different one.
--
-- How to apply: Supabase dashboard -> SQL Editor -> paste this whole file
-- -> Run. Safe to re-run only once (uses `create table`, not `create or
-- replace`) - if you need to re-apply, drop the tables first or run future
-- migrations as separate files instead of editing this one.
-- ---------------------------------------------------------------------------

-- 1. Profiles ------------------------------------------------------------
-- One row per auth.users entry, created automatically on sign-up (trigger
-- below) - app-specific preferences live here instead of on auth.users.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  avatar_path text,
  currency text not null default 'MAD',
  distance_unit text not null default 'km',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "select own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "update own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
-- No insert/delete policy: rows are only ever created by the trigger below
-- (security definer) and removed automatically via the auth.users cascade.

-- Auto-creates the profile row the moment someone finishes signing up, so
-- the app never has to remember to do it itself.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, currency, distance_unit)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    'MAD',
    'km'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Devices (bloc 12/18 - multi-device state, last sync) ----------------
create table public.devices (
  id text primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  device_name text,
  platform text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.devices enable row level security;
create policy "select own devices" on public.devices for select using (auth.uid() = user_id);
create policy "insert own devices" on public.devices for insert with check (auth.uid() = user_id);
create policy "update own devices" on public.devices for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own devices" on public.devices for delete using (auth.uid() = user_id);

-- 3. Vehicles --------------------------------------------------------------
create table public.vehicles (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  brand text not null,
  model text not null,
  trim text,
  year integer,
  first_registration_date timestamptz,
  vin text,
  plate text,
  motorization text,
  fiscal_power text,
  fuel_type text,
  transmission text,
  color text,
  photo_path text,
  acquisition_date timestamptz,
  purchase_price double precision,
  condition text,
  comments text,
  current_mileage double precision not null,
  status text not null default 'active',
  created_at timestamptz not null,
  updated_at timestamptz not null,
  is_deleted boolean not null default false
);

create index vehicles_user_id_idx on public.vehicles (user_id);

alter table public.vehicles enable row level security;
create policy "select own vehicles" on public.vehicles for select using (auth.uid() = user_id);
create policy "insert own vehicles" on public.vehicles for insert with check (auth.uid() = user_id);
create policy "update own vehicles" on public.vehicles for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own vehicles" on public.vehicles for delete using (auth.uid() = user_id);

-- 4. Mileage entries ---------------------------------------------------------
create table public.mileage_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  value double precision not null,
  recorded_at timestamptz not null,
  source text not null,
  source_id text,
  note text,
  created_at timestamptz not null
);

create index mileage_entries_vehicle_id_idx on public.mileage_entries (vehicle_id);

alter table public.mileage_entries enable row level security;
create policy "select own mileage_entries" on public.mileage_entries for select using (auth.uid() = user_id);
create policy "insert own mileage_entries" on public.mileage_entries for insert with check (auth.uid() = user_id);
create policy "update own mileage_entries" on public.mileage_entries for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own mileage_entries" on public.mileage_entries for delete using (auth.uid() = user_id);

-- 5. Service providers -------------------------------------------------------
create table public.service_providers (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  type text,
  address text,
  city text,
  country text,
  phone text,
  email text,
  website text,
  comments text,
  is_archived boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index service_providers_user_id_idx on public.service_providers (user_id);

alter table public.service_providers enable row level security;
create policy "select own service_providers" on public.service_providers for select using (auth.uid() = user_id);
create policy "insert own service_providers" on public.service_providers for insert with check (auth.uid() = user_id);
create policy "update own service_providers" on public.service_providers for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own service_providers" on public.service_providers for delete using (auth.uid() = user_id);

-- 6. Documents + versions + attachments --------------------------------------
create table public.documents (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid references public.vehicles (id) on delete cascade,
  type text not null,
  holder text,
  current_version_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  is_deleted boolean not null default false
);

create index documents_vehicle_id_idx on public.documents (vehicle_id);

alter table public.documents enable row level security;
create policy "select own documents" on public.documents for select using (auth.uid() = user_id);
create policy "insert own documents" on public.documents for insert with check (auth.uid() = user_id);
create policy "update own documents" on public.documents for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own documents" on public.documents for delete using (auth.uid() = user_id);

create table public.document_versions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  document_id uuid not null references public.documents (id) on delete cascade,
  document_number text,
  issue_date timestamptz,
  expiry_date timestamptz,
  cost double precision,
  provider_id uuid references public.service_providers (id),
  comments text,
  status text not null default 'valid',
  created_at timestamptz not null
);

create index document_versions_document_id_idx on public.document_versions (document_id);

alter table public.document_versions enable row level security;
create policy "select own document_versions" on public.document_versions for select using (auth.uid() = user_id);
create policy "insert own document_versions" on public.document_versions for insert with check (auth.uid() = user_id);
create policy "update own document_versions" on public.document_versions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own document_versions" on public.document_versions for delete using (auth.uid() = user_id);

-- Now that document_versions exists, wire the forward reference from
-- documents.current_version_id.
alter table public.documents
  add constraint documents_current_version_id_fkey
  foreign key (current_version_id) references public.document_versions (id);

create table public.document_attachments (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  document_version_id uuid not null references public.document_versions (id) on delete cascade,
  -- Points to a Supabase Storage object path once file sync is wired -
  -- local-only paths never leave the device as-is.
  file_path text not null,
  file_name text not null,
  file_type text not null,
  size_bytes integer,
  added_at timestamptz not null
);

create index document_attachments_version_id_idx on public.document_attachments (document_version_id);

alter table public.document_attachments enable row level security;
create policy "select own document_attachments" on public.document_attachments for select using (auth.uid() = user_id);
create policy "insert own document_attachments" on public.document_attachments for insert with check (auth.uid() = user_id);
create policy "update own document_attachments" on public.document_attachments for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own document_attachments" on public.document_attachments for delete using (auth.uid() = user_id);

-- 7. Maintenance -------------------------------------------------------------
create table public.maintenance_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  date timestamptz not null,
  mileage double precision not null,
  provider_id uuid references public.service_providers (id),
  parts_cost double precision not null default 0,
  labor_cost double precision not null default 0,
  currency text not null default 'MAD',
  warranty_months integer,
  comments text,
  next_due_date timestamptz,
  next_due_mileage double precision,
  linked_expense_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  is_deleted boolean not null default false
);

create index maintenance_entries_vehicle_id_idx on public.maintenance_entries (vehicle_id);

alter table public.maintenance_entries enable row level security;
create policy "select own maintenance_entries" on public.maintenance_entries for select using (auth.uid() = user_id);
create policy "insert own maintenance_entries" on public.maintenance_entries for insert with check (auth.uid() = user_id);
create policy "update own maintenance_entries" on public.maintenance_entries for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own maintenance_entries" on public.maintenance_entries for delete using (auth.uid() = user_id);

create table public.maintenance_parts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
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
create policy "select own maintenance_parts" on public.maintenance_parts for select using (auth.uid() = user_id);
create policy "insert own maintenance_parts" on public.maintenance_parts for insert with check (auth.uid() = user_id);
create policy "update own maintenance_parts" on public.maintenance_parts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own maintenance_parts" on public.maintenance_parts for delete using (auth.uid() = user_id);

-- 8. Expenses ------------------------------------------------------------
create table public.expenses (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  date timestamptz not null,
  amount double precision not null,
  currency text not null default 'MAD',
  provider_id uuid references public.service_providers (id),
  mileage double precision,
  payment_method text,
  comments text,
  linked_maintenance_id uuid references public.maintenance_entries (id),
  linked_fuel_id uuid,
  linked_document_version_id uuid references public.document_versions (id),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  is_deleted boolean not null default false
);

create index expenses_vehicle_id_idx on public.expenses (vehicle_id);

alter table public.expenses enable row level security;
create policy "select own expenses" on public.expenses for select using (auth.uid() = user_id);
create policy "insert own expenses" on public.expenses for insert with check (auth.uid() = user_id);
create policy "update own expenses" on public.expenses for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own expenses" on public.expenses for delete using (auth.uid() = user_id);

-- 9. Fuel entries --------------------------------------------------------
create table public.fuel_entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  date timestamptz not null,
  mileage double precision not null,
  provider_id uuid references public.service_providers (id),
  fuel_type text not null,
  quantity_liters double precision not null,
  price_per_liter double precision not null,
  total_amount double precision not null,
  is_full_tank boolean not null default true,
  comments text,
  linked_expense_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  is_deleted boolean not null default false
);

create index fuel_entries_vehicle_id_idx on public.fuel_entries (vehicle_id);

alter table public.fuel_entries enable row level security;
create policy "select own fuel_entries" on public.fuel_entries for select using (auth.uid() = user_id);
create policy "insert own fuel_entries" on public.fuel_entries for insert with check (auth.uid() = user_id);
create policy "update own fuel_entries" on public.fuel_entries for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own fuel_entries" on public.fuel_entries for delete using (auth.uid() = user_id);

-- 10. Timeline (business history) + audit (technical trail) ------------------
create table public.timeline_events (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  module_origin text not null,
  event_type text not null,
  title text not null,
  description text,
  occurred_at timestamptz not null,
  importance text not null default 'normal',
  linked_entity_id text,
  linked_entity_type text,
  created_at timestamptz not null
);

create index timeline_events_vehicle_id_idx on public.timeline_events (vehicle_id);

alter table public.timeline_events enable row level security;
create policy "select own timeline_events" on public.timeline_events for select using (auth.uid() = user_id);
create policy "insert own timeline_events" on public.timeline_events for insert with check (auth.uid() = user_id);
create policy "update own timeline_events" on public.timeline_events for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own timeline_events" on public.timeline_events for delete using (auth.uid() = user_id);

create table public.audit_events (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid references public.vehicles (id) on delete cascade,
  entity_type text not null,
  entity_id text,
  action text not null,
  summary text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null
);

create index audit_events_vehicle_id_idx on public.audit_events (vehicle_id);

alter table public.audit_events enable row level security;
create policy "select own audit_events" on public.audit_events for select using (auth.uid() = user_id);
create policy "insert own audit_events" on public.audit_events for insert with check (auth.uid() = user_id);
create policy "update own audit_events" on public.audit_events for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own audit_events" on public.audit_events for delete using (auth.uid() = user_id);

-- 11. Operation frequency preferences + reminders -----------------------------
create table public.operation_frequency_preferences (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  frequency_km double precision,
  frequency_months integer,
  updated_at timestamptz not null
);

create index operation_frequency_preferences_vehicle_id_idx on public.operation_frequency_preferences (vehicle_id);

alter table public.operation_frequency_preferences enable row level security;
create policy "select own operation_frequency_preferences" on public.operation_frequency_preferences for select using (auth.uid() = user_id);
create policy "insert own operation_frequency_preferences" on public.operation_frequency_preferences for insert with check (auth.uid() = user_id);
create policy "update own operation_frequency_preferences" on public.operation_frequency_preferences for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own operation_frequency_preferences" on public.operation_frequency_preferences for delete using (auth.uid() = user_id);

create table public.reminders (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  source_type text not null,
  source_id text not null,
  title text not null,
  due_date timestamptz,
  due_mileage double precision,
  priority text not null default 'normal',
  status text not null default 'active',
  snoozed_until timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index reminders_vehicle_id_idx on public.reminders (vehicle_id);

alter table public.reminders enable row level security;
create policy "select own reminders" on public.reminders for select using (auth.uid() = user_id);
create policy "insert own reminders" on public.reminders for insert with check (auth.uid() = user_id);
create policy "update own reminders" on public.reminders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "delete own reminders" on public.reminders for delete using (auth.uid() = user_id);
