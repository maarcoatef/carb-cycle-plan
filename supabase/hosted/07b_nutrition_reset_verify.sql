-- READ-ONLY. After 07_nutrition_reset.sql.  Compare the last column with `must_not_change_counts` from your 07a backup.
select 'nutrition (all must be 0)' as check, (select count(*) from public.plan_base_items) as base_items, (select count(*) from public.doda_meal_items) as meal_items,
       (select count(*) from public.doda_meal_overrides) as overrides, (select count(*) from public.meal_done) as meal_done;
select 'structure kept (28 / 140 / active version 3)' as check, (select count(*) from public.plan_days where version = 3) as days,
       (select count(*) from public.plan_meals) as meals, (select version from public.plan_versions where is_active) as active_version;
select 'unchanged: compare with the backup' as check, (select count(*) from public.foods) as foods, (select count(*) from public.exercises) as exercises, (select count(*) from public.videos) as videos,
       (select count(*) from public.doda_workout_rows) as workout_rows, (select count(*) from public.doda_workout_rows where done) as workouts_done,
       (select count(*) from public.hydration_entries) as hydration, (select count(*) from public.weight_entries) as weights, (select count(*) from public.targets_carb) as targets_carb;
