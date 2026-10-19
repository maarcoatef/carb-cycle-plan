-- Authorization tests (pgTAP). Run with:  supabase test db
-- Uses throw-away users inserted into auth.users; roles are assigned through public.bootstrap_roles (UUID resolution), never via policies on e-mail.
begin;
create extension if not exists pgtap with schema extensions;
select plan(114);
-- (local stacks without the storage service: apply supabase/support/local_storage_stub.sql first)
select public.setup_profile_photo_storage();

-- ── fixtures (as postgres) ──
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-000000000001','admin@test.invalid','authenticated','authenticated'),
  ('dddddddd-0000-0000-0000-000000000002','doda@test.invalid','authenticated','authenticated'),
  ('eeeeeeee-0000-0000-0000-000000000003','other@test.invalid','authenticated','authenticated'),
  ('99999999-0000-0000-0000-000000000004','stranger@test.invalid','authenticated','authenticated');
select lives_ok($$select public.bootstrap_roles('admin@test.invalid','doda@test.invalid')$$, 'bootstrap_roles resolves UUIDs and assigns roles');
select throws_ok($$select public.bootstrap_roles('doda@test.invalid','doda@test.invalid')$$, 'P0001', 'admin and doda must be different accounts', 'same account cannot hold both roles');
select throws_ok($$select public.bootstrap_roles('nobody@test.invalid','doda@test.invalid')$$, 'P0001', 'no auth user found for the admin e-mail', 'unknown e-mail rejected');
select is((select role from public.profiles where id='aaaaaaaa-0000-0000-0000-000000000001'), 'admin', 'admin UUID has role admin');
select is((select role from public.profiles where id='dddddddd-0000-0000-0000-000000000002'), 'doda',  'doda UUID has role doda');
select lives_ok($$select public.bootstrap_roles('admin@test.invalid','doda@test.invalid')$$, 'bootstrap is idempotent');
select is((select count(*)::int from public.profiles), 2, 'no duplicate profile rows');
insert into public.profiles(id, role) values ('eeeeeeee-0000-0000-0000-000000000003','doda');   -- a second doda-role user to test row isolation

insert into public.videos(id,title,url) values ('v1','V','https://youtu.be/x');
insert into public.foods(id,name,base_qty,unit,kcal,p,c,f,fiber,cats) values ('f1','Egg',2,'piece',144,12.6,.7,9.6,0,'{breakfast}');
insert into public.exercises(id,name) values ('e1','Plank');
insert into public.targets_carb(carb_type,kcal) values ('Low',1400);
insert into public.plan_days(day_id,week_no,day_number,weekday,carb_type) values ('w1-d1',1,1,'Saturday','Moderate');
insert into public.targets_day(day_id,kcal) values ('w1-d1',1500);
insert into public.plan_meals(meal_id,day_id,key,name) values ('w1-d1-breakfast','w1-d1','breakfast','Breakfast');
insert into public.plan_base_items(id,meal_id,name,kcal) values ('b1','w1-d1-breakfast','Whole egg',144);
-- doda's + other's private rows
insert into public.weight_entries(id,user_id,entry_date,kg) values ('w_d','dddddddd-0000-0000-0000-000000000002','2026-01-01',70),('w_o','eeeeeeee-0000-0000-0000-000000000003','2026-01-01',60);
insert into public.hydration_entries(id,user_id,day_id,ml) values ('h_d','dddddddd-0000-0000-0000-000000000002','w1-d1',500);
insert into public.meal_done(user_id,meal_id) values ('dddddddd-0000-0000-0000-000000000002','w1-d1-breakfast');
insert into public.doda_workout_rows(id,user_id,day_index,name) values ('x_d','dddddddd-0000-0000-0000-000000000002',0,'Walk');
insert into public.doda_meal_items(id,user_id,meal_id,name) values ('i_d','dddddddd-0000-0000-0000-000000000002','w1-d1-breakfast','Egg');
insert into public.user_settings(user_id,display_name) values ('dddddddd-0000-0000-0000-000000000002','Doda');
insert into public.doda_day_notes(user_id,day_index,notes) values ('dddddddd-0000-0000-0000-000000000002',0,'private');
insert into public.migrations(user_id,name) values ('dddddddd-0000-0000-0000-000000000002','m1');

