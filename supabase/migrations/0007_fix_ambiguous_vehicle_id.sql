-- ---------------------------------------------------------------------------
-- Fixes the real cause of every "Rejoindre un véhicule" failure: confirmed
-- live as Postgres error 42702 - "column reference \"vehicle_id\" is
-- ambiguous".
--
-- accept_vehicle_invite() is declared `returns table (vehicle_id uuid,
-- brand text, model text, plate text, role text)`. PL/pgSQL implicitly
-- declares an OUT variable for every column in a RETURNS TABLE clause, so
-- inside the function body a bare `vehicle_id` can bind to *either* that
-- OUT parameter *or* a same-named column in scope - and one statement did
-- use it bare:
--
--   update public.vehicle_members
--     set last_activity_at = now()
--     where vehicle_id = v_row.vehicle_id and user_id = auth.uid();
--
-- `vehicle_id` here is ambiguous between the OUT parameter and
-- vehicle_members.vehicle_id (same for `user_id`, though that one isn't a
-- return column here so it happened not to trigger). This line has been
-- unchanged since the original 0004_vehicle_sharing.sql - meaning this is
-- not a regression from a later change, it's the feature's original bug:
-- the membership row itself was already being inserted successfully by
-- the time this statement ran, but the function then errored out before
-- ever returning, so every accept looked like a total failure to the
-- client even though the membership half of it had actually worked.
--
-- Fix: qualify every column reference in that statement (and re-verified
-- every other statement in both functions - already correctly qualified
-- elsewhere, this was the only bare one).
-- ---------------------------------------------------------------------------

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

  if v_owner_id = auth.uid() then
    raise exception 'already_owner';
  end if;

  select exists(
    select 1 from public.vehicle_members m
    where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid()
  ) into v_already_member;

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

  -- Explicitly qualified (m.vehicle_id, m.user_id) - the bare
  -- vehicle_id/user_id this replaces were the source of the 42702 error.
  update public.vehicle_members m
    set last_activity_at = now()
    where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid();

  return query
    select v.id, v.brand, v.model, v.plate, v_row.role
    from public.vehicles v where v.id = v_row.vehicle_id;
end;
$$;

grant execute on function public.accept_vehicle_invite(text) to authenticated;
