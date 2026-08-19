-- Vehicle sharing / collaboration (phase 3 of the "connexion visible +
-- partage collaboratif d'un véhicule" évolution).
-- ---------------------------------------------------------------------------
-- Adds real multi-user access to a single vehicle, built on top of the
-- existing single-owner schema (public.vehicles.user_id stays the one and
-- only owner column - nothing about ownership itself changes). A second
-- table, vehicle_members, grants additional users read (viewer) or
-- read+write (editor) access to a specific vehicle; vehicle_invite_codes
-- is how a member gets added there, through a short human-readable code
-- instead of ever sharing real credentials.
--
-- Security model recap (see 0001's header comment, and 0002's real-world
-- lesson): SECURITY DEFINER functions on this project do NOT bypass Row
-- Level Security - the `postgres` role used to run them has no BYPASSRLS
-- attribute here. So the invite-redemption functions below can only
-- mutate vehicle_invite_codes / vehicle_members because explicit policies
-- allow it - and those policies are deliberately gated behind a
-- transaction-local setting (`app.redeeming_code`) that only the
-- functions themselves can set. A client calling the REST API directly
-- instead of going through preview_vehicle_invite()/accept_vehicle_invite()
-- can never satisfy those policies, even if they can guess a vehicle id.
-- ---------------------------------------------------------------------------

-- 1. profiles.email - so a collaborator's name *and* email can be shown on
--    the access-management screen without ever querying auth.users
--    directly from a client (never exposed via PostgREST). Populated by
--    the app itself right after sign-in (see AccountRepository), since
--    that's simpler and more reliable than a one-off cross-schema backfill
--    from this migration.
alter table public.profiles add column if not exists email text;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email, currency, distance_unit)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    new.email,
    'MAD',
    'km'
  );
  return new;
exception when others then
  return new;
end;
$$;

-- A user's own profile stays visible as before; additionally, anyone who
-- shares at least one vehicle (as owner or as fellow member) with another
-- user can see that user's name/email - needed for both the "Partage et
-- accès" screen and the invite preview ("owner_display_name"). Scoped
-- strictly to actual shared vehicles, never a global directory.
alter policy "select own profile" on public.profiles
  using (
    auth.uid() = id
    or exists (
      select 1
      from public.vehicle_members vm
      join public.vehicles v on v.id = vm.vehicle_id
      where (v.user_id = auth.uid() or vm.user_id = auth.uid())
        and (profiles.id = v.user_id or profiles.id = vm.user_id)
    )
  );

-- 2. vehicle_members - who (besides the owner) can access a vehicle, and
--    at what level. -----------------------------------------------------
create table public.vehicle_members (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('viewer', 'editor')),
  invited_by uuid not null references auth.users (id),
  added_at timestamptz not null default now(),
  last_activity_at timestamptz,
  unique (vehicle_id, user_id)
);

create index vehicle_members_vehicle_id_idx on public.vehicle_members (vehicle_id);
create index vehicle_members_user_id_idx on public.vehicle_members (user_id);

alter table public.vehicle_members enable row level security;

-- The member themselves (to know their own role) or the vehicle's owner
-- (to manage the access list) can see a membership row.
create policy "select own membership or as owner" on public.vehicle_members
  for select using (
    user_id = auth.uid()
    or exists (
      select 1 from public.vehicles v
      where v.id = vehicle_members.vehicle_id and v.user_id = auth.uid()
    )
  );

-- Never inserted directly by a client - only accept_vehicle_invite() ever
-- does this, inside the same transaction that already validated a real,
-- unexpired, not-yet-used code (see app.redeeming_code below).
create policy "insert only via accepted invite" on public.vehicle_members
  for insert with check (
    user_id = auth.uid()
    and current_setting('app.redeeming_code', true) is not null
  );

-- Only the owner changes a collaborator's permission level (RG: an editor
-- can never touch anyone's role, including their own).
create policy "owner updates member role" on public.vehicle_members
  for update using (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_members.vehicle_id and v.user_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_members.vehicle_id and v.user_id = auth.uid()
    )
  );

