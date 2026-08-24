-- Permis de conduire (mission 2026): a personal (driver-level, not
-- vehicle-level) reminder has no single vehicle to belong to. RLS already
-- scopes every reminder by `user_id = auth.uid()` (unaffected by this
-- change - `user_id` still defaults to auth.uid() on insert), so a
-- nullable vehicle_id is enough: no policy changes needed.
alter table public.reminders alter column vehicle_id drop not null;
