-- Plan versioning + full-sync support.  Additive: the hosted baseline tables are still empty, so nothing is rewritten.
--  • plan_versions: one row per imported PDF; exactly one may be active.  A new PDF becomes a NEW version with its own ids
--    (v2-w1-d1 …): old baseline rows and anyone's progress that points at them are never deleted or re-pointed.
--  • progress tables (meal_done, doda_meal_items, doda_meal_overrides, hydration_entries, targets_day) now RESTRICT deletes of
--    baseline rows instead of cascading, so removing a baseline row can never silently delete progress.
--  • doda_meal_overrides marks "this meal is Doda's own working copy" (so a copy with zero foods is distinguishable from "untouched").

create table public.plan_versions (
  version       int primary key check (version >= 1),
  label         text not null,
  source_file   text,
  source_sha256 text,
  imported_at   timestamptz not null default now(),
  is_active     boolean not null default false
);
create unique index plan_versions_one_active on public.plan_versions ((true)) where is_active;
insert into public.plan_versions (version, label) values (1, 'legacy placeholder (no baseline imported)');

alter table public.plan_days add column version int not null default 1 references public.plan_versions(version) on delete restrict;
alter table public.plan_days drop constraint plan_days_day_number_key;
alter table public.plan_days add constraint plan_days_version_day_number_key unique (version, day_number);
create index plan_days_version_idx on public.plan_days(version);

create table public.doda_meal_overrides (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  meal_id    text not null references public.plan_meals(meal_id) on delete restrict,
  updated_at timestamptz not null default now(),
  primary key (user_id, meal_id)
);
create trigger doda_meal_overrides_touch before update on public.doda_meal_overrides for each row execute function public.touch_updated_at();

-- never cascade-delete progress
alter table public.doda_meal_items  drop constraint doda_meal_items_meal_id_fkey,  add constraint doda_meal_items_meal_id_fkey  foreign key (meal_id) references public.plan_meals(meal_id) on delete restrict;
alter table public.meal_done        drop constraint meal_done_meal_id_fkey,        add constraint meal_done_meal_id_fkey        foreign key (meal_id) references public.plan_meals(meal_id) on delete restrict;
alter table public.hydration_entries drop constraint hydration_entries_day_id_fkey, add constraint hydration_entries_day_id_fkey foreign key (day_id)  references public.plan_days(day_id)   on delete restrict;
alter table public.targets_day      drop constraint targets_day_day_id_fkey,       add constraint targets_day_day_id_fkey       foreign key (day_id)  references public.plan_days(day_id)   on delete restrict;

-- RLS + privileges (same model as the other tables)
alter table public.plan_versions        enable row level security; alter table public.plan_versions        force row level security;
alter table public.doda_meal_overrides  enable row level security; alter table public.doda_meal_overrides  force row level security;
grant select on public.plan_versions to authenticated;
create policy plan_versions_read on public.plan_versions for select to authenticated using (public.app_role() is not null);
grant select, insert, update, delete on public.doda_meal_overrides to authenticated;
create policy doda_meal_overrides_owner on public.doda_meal_overrides for all to authenticated
  using (user_id = (select auth.uid()) and public.is_doda()) with check (user_id = (select auth.uid()) and public.is_doda());