-- Only the owner revokes access. Deliberately does not cascade into any
-- other table - a revoked member's past contributions (timeline, audit,
-- maintenance...) are untouched, by construction (nothing here references
-- vehicle_members as a foreign key from history tables).
create policy "owner revokes member" on public.vehicle_members
  for delete using (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_members.vehicle_id and v.user_id = auth.uid()
    )
  );

-- 3. vehicle_invite_codes - short-lived, single-use, human-typeable codes
--    that grant access once redeemed by a real authenticated account. ---
create table public.vehicle_invite_codes (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  -- Stored without the display dash, uppercase, from a charset the app
  -- deliberately excludes ambiguous characters from (0/O, 1/I/L) - see
  -- lib/features/sharing/domain/invite_code.dart.
  code text not null unique check (code ~ '^[A-Z0-9]{8}$'),
  role text not null check (role in ('viewer', 'editor')),
  created_by uuid not null default auth.uid() references auth.users (id),
  status text not null default 'active' check (status in ('active', 'cancelled', 'accepted')),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users (id),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create index vehicle_invite_codes_vehicle_id_idx on public.vehicle_invite_codes (vehicle_id);

alter table public.vehicle_invite_codes enable row level security;

-- The owner sees every code for their own vehicle (to list/cancel them);
-- anyone else can only ever see the single row matching the exact code
-- they just typed, and only for the duration of the redeeming function's
-- own transaction (app.redeeming_code) - never a listing, never guessable.
create policy "owner or exact code match" on public.vehicle_invite_codes
  for select using (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_invite_codes.vehicle_id and v.user_id = auth.uid()
    )
    or code = current_setting('app.redeeming_code', true)
  );

-- Only the vehicle's owner generates codes for it.
create policy "owner creates codes" on public.vehicle_invite_codes
  for insert with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.vehicles v
      where v.id = vehicle_invite_codes.vehicle_id and v.user_id = auth.uid()
    )
  );

-- Two, and only two, ways a code row is ever updated: the owner cancels
-- it, or accept_vehicle_invite() marks it accepted for the exact code the
-- caller supplied (app.redeeming_code again).
create policy "owner cancels or function accepts" on public.vehicle_invite_codes
  for update using (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_invite_codes.vehicle_id and v.user_id = auth.uid()
    )
    or code = current_setting('app.redeeming_code', true)
  ) with check (
    exists (
      select 1 from public.vehicles v
      where v.id = vehicle_invite_codes.vehicle_id and v.user_id = auth.uid()
    )
    or (
      accepted_by = auth.uid()
      and status = 'accepted'
      and code = current_setting('app.redeeming_code', true)
    )
  );

-- 4. Shared access to the vehicle itself - a viewer can read, an editor
--    can read+write, neither can insert (creating a vehicle always makes
--    you its owner) or delete (see the owner-only trigger below). --------
alter policy "select own vehicles" on public.vehicles
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.vehicle_members vm
      where vm.vehicle_id = vehicles.id and vm.user_id = auth.uid()
    )
  );

alter policy "update own vehicles" on public.vehicles
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.vehicle_members vm
      where vm.vehicle_id = vehicles.id and vm.user_id = auth.uid() and vm.role = 'editor'
    )
  )
  with check (
    auth.uid() = user_id
    or exists (
      select 1 from public.vehicle_members vm
      where vm.vehicle_id = vehicles.id and vm.user_id = auth.uid() and vm.role = 'editor'
    )
  );

-- Belt-and-suspenders (bloc 19 - never trust the app alone): even though
-- an editor's UPDATE is otherwise allowed, permanently deleting the
-- vehicle is owner-exclusive (mandate item 16). The app itself already
-- only ever soft-deletes (is_deleted = true) rather than issuing a real
-- SQL DELETE, so this is the actual enforcement point, not just hiding
-- the button in the UI for a collaborator.
create or replace function public.prevent_non_owner_vehicle_delete()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.is_deleted is distinct from old.is_deleted
     and new.is_deleted = true
     and auth.uid() is distinct from old.user_id then
    raise exception 'only_owner_can_delete_vehicle';
  end if;
  return new;
