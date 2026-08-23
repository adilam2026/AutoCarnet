-- Per-vehicle home-dashboard card colour ("carte identité du véhicule",
-- design-review pass, Variante A): a distinct property from the existing
-- `color` column (the vehicle's real paint colour, a free-text
-- administrative field) - never merge the two. Existing rows are
-- backfilled transparently on the client (VehicleRepository.
-- backfillMissingCardColors), not here - this migration only adds the
-- column.
alter table public.vehicles add column if not exists card_color_key text;
