-- NOT APPLIED. Run only after 07a (backup saved) and only with your explicit approval.
-- Nutrition reset: empties ALL 28 days of the nutrition plan but keeps the 28-day structure (day ids, meal slots, carb types).
--   DELETES:  Doda's meal check-offs (meal_done), her meal edits (doda_meal_items, doda_meal_overrides) and the imported PDF foods of the plan (plan_base_items).
--   CHANGES:  the 28 plan days/meals lose their PDF reference totals; a new plan version 3 ("empty plan") becomes the active one.  The day ids stay the same,
--             so hydration history (keyed by day) is untouched.
--   KEEPS:    foods + categories, exercises, videos, ALL workout rows/notes/progress, weight, hydration, targets (carb-type and per-day), profile/settings, users/roles.
-- Single transaction; refuses to run twice; nothing outside the tables named above is touched.
begin;
do $$ begin
  if exists (select 1 from public.plan_versions where version = 3) then raise exception 'plan version 3 already exists - nothing done'; end if;
  if (select count(*) from public.plan_days where version = 2) <> 28 then raise exception 'expected the 28 days of plan version 2 - nothing done'; end if;
end $$;
delete from public.meal_done;
delete from public.doda_meal_items;
delete from public.doda_meal_overrides;
delete from public.plan_base_items where meal_id in (select m.meal_id from public.plan_meals m join public.plan_days d using (day_id) where d.version = 2);
update public.plan_meals set pdf_total = null where day_id in (select day_id from public.plan_days where version = 2);
insert into public.plan_versions (version, label, source_file, is_active) values (3, 'nutrition reset: empty 28-day plan', 'reset', false);
update public.plan_days set version = 3, pdf_total = null, pdf_updated_kcal = null where version = 2;
update public.plan_versions set is_active = false where is_active;
update public.plan_versions set is_active = true where version = 3;
commit;
