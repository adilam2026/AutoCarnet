-- Finition / niveau d'équipement (mission 2026: précision de l'estimation
-- de revente): structured, closed-set data the resale valuation engine can
-- apply a generic coefficient to - distinct from the existing free-text
-- `trim` column ("version" descriptor like "Cosmo", "Life"). Existing rows
-- simply have no level (nullable) rather than a guessed one.
alter table public.vehicles add column if not exists finish_level text;
