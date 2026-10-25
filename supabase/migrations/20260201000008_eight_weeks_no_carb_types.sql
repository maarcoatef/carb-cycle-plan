-- 8-week / 56-day challenge and no carb types.  Additive/relaxing only: existing rows stay valid.
alter table public.plan_days
  drop constraint plan_days_week_no_check,    add constraint plan_days_week_no_check    check (week_no between 1 and 8),
  drop constraint plan_days_day_number_check, add constraint plan_days_day_number_check check (day_number between 1 and 56),
  alter column carb_type drop not null;                     -- (the existing check on carb_type still allows NULL)
alter table public.doda_workout_rows drop constraint doda_workout_rows_day_index_check, add constraint doda_workout_rows_day_index_check check (day_index between 0 and 55);
alter table public.doda_day_notes    drop constraint doda_day_notes_day_index_check,    add constraint doda_day_notes_day_index_check    check (day_index between 0 and 55);
