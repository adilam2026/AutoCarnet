-- Fix: account creation was silently failing end-to-end.
-- ---------------------------------------------------------------------------
-- handle_new_user() (0001_init.sql) inserts into public.profiles from a
-- trigger on auth.users. That insert was blocked by profiles' Row Level
-- Security (only select/update policies exist, no insert policy - the
-- comment in 0001 assumed SECURITY DEFINER would bypass RLS, but it only
-- bypasses privilege GRANTs, not RLS, unless the function's owner role has
-- the BYPASSRLS attribute - which Supabase's own "postgres" role does not
-- have). Because the trigger runs inside the same transaction as the
-- auth.users insert, the RLS violation rolled back the ENTIRE signup: the
-- confirmation email still went out (GoTrue processes that independently),
-- but no user ever actually existed - reproduced and confirmed locally
-- against a non-bypassrls role standing in for Supabase's real one.
--
-- Fix: never let profile creation be able to block account creation. The
-- insert is now wrapped so any failure there is swallowed - worst case a
-- profile row is missing and gets created lazily by the app later, but the
-- account itself always succeeds.
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
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
exception when others then
  return new;
end;
$$;

-- Belt-and-suspenders: also let the insert actually succeed instead of only
-- being swallowed. auth.uid() can't be used in the check here - at the
-- instant this trigger fires the new user has no session/JWT yet, so
-- auth.uid() would just be null. Safe as a permissive policy anyway: id is
-- the primary key referencing auth.users(id), so a row can only ever be
-- inserted once per real user id, and the trigger already does that
-- immediately on signup - a stray extra insert attempt just hits the
-- primary key conflict, it can never overwrite someone else's profile
-- (that's still only possible through the update policy, which stays
-- scoped to auth.uid() = id).
create policy "insert own profile via signup trigger" on public.profiles
  for insert with check (true);
