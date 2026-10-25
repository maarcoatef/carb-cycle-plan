-- NOT APPLIED. Run only after 08a (backup saved) and only with your explicit approval.  Works whether or not 07_nutrition_reset.sql was run.
-- DOES:    (1) relaxes checks so the plan, workouts and day notes can use 56 days; carb_type may be empty
--          (2) adds plan days 29-56 (weeks 5-8) with the 5 empty meal slots each (breakfast, lunch, dinner, snack, iced coffee); existing day/meal ids are unchanged
--          (3) clears carb_type on every day
--          (4) deletes ONLY the meal check-offs (public.meal_done) = "all meals Not Completed"
--          (5) activates a new plan version so every browser drops its cached copy
-- KEEPS:   every food assignment + quantity (plan_base_items, doda_meal_items, doda_meal_overrides), foods, exercises, videos, ALL workout rows/notes/progress,
--          hydration, weight, targets, profile/settings, users/roles.
begin;
do $$ begin
  if (select count(*) from public.plan_days) <> 28 then raise exception 'expected exactly the 28 existing plan days - nothing done'; end if;
  if not exists (select 1 from public.plan_versions where is_active) then raise exception 'no active plan version - nothing done'; end if;
end $$;
alter table public.plan_days
  drop constraint plan_days_week_no_check,    add constraint plan_days_week_no_check    check (week_no between 1 and 8),
  drop constraint plan_days_day_number_check, add constraint plan_days_day_number_check check (day_number between 1 and 56),
  alter column carb_type drop not null;
alter table public.doda_workout_rows drop constraint doda_workout_rows_day_index_check, add constraint doda_workout_rows_day_index_check check (day_index between 0 and 55);
alter table public.doda_day_notes    drop constraint doda_day_notes_day_index_check,    add constraint doda_day_notes_day_index_check    check (day_index between 0 and 55);

create temp table _nv on commit drop as select max(version) + 1 as v from public.plan_versions;
insert into public.plan_versions (version, label, source_file, is_active) select v, 'Weight Loss Challenge: 8-week plan, no carb types', 'extend', false from _nv;
update public.plan_days set version = (select v from _nv), carb_type = null;
insert into public.plan_days (day_id, week_no, day_number, weekday, carb_type, version, pdf_total, pdf_updated_kcal)
  select 'v2-w' || ((n - 1) / 7 + 1) || '-d' || n, (n - 1) / 7 + 1, n,
         (array['Saturday','Sunday','Monday','Tuesday','Wednesday','Thursday','Friday'])[(n - 1) % 7 + 1], null, (select v from _nv), null, null
  from generate_series(29, 56) as n;
insert into public.plan_meals (meal_id, day_id, key, name, sort, is_coffee, pdf_total)
  select d.day_id || '-' || s.key, d.day_id, s.key, s.name, s.sort, s.key = 'coffee', null
  from public.plan_days d cross join (values ('breakfast','Breakfast',0),('lunch','Lunch',1),('dinner','Dinner',2),('snack','Snack',3),('coffee','Daily Iced Coffee',4)) as s(key, name, sort)
  where d.day_number between 29 and 56;
delete from public.meal_done;
update public.plan_versions set is_active = false where is_active;
update public.plan_versions set is_active = true where version = (select v from _nv);
commit;