create function pg_temp.act_as(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', u::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
end $$;
create temp table _priv(t text); insert into _priv values ('doda_meal_items'),('meal_done'),('doda_workout_rows'),('doda_day_notes'),('hydration_entries'),('weight_entries'),('user_settings'),('migrations');
create temp table _master(t text); insert into _master values ('videos'),('foods'),('exercises'),('targets_carb'),('targets_day');
create temp table _base(t text); insert into _base values ('plan_days'),('plan_meals'),('plan_base_items');
grant select on _priv, _master, _base to public;

-- ── structural checks ──
select is((select count(*)::int from pg_tables where schemaname='public' and not rowsecurity), 0, 'RLS is enabled on every public table');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relforcerowsecurity), 0, 'RLS is forced on every public table');
select is((select count(*)::int from pg_policies where schemaname in ('public','storage') and (coalesce(qual,'') ilike '%email%' or coalesce(with_check,'') ilike '%email%')), 0, 'no policy references e-mail addresses');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('app_role','is_admin','is_doda') and pg_get_functiondef(p.oid) ilike '%email%'), 0, 'role helper functions never look at e-mail');
select is((select count(*)::int from pg_policies where schemaname='public' and (qual='true' or with_check='true')), 0, 'no policy is unconditionally true');
select is((select public from storage.buckets where id='profile-photos'), false, 'profile-photos bucket is private');
select is((select file_size_limit from storage.buckets where id='profile-photos'), 2097152::bigint, 'profile-photos has a 2 MB limit');

-- ── anonymous: everything denied ──
reset role; set local role anon; select set_config('request.jwt.claims','',true);
select throws_ok(format('select 1 from public.%I', t), '42501', null, 'anon cannot read '||t) from (select t from _priv union all select t from _master union all select t from _base union all select 'profiles') x(t);
select throws_ok($$insert into public.foods(id,name,base_qty,unit) values ('x','X',1,'g')$$, '42501', null, 'anon cannot write master data');
select throws_ok($$select public.is_admin()$$, '42501', null, 'anon cannot call role helpers');
select throws_ok($$select public.bootstrap_roles('a','b')$$, '42501', null, 'anon cannot call bootstrap_roles');

-- ── authenticated user without a profile: no access ──
reset role; select pg_temp.act_as('99999999-0000-0000-0000-000000000004');
select is((select count(*)::int from public.foods), 0, 'user without a role sees no master data');
select is((select count(*)::int from public.plan_days), 0, 'user without a role sees no plan');
select throws_ok($$insert into public.foods(id,name,base_qty,unit) values ('x','X',1,'g')$$, '42501', null, 'user without a role cannot write');

