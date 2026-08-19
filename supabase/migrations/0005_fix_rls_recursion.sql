-- Fix: infinite recursion between public.vehicles and public.vehicle_members
-- RLS policies (Postgres error 42P17).
-- ---------------------------------------------------------------------------
-- 0004 gave vehicle_members' "select/update/delete as owner" policies an
-- `exists (select 1 from vehicles v where v.id = vehicle_id and v.user_id
-- = auth.uid())` check. But vehicles' own select/update policies (also
-- from 0004) check `exists (select 1 from vehicle_members ...)` to let a
-- collaborator see a shared vehicle. Evaluating either table's RLS then
-- requires evaluating the other's, which requires the first's again -
-- Postgres detects the cycle and refuses the query outright, for every
-- single query against either table (confirmed live: querying
-- vehicle_members failed with "infinite recursion detected in policy for
-- relation vehicle_members", and vehicle_invite_codes - which itself
-- queries vehicles - failed the same way one hop further out).
--
-- Fix: vehicle_members no longer needs to ask `vehicles` "is this your
-- vehicle" - `vehicle_members.invited_by` is always already the vehicle's
-- owner (the only way a code, and therefore a membership row, is ever
-- created is via "owner creates codes" on vehicle_invite_codes, which
-- requires created_by = the owner; accept_vehicle_invite() carries that
-- same value into invited_by). Checking `invited_by = auth.uid()` answers
-- "am I the owner of this membership's vehicle" from the row itself, with
-- no subquery into vehicles at all - breaking the cycle in that direction
-- while keeping vehicles -> vehicle_members intact (still needed so a
-- collaborator can see the shared vehicle).
-- ---------------------------------------------------------------------------

alter policy "select own membership or as owner" on public.vehicle_members
  using (
    user_id = auth.uid() or invited_by = auth.uid()
  );

alter policy "owner updates member role" on public.vehicle_members
  using (
    invited_by = auth.uid()
  ) with check (
    invited_by = auth.uid()
  );

alter policy "owner revokes member" on public.vehicle_members
  using (
    invited_by = auth.uid()
  );

notify pgrst, 'reload schema';
