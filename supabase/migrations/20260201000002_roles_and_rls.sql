-- Role helpers, grants and Row Level Security for EVERY table in public.
-- Authorization is decided only by public.profiles.role resolved from auth.uid() — never by e-mail strings.

create function public.app_role() returns text language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = (select auth.uid())
$$;
create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role() = 'admin', false)
$$;
create function public.is_doda() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.app_role() = 'doda', false)
$$;
revoke all on function public.app_role(), public.is_admin(), public.is_doda() from public, anon;
grant execute on function public.app_role(), public.is_admin(), public.is_doda() to authenticated;

-- 1) start from zero privileges: anonymous users get nothing, authenticated users get only what is granted below
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon;

-- 2) enable RLS everywhere
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop; end $$;

-- 3) profiles: a user can read ONLY her own row; nobody can insert/update/delete through the API (roles are server-assigned)
grant select on public.profiles to authenticated;
create policy profiles_read_own on public.profiles for select to authenticated using (id = (select auth.uid()));

-- 4) immutable PDF baseline: readable by the two app roles, not writable through the API at all
grant select on public.plan_days, public.plan_meals, public.plan_base_items to authenticated;
do $$ declare t text; begin
  foreach t in array array['plan_days','plan_meals','plan_base_items'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.app_role() is not null)', t||'_read', t);
  end loop; end $$;

-- 5) master data: any app user may read, only admins may write
do $$ declare t text; begin
  foreach t in array array['videos','foods','exercises','targets_carb','targets_day'] loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.app_role() is not null)', t||'_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.is_admin())', t||'_admin_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())', t||'_admin_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.is_admin())', t||'_admin_delete', t);
  end loop; end $$;

-- 6) Doda's private data: only the owner, and only while she holds the doda role. Admin has NO policy here → no access.
do $$ declare t text; begin
  foreach t in array array['doda_meal_items','meal_done','doda_workout_rows','doda_day_notes','hydration_entries','weight_entries','user_settings','migrations'] loop
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for all to authenticated using (user_id = (select auth.uid()) and public.is_doda()) with check (user_id = (select auth.uid()) and public.is_doda())', t||'_owner', t);
  end loop; end $$;