-- ── Doda ──
reset role; select pg_temp.act_as('dddddddd-0000-0000-0000-000000000002');
select is((select count(*)::int from public.foods), 1, 'Doda can read the food catalog');
select is((select count(*)::int from public.plan_base_items), 1, 'Doda can read the PDF baseline');
select throws_ok(format('insert into public.%I default values', t), '42501', null, 'Doda cannot insert into '||t) from (select t from _master union all select t from _base) x(t) where t not in ('foods','videos','exercises','targets_carb','targets_day','plan_days','plan_meals','plan_base_items') or true;
select throws_ok($$insert into public.foods(id,name,base_qty,unit) values ('x','X',1,'g')$$, '42501', null, 'Doda cannot add foods');
select throws_ok($$insert into public.targets_day(day_id,kcal) values ('w1-d1',1)$$, '42501', null, 'Doda cannot set targets');
select lives_ok($$update public.foods set name='Hacked' where id='f1'$$, 'Doda update on master data runs but is filtered by RLS');
select lives_ok($$delete from public.foods where id='f1'$$, 'Doda delete on master data runs but is filtered by RLS');
select lives_ok($$update public.targets_carb set kcal=1 where carb_type='Low'$$, 'Doda target update filtered');
select throws_ok($$update public.plan_base_items set kcal=1$$, '42501', null, 'Doda cannot alter the PDF baseline (no privilege)');
select throws_ok($$delete from public.plan_meals$$, '42501', null, 'Doda cannot delete baseline meals');
-- own data
select lives_ok($$insert into public.weight_entries(id,entry_date,kg) values ('w_new','2026-02-01',69)$$, 'Doda can add her own weight (user_id defaults to auth.uid())');
select is((select count(*)::int from public.weight_entries), 2, 'Doda sees only her own weight rows');
select is((select count(*)::int from public.hydration_entries), 1, 'Doda reads her hydration');
select lives_ok($$insert into public.hydration_entries(id,day_id,ml) values ('h_new','w1-d1',250)$$, 'Doda logs water');
select throws_ok($$insert into public.hydration_entries(id,day_id,ml) values ('h_bad','w1-d1',0)$$, '23514', null, 'invalid hydration amount rejected');
select lives_ok($$update public.doda_workout_rows set done = true where id='x_d'$$, 'Doda completes her workout row');
-- ── Phase 3B: workout video label/url columns ──
select lives_ok($$update public.doda_workout_rows set video_label='My video', video_url='https://youtu.be/abc' where id='x_d'$$, 'migration 0005: Doda stores video label + https url');
select throws_ok($$update public.doda_workout_rows set video_url='javascript:alert(1)' where id='x_d'$$, '23514', null, 'migration 0005: non-http(s) url rejected');
select throws_ok($$update public.doda_workout_rows set video_url=repeat('a',2049) where id='x_d'$$, '23514', null, 'migration 0005: over-long url rejected');
select is((select video_label||'|'||video_url from public.doda_workout_rows where id='x_d'), 'My video|https://youtu.be/abc', 'migration 0005: values round-trip');
select lives_ok($$insert into public.meal_done(meal_id) values ('w1-d1-breakfast') on conflict do nothing$$, 'Doda marks a meal');
select lives_ok($$update public.user_settings set plan_start='2026-03-01' where user_id=auth.uid()$$, 'Doda edits her settings');
select throws_ok($$insert into public.weight_entries(id,user_id,entry_date,kg) values ('spoof','aaaaaaaa-0000-0000-0000-000000000001','2026-01-02',50)$$, '42501', null, 'Doda cannot write rows for another user (admin)');
select throws_ok($$insert into public.weight_entries(id,user_id,entry_date,kg) values ('spoof2','eeeeeeee-0000-0000-0000-000000000003','2026-01-02',50)$$, '42501', null, 'Doda cannot write rows for another doda-role user');
select lives_ok($$update public.weight_entries set kg = 1 where id='w_o'$$, 'update of another user''s row runs but affects nothing');
select lives_ok($$delete from public.weight_entries where id='w_o'$$, 'delete of another user''s row runs but affects nothing');
-- roles
select throws_ok($$update public.profiles set role='admin' where id=auth.uid()$$, '42501', null, 'Doda cannot change her own role');
select throws_ok($$insert into public.profiles(id,role) values (gen_random_uuid(),'admin')$$, '42501', null, 'Doda cannot create profiles');
select throws_ok($$delete from public.profiles$$, '42501', null, 'Doda cannot delete profiles');
select is((select count(*)::int from public.profiles), 1, 'Doda sees only her own profile');
select throws_ok($$select public.bootstrap_roles('admin@test.invalid','doda@test.invalid')$$, '42501', null, 'Doda cannot call bootstrap_roles');
-- storage
select lives_ok($$insert into storage.objects(bucket_id,name,owner) values ('profile-photos','dddddddd-0000-0000-0000-000000000002/avatar.jpg', auth.uid())$$, 'Doda can store a photo in her own folder');
select throws_ok($$insert into storage.objects(bucket_id,name,owner) values ('profile-photos','eeeeeeee-0000-0000-0000-000000000003/avatar.jpg', auth.uid())$$, '42501', null, 'Doda cannot store in another user''s folder');
select is((select count(*)::int from storage.objects where bucket_id='profile-photos'), 1, 'Doda sees her own photo');

-- verify (as postgres) that Doda's blocked writes really changed nothing
reset role;
select is((select name from public.foods where id='f1'), 'Egg', 'master food unchanged after Doda attempts');
select is((select count(*)::int from public.foods), 1, 'master food not deleted by Doda');
select is((select kcal from public.targets_carb where carb_type='Low'), 1400::numeric, 'target unchanged after Doda attempt');
select is((select kg from public.weight_entries where id='w_o'), 60::numeric, 'other user''s row untouched');
select is((select role from public.profiles where id='dddddddd-0000-0000-0000-000000000002'), 'doda', 'Doda role unchanged');
insert into storage.objects(bucket_id,name,owner) values ('profile-photos','eeeeeeee-0000-0000-0000-000000000003/avatar.jpg','eeeeeeee-0000-0000-0000-000000000003');

