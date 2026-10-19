-- NOT APPLIED. Hosted counterpart of migration 20260201000007 (target ranges). Run first; additive, existing rows untouched.
-- Target ranges: protein and carbs can have a minimum and/or maximum (e.g. protein 100–110 g, High-carb days 200–250 g, Low ≤100 g).
-- Additive: the existing single-value columns stay and keep working when no range is set. RLS/grants already cover both tables.
alter table public.targets_carb
  add column p_min numeric check (p_min >= 0), add column p_max numeric check (p_max >= 0),
  add column c_min numeric check (c_min >= 0), add column c_max numeric check (c_max >= 0),
  add constraint targets_carb_p_range check (p_min is null or p_max is null or p_min <= p_max),
  add constraint targets_carb_c_range check (c_min is null or c_max is null or c_min <= c_max);
alter table public.targets_day
  add column p_min numeric check (p_min >= 0), add column p_max numeric check (p_max >= 0),
  add column c_min numeric check (c_min >= 0), add column c_max numeric check (c_max >= 0),
  add constraint targets_day_p_range check (p_min is null or p_max is null or p_min <= p_max),
  add constraint targets_day_c_range check (c_min is null or c_max is null or c_min <= c_max);
