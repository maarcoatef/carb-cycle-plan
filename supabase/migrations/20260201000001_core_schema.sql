-- Core schema for Carb Cycle Plan.
-- Ownership model:  master data (admin writes) · immutable PDF baseline · Doda's private data (per-user rows).
-- Nothing here references e-mail addresses for authorization; roles live in public.profiles (see 0002/0004).

create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('admin','doda')),
  created_at timestamptz not null default now()
);
comment on table public.profiles is 'One row per authenticated user. Role is assigned server-side only (never by the client).';

-- ───────────── master data (admin-managed) ─────────────
create table public.videos (
  id         text primary key,
  title      text not null check (length(btrim(title)) between 1 and 160),
  url        text not null check (url ~* '^https?://\S+$'),
  type       text not null default 'Other',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.foods (
  id         text primary key,
  name       text not null check (length(btrim(name)) between 1 and 160),
  base_qty   numeric not null check (base_qty > 0 and base_qty <= 100000),
  unit       text not null check (unit in ('g','ml','piece','slice','serving')),
  kcal       numeric check (kcal  is null or kcal  >= 0),
  p          numeric check (p     is null or p     >= 0),
  c          numeric check (c     is null or c     >= 0),
  f          numeric check (f     is null or f     >= 0),
  fiber      numeric check (fiber is null or fiber >= 0),
  cats       text[] not null default '{}' check (cats <@ array['breakfast','lunch','dinner','snack','coffee']),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index foods_name_uq on public.foods (lower(btrim(name)));
create table public.exercises (
  id               text primary key,
  name             text not null check (length(btrim(name)) between 1 and 160),
  intensity        text not null default 'Moderate' check (intensity in ('Low','Moderate','High')),
  minutes          numeric not null default 0 check (minutes between 0 and 1440),
  kcal             numeric not null default 0 check (kcal >= 0),
  default_video_id text references public.videos(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index exercises_name_uq on public.exercises (lower(btrim(name)));

-- ───────────── plan baseline (original PDF values; seeded once, never editable through the API) ─────────────
create table public.plan_days (
  day_id        text primary key,                       -- e.g. w1-d3
  week_no       smallint not null check (week_no between 1 and 4),
  day_number    smallint not null unique check (day_number between 1 and 28),
  weekday       text not null,
  carb_type     text not null check (carb_type in ('Low','Moderate','High')),
  pdf_total     jsonb,
  pdf_updated_kcal numeric
);
create table public.plan_meals (
  meal_id   text primary key,                            -- e.g. w1-d3-breakfast, w1-d3-coffee
  day_id    text not null references public.plan_days(day_id) on delete cascade,
  key       text not null,
  name      text not null,
  sort      smallint not null default 0,
  is_coffee boolean not null default false,
  pdf_total jsonb
);
create table public.plan_base_items (
  id       text primary key,
  meal_id  text not null references public.plan_meals(meal_id) on delete cascade,
  sort     smallint not null default 0,
  name     text not null,
  quantity text,
  grams    numeric,
  kcal numeric, p numeric, c numeric, f numeric, fiber numeric,   -- exact PDF values (null = not specified)
  qty      numeric,
  unit     text
);
create index plan_meals_day_idx on public.plan_meals(day_id);
create index plan_base_items_meal_idx on public.plan_base_items(meal_id);

-- targets (admin): by carb type, optionally overridden per day. NULL = inherit (day → carb type → PDF baseline)
create table public.targets_carb (
  carb_type text primary key check (carb_type in ('Low','Moderate','High')),
  kcal numeric check (kcal >= 0), p numeric check (p >= 0), c numeric check (c >= 0), f numeric check (f >= 0), fiber numeric check (fiber >= 0),
  updated_at timestamptz not null default now()
);
create table public.targets_day (
  day_id text primary key references public.plan_days(day_id) on delete cascade,
  kcal numeric check (kcal >= 0), p numeric check (p >= 0), c numeric check (c >= 0), f numeric check (f >= 0), fiber numeric check (fiber >= 0),
  updated_at timestamptz not null default now()
);

-- ───────────── Doda's private data (every row owned by a user; RLS = owner only) ─────────────
create table public.doda_meal_items (            -- Doda's working copy of the plan (quantity overrides, added/removed foods)
  id           text primary key,
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  meal_id      text not null references public.plan_meals(meal_id) on delete cascade,
  base_item_id text references public.plan_base_items(id) on delete set null,
  food_id      text references public.foods(id) on delete set null,
  name         text not null,
  quantity     text,
  qty          numeric check (qty is null or (qty >= 0 and qty <= 100000)),
  unit         text,
  kcal numeric, p numeric, c numeric, f numeric, fiber numeric,
  calc         boolean not null default false,     -- false = original PDF values kept until the first edit
  flag         text,
  sort         smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index doda_meal_items_user_meal_idx on public.doda_meal_items(user_id, meal_id);
create table public.meal_done (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  meal_id text not null references public.plan_meals(meal_id) on delete cascade,
  done_at timestamptz not null default now(),
  primary key (user_id, meal_id)
);
create table public.doda_workout_rows (
  id          text primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_index   smallint not null check (day_index between 0 and 27),
  sort        smallint not null default 0,
  exercise_id text references public.exercises(id) on delete set null,
  name        text not null,
  minutes     numeric not null default 0 check (minutes between 0 and 1440),
  kcal        numeric not null default 0 check (kcal >= 0),
  intensity   text not null default 'Moderate' check (intensity in ('Low','Moderate','High')),
  video_id    text references public.videos(id) on delete set null,
  notes       text not null default '',
  done        boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index doda_workout_rows_user_day_idx on public.doda_workout_rows(user_id, day_index);
create table public.doda_day_notes (
  user_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_index smallint not null check (day_index between 0 and 27),
  notes     text not null default '',
  updated_at timestamptz not null default now(),
  primary key (user_id, day_index)
);
create table public.hydration_entries (
  id        text primary key,
  user_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day_id    text not null references public.plan_days(day_id) on delete cascade,
  ml        integer not null check (ml between 1 and 10000),
  logged_at timestamptz not null default now()
);
create index hydration_user_day_idx on public.hydration_entries(user_id, day_id);
create table public.weight_entries (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  entry_date date not null,
  kg         numeric not null check (kg between 20 and 500),
  created_at timestamptz not null default now()
);
create index weight_user_date_idx on public.weight_entries(user_id, entry_date);
create table public.user_settings (
  user_id          uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  display_name     text check (length(display_name) <= 80),
  gender           text check (gender in ('Female','Male','Other')),
  height_cm        numeric check (height_cm is null or height_cm between 80 and 260),
  birthday         date,
  plan_start       date,
  weight_start     numeric check (weight_start is null or weight_start between 20 and 500),
  weight_goal      numeric check (weight_goal  is null or weight_goal  between 20 and 500),
  hydration_goal_ml integer not null default 3000 check (hydration_goal_ml between 500 and 10000),
  theme            text check (theme in ('light','dark')),
  photo_path       text,                           -- object path inside the private profile-photos bucket
  updated_at       timestamptz not null default now()
);
create table public.migrations (                 -- idempotency markers for the one-time localStorage import (later phase)
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name       text not null,
  applied_at timestamptz not null default now(),
  primary key (user_id, name)
);

-- generic updated_at trigger
create function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function public.touch_updated_at() from public, anon, authenticated;   -- trigger-only helper: not callable through the API
do $$ declare t text; begin
  foreach t in array array['videos','foods','exercises','targets_carb','targets_day','doda_meal_items','doda_workout_rows','doda_day_notes','user_settings'] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.touch_updated_at()', t||'_touch', t);
  end loop; end $$;
