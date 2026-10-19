-- Phase 3B: keep each workout row's free-text video label and link (legacy per-exercise fields) in the cloud.
-- Additive and backward compatible: existing rows get ''. RLS/grants already cover the table (owner-only, Doda).
alter table public.doda_workout_rows
  add column video_label text not null default '' check (length(video_label) <= 200),
  add column video_url   text not null default '' check (length(video_url) <= 2048 and (video_url = '' or video_url ~* '^https?://'));