end;
$$;

create trigger vehicles_owner_only_delete
  before update on public.vehicles
  for each row execute procedure public.prevent_non_owner_vehicle_delete();

-- 5. Invite preview + redemption - the only two ways vehicle_members or
--    vehicle_invite_codes.status ever change on the "joining" side. ------
-- Read-only: shows what the code grants (vehicle, owner, permission
-- level) *before* the user commits to anything - never mutates.
create or replace function public.preview_vehicle_invite(p_code text)
returns table (
  vehicle_id uuid,
  brand text,
  model text,
  plate text,
  owner_display_name text,
  role text,
  expires_at timestamptz
)
language plpgsql
security definer set search_path = public
as $$
declare
  v_code text := upper(regexp_replace(trim(p_code), '[^A-Za-z0-9]', '', 'g'));
  v_row public.vehicle_invite_codes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if v_code = '' then
    raise exception 'code_invalid';
  end if;

  perform set_config('app.redeeming_code', v_code, true);

  select * into v_row from public.vehicle_invite_codes where code = v_code;

  if not found then
    raise exception 'code_invalid';
  elsif v_row.status = 'cancelled' then
    raise exception 'code_cancelled';
  elsif v_row.status = 'accepted' then
    raise exception 'code_already_used';
  elsif v_row.expires_at <= now() then
    raise exception 'code_expired';
  end if;

  return query
    select v_row.vehicle_id, v.brand, v.model, v.plate, p.display_name, v_row.role, v_row.expires_at
    from public.vehicles v
    join public.profiles p on p.id = v.user_id
    where v.id = v_row.vehicle_id;
end;
$$;

-- Mutating: actually redeems the code - marks it accepted (one-time use)
-- and grants membership. Idempotent for a retry on the same already-
-- accepted-by-this-same-user code (rare double-submit), via the upsert.
create or replace function public.accept_vehicle_invite(p_code text)
returns table (
  vehicle_id uuid,
  brand text,
  model text,
  plate text,
  role text
)
language plpgsql
security definer set search_path = public
as $$
declare
  v_code text := upper(regexp_replace(trim(p_code), '[^A-Za-z0-9]', '', 'g'));
  v_row public.vehicle_invite_codes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if v_code = '' then
    raise exception 'code_invalid';
  end if;

  perform set_config('app.redeeming_code', v_code, true);

  select * into v_row from public.vehicle_invite_codes where code = v_code;

  if not found then
    raise exception 'code_invalid';
  elsif v_row.status = 'cancelled' then
    raise exception 'code_cancelled';
  elsif v_row.status = 'accepted' then
    raise exception 'code_already_used';
  elsif v_row.expires_at <= now() then
    raise exception 'code_expired';
  end if;

  update public.vehicle_invite_codes
    set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
    where code = v_code and status = 'active' and expires_at > now()
    returning * into v_row;

  if not found then
    raise exception 'code_invalid';
  end if;

  insert into public.vehicle_members (vehicle_id, user_id, role, invited_by)
  values (v_row.vehicle_id, auth.uid(), v_row.role, v_row.created_by)
  on conflict (vehicle_id, user_id)
  do update set role = excluded.role, last_activity_at = now();

  update public.vehicle_members
    set last_activity_at = now()
    where vehicle_id = v_row.vehicle_id and user_id = auth.uid();

  return query
    select v.id, v.brand, v.model, v.plate, v_row.role
    from public.vehicles v where v.id = v_row.vehicle_id;
end;
$$;

grant execute on function public.preview_vehicle_invite(text) to authenticated;
grant execute on function public.accept_vehicle_invite(text) to authenticated;

-- 6. Realtime - so a revoked/downgraded member, and an owner watching
--    their access list, both see changes within a second or two instead
--    of waiting for the next periodic sync pass.
alter publication supabase_realtime add table public.vehicle_members;