-- ── Admin ──
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-000000000001');
select is((select count(*)::int from public.foods), 1, 'Admin can read the catalog');
select lives_ok($$insert into public.foods(id,name,base_qty,unit,kcal) values ('f2','Toast',2,'slice',170)$$, 'Admin can add foods');
select lives_ok($$update public.foods set kcal=150 where id='f2'$$, 'Admin can edit foods');
select lives_ok($$insert into public.videos(id,title,url) values ('v2','Two','https://youtu.be/y')$$, 'Admin can add videos');
select lives_ok($$insert into public.exercises(id,name) values ('e2','Squat')$$, 'Admin can add exercises');
select lives_ok($$update public.targets_carb set kcal=1300 where carb_type='Low'$$, 'Admin can edit carb-type targets');
select lives_ok($$update public.targets_day set kcal=1600 where day_id='w1-d1'$$, 'Admin can edit day targets');
select throws_ok($$insert into public.foods(id,name,base_qty,unit) values ('bad','Bad',0,'g')$$, '23514', null, 'invalid food (base qty 0) rejected by constraint');
select throws_ok($$insert into public.videos(id,title,url) values ('v3','X','javascript:alert(1)')$$, '23514', null, 'non-http video URL rejected');
select lives_ok($$delete from public.foods where id='f2'$$, 'Admin can delete foods');
select throws_ok($$update public.plan_base_items set kcal=1$$, '42501', null, 'Admin cannot alter the PDF baseline either');
select is((select count(*)::int from public.profiles), 1, 'Admin sees only her own profile');
select throws_ok($$update public.profiles set role='doda' where id=auth.uid()$$, '42501', null, 'Admin cannot change her own role');
select throws_ok($$update public.profiles set role='admin' where id='dddddddd-0000-0000-0000-000000000002'$$, '42501', null, 'Admin cannot promote anyone');
-- admin vs Doda's private data
select is((select count(*)::int from public.weight_entries), 0, 'Admin cannot read weight entries');
select is((select count(*)::int from public.hydration_entries), 0, 'Admin cannot read hydration');
select is((select count(*)::int from public.meal_done), 0, 'Admin cannot read meal completion');
select is((select count(*)::int from public.doda_workout_rows), 0, 'Admin cannot read workouts');
select is((select count(*)::int from public.doda_meal_items), 0, 'Admin cannot read Doda''s meal items');
select is((select count(*)::int from public.user_settings), 0, 'Admin cannot read profile settings');
select is((select count(*)::int from public.doda_day_notes), 0, 'Admin cannot read day notes');
select is((select count(*)::int from public.migrations), 0, 'Admin cannot read migration markers');
select is((select count(*)::int from storage.objects where bucket_id='profile-photos'), 0, 'Admin cannot see profile photos');
select throws_ok($$insert into public.weight_entries(id,user_id,entry_date,kg) values ('a1','dddddddd-0000-0000-0000-000000000002','2026-01-03',55)$$, '42501', null, 'Admin cannot write into Doda''s weight data');
select throws_ok($$insert into public.weight_entries(id,user_id,entry_date,kg) values ('a2','aaaaaaaa-0000-0000-0000-000000000001','2026-01-03',55)$$, '42501', null, 'Admin has no personal tracking data either');
select throws_ok($$insert into storage.objects(bucket_id,name,owner) values ('profile-photos','dddddddd-0000-0000-0000-000000000002/evil.jpg', auth.uid())$$, '42501', null, 'Admin cannot upload into Doda''s photo folder');
select lives_ok($$update public.hydration_entries set ml=1$$, 'admin update on hydration runs but touches nothing');
select lives_ok($$delete from public.weight_entries$$, 'admin delete on weight runs but touches nothing');
select throws_ok($$select public.bootstrap_roles('admin@test.invalid','doda@test.invalid')$$, '42501', null, 'Admin cannot call bootstrap_roles');

-- ── final: Doda's data intact after admin attempts ──
reset role;
select is((select count(*)::int from public.weight_entries where user_id='dddddddd-0000-0000-0000-000000000002'), 2, 'Doda weight rows intact');
select is((select ml from public.hydration_entries where id='h_d'), 500, 'Doda hydration intact');

select * from finish();
rollback;
