-- READ-ONLY backup: run in the SQL editor and save the single JSON value it returns (Export / copy cell) before importing.
select jsonb_pretty(jsonb_build_object(
  'taken_at', now(),
  'plan_versions', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_versions t),
  'plan_days',      (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_days t),
  'plan_meals',     (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_meals t),
  'plan_base_items',(select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.plan_base_items t),
  'foods',          (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.foods t),
  'targets_carb',   (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.targets_carb t),
  'targets_day',    (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.targets_day t),
  'doda_meal_items',(select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.doda_meal_items t),
  'doda_meal_overrides', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.doda_meal_overrides t),
  'meal_done',      (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.meal_done t),
  'hydration_entries', (select coalesce(jsonb_agg(to_jsonb(t)), '[]') from public.hydration_entries t),
  'row_counts', jsonb_build_object('doda_workout_rows', (select count(*) from public.doda_workout_rows), 'weight_entries', (select count(*) from public.weight_entries), 'user_settings', (select count(*) from public.user_settings))
)) as backup_json;
