-- ---------------------------------------------------------------------------
-- Fixes the "Rejoindre un véhicule" crash: the join journey never had a
-- clean way to recognize "you already have access" (either as an existing
-- vehicle_members row, or as the vehicle's owner) *before* re-running
-- accept_vehicle_invite() - which could otherwise consume a still-active
-- code and, for an owner testing their own code, insert a redundant
-- self-membership row. This migration teaches both RPCs to recognize those
-- two cases explicitly instead of just re-running the normal join path.
-- ---------------------------------------------------------------------------

-- preview_vehicle_invite(): now also reports whether the caller already has
-- access, so the UI can show "Vous avez déjà accès" / "Vous êtes déjà
-- propriétaire" and skip straight to opening the vehicle, never presenting
-- a "Rejoindre" action that would be a no-op (or worse, a wasted code) in
-- either case.
--
-- Dropped first: this adds two new return columns (already_member,
-- already_owner) to the existing 0004 signature, and Postgres refuses
-- `create or replace function` when the return row type changes (42P13 -
-- "cannot change return type of existing function"). Safe here: nothing
-- else in the schema depends on this function (no view/policy calls it,
-- only the app via RPC), so dropping and recreating it is a no-op for
-- everything except the function itself.
drop function if exists public.preview_vehicle_invite(text);

create function public.preview_vehicle_invite(p_code text)
returns table (
  vehicle_id uuid,
  brand text,
  model text,
  plate text,
  owner_display_name text,
  role text,
  expires_at timestamptz,
  already_member boolean,
  already_owner boolean
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
    select
      v_row.vehicle_id,
      v.brand,
      v.model,
      v.plate,
      p.display_name,
      v_row.role,
      v_row.expires_at,
      exists(
        select 1 from public.vehicle_members m
        where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid()
      ) as already_member,
      (v.user_id = auth.uid()) as already_owner
    from public.vehicles v
    join public.profiles p on p.id = v.user_id
    where v.id = v_row.vehicle_id;
end;
$$;

-- accept_vehicle_invite(): hard guards mirroring the preview flags, so a
-- direct call (bypassing the preview step) can never consume a code or
-- create a duplicate/redundant membership row for someone who already has
-- access.
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
  v_owner_id uuid;
  v_already_member boolean;
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

  select user_id into v_owner_id from public.vehicles where id = v_row.vehicle_id;

  -- Owner redeeming their own code: never consume the code or create a
  -- self-membership row - the owner already has full access via
  -- vehicles.user_id, not via vehicle_members.
  if v_owner_id = auth.uid() then
    raise exception 'already_owner';
  end if;

  select exists(
    select 1 from public.vehicle_members m
    where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid()
  ) into v_already_member;

  -- Already a member (e.g. via an earlier code): return the existing
  -- access as-is, without touching this code's status - it stays
  -- available for whoever it was actually meant for.
  if v_already_member then
    return query
      select v.id, v.brand, v.model, v.plate, m.role
      from public.vehicles v
      join public.vehicle_members m on m.vehicle_id = v.id and m.user_id = auth.uid()
      where v.id = v_row.vehicle_id;
    return;
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
