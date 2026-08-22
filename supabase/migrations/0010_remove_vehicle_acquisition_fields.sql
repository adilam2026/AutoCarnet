-- The "Acquisition" section (date d'acquisition + prix d'achat) is removed
-- from the vehicle sheet entirely - by explicit choice, accepting that the
-- internal valuation engine (Revendre) now always uses its own reference
-- price instead of a real purchase price, rather than keeping a UI section
-- and columns nobody should see again. Any value a vehicle already had in
-- these columns is lost - there was no other consumer of this data outside
-- the valuation engine, which is updated in the same app release to no
-- longer read either column.
alter table public.vehicles drop column if exists acquisition_date;
alter table public.vehicles drop column if exists purchase_price;
