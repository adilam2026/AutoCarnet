-- ---------------------------------------------------------------------------
-- The 42702 ("column reference \"vehicle_id\" is ambiguous") error
-- persisted live even after 0007 qualified the one bare reference found by
-- manual review - confirmed via Postgres logs, same error, same function,
-- after 0007 had been (re-)applied. That means at least one more bare
-- reference to an OUT-parameter name exists somewhere in the function body
-- that reviewing line by line did not catch (the prime suspect being the
-- `on conflict (vehicle_id, user_id)` target list, or PL/pgSQL's default
-- `variable_conflict = error` behavior applying somewhere less obvious than
-- expected).
--
-- Rather than keep hunting for the exact remaining spot, this migration
-- removes the entire class of bug: renames the function's RETURNS TABLE
-- columns so none of them can ever again collide with a real table column
-- name (vehicle_id, brand, model, plate, role all exist as literal columns
-- on vehicles/vehicle_members/vehicle_invite_codes). With out_-prefixed
-- names, no bare identifier inside the function body - now or in any
-- future edit - can ever again be ambiguous with an OUT parameter, because
-- no table in this schema has a column literally named out_vehicle_id,
-- out_brand, etc.
--
-- The API-visible change: the RPC's JSON response now uses these renamed
-- keys - SharingRepository.acceptInvite() (Dart) is updated in the same
-- commit to match.
-- ---------------------------------------------------------------------------

-- Dropped first: renaming the return columns changes the function's row
-- type, and Postgres refuses `create or replace function` across a return
-- type change (42P13 - "cannot change return type of existing function"),
-- same as preview_vehicle_invite() needed in 0006. Safe: nothing else in
-- the schema depends on this function.
drop function if exists public.accept_vehicle_invite(text);

create function public.accept_vehicle_invite(p_code text)
returns table (
  out_vehicle_id uuid,
  out_brand text,
  out_model text,
  out_plate text,
  out_role text
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

  update public.vehicle_members m
    set last_activity_at = now()
    where m.vehicle_id = v_row.vehicle_id and m.user_id = auth.uid();

  return query
    select v.id, v.brand, v.model, v.plate, v_row.role
    from public.vehicles v where v.id = v_row.vehicle_id;
end;
$$;

grant execute on function public.accept_vehicle_invite(text) to authenticated;
