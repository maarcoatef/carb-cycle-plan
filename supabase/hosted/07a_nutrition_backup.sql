-- READ-ONLY backup before the Nutrition reset. Run in the SQL editor (project oxqcprgreelxfjhlqpxl), click the `backup_json` cell, copy it and save it as a file
-- (for example nutrition-backup-before-reset.json) OUTSIDE the repo. Keep it until you are happy with the new plan.
-- It contains exactly what 07_nutrition_reset.sql deletes or changes, plus counts of everything that must NOT change.
select jsonb_pretty(jsonb_build_object(
  'taken_at', now(),
  'will_be_deleted', jsonb_build_object(
    'meal_done',           (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.meal_done t),
    'doda_meal_items',     (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.doda_meal_items t),
    'doda_meal_overrides', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.doda_meal_overrides t),
    'plan_base_items',     (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_base_items t)),
  'will_be_changed', jsonb_build_object(
    'plan_days',  (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_days t),
    'plan_meals', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_meals t),
    'plan_versions', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_versions t)),
  'must_not_change_counts', jsonb_build_object(
    'foods', (select count(*) from public.foods), 'exercises', (select count(*) from public.exercises), 'videos', (select count(*) from public.videos),
    'doda_workout_rows', (select count(*) from public.doda_workout_rows), 'doda_workout_rows_done', (select count(*) from public.doda_workout_rows where done),
    'doda_day_notes', (select count(*) from public.doda_day_notes), 'weight_entries', (select count(*) from public.weight_entries),
    'hydration_entries', (select count(*) from public.hydration_entries), 'user_settings', (select count(*) from public.user_settings),
    'targets_carb', (select count(*) from public.targets_carb), 'targets_day', (select count(*) from public.targets_day),
    'profiles', (select count(*) from public.profiles), 'auth_users', (select count(*) from auth.users))
)) as backup_json;
