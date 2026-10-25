-- READ-ONLY backup before the 8-week extension + completion reset. Run in the SQL editor (project oxqcprgreelxfjhlqpxl), click the `backup_json` cell, copy and
-- save it OUTSIDE the repo (for example weeks8-backup-before.json). `will_be_deleted` = the meal check-offs; `will_be_changed` = plan structure rows.
-- `must_not_change_counts` is what 08b compares against.
select jsonb_pretty(jsonb_build_object(
  'taken_at', now(),
  'will_be_deleted', jsonb_build_object('meal_done', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.meal_done t)),
  'will_be_changed', jsonb_build_object(
    'plan_versions', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_versions t),
    'plan_days',     (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_days t)),
  'must_not_change_counts', jsonb_build_object(
    'plan_base_items', (select count(*) from public.plan_base_items), 'doda_meal_items', (select count(*) from public.doda_meal_items), 'doda_meal_overrides', (select count(*) from public.doda_meal_overrides),
    'plan_meals', (select count(*) from public.plan_meals),
    'foods', (select count(*) from public.foods), 'exercises', (select count(*) from public.exercises), 'videos', (select count(*) from public.videos),
    'doda_workout_rows', (select count(*) from public.doda_workout_rows), 'doda_workout_rows_done', (select count(*) from public.doda_workout_rows where done),
    'doda_day_notes', (select count(*) from public.doda_day_notes), 'weight_entries', (select count(*) from public.weight_entries),
    'hydration_entries', (select count(*) from public.hydration_entries), 'user_settings', (select count(*) from public.user_settings),
    'targets_carb', (select count(*) from public.targets_carb), 'targets_day', (select count(*) from public.targets_day),
    'profiles', (select count(*) from public.profiles), 'auth_users', (select count(*) from auth.users))
)) as backup_json;
