-- NOT APPLIED. Run after 06a_target_ranges.sql, only after explicit approval.  Data only; nothing is deleted or overwritten except the three carb-type goal rows.
begin;
-- 1) Goals (Admin-editable afterwards): protein 100–110 g on every carb type; carbs Low max 100, Moderate max 160, High 200–250.
--    The single-value p / c columns are cleared for these three rows only (c held the PDF-header 80/140/210 seeded by the Plan V2 import); kcal, f, fiber are untouched.
insert into public.targets_carb (carb_type, p_min, p_max, c_min, c_max) values
  ('Low',100,110,null,100), ('Moderate',100,110,null,160), ('High',100,110,200,250)
  on conflict (carb_type) do update set p_min = excluded.p_min, p_max = excluded.p_max, c_min = excluded.c_min, c_max = excluded.c_max, p = null, c = null;
-- 2) Chloe Ting "2 Weeks Shred Challenge": official YouTube links (verified against chloeting.com/program/2019/two-weeks-shred-challenge).
--    A video whose link already exists, or an exercise whose name already exists, is NOT duplicated or changed.
insert into public.videos (id, title, url, type)
  select v.id, v.title, v.url, v.type from (values
  ('v_ct_wu','Warm Up','https://youtu.be/-p0PA9Zt8zk','Stretching'),
  ('v_ct_dte','Do This Everyday to Lose Weight','https://youtu.be/2MoGxae-zyo','Cardio'),
  ('v_ct_a2w','Abs in 2 Weeks','https://youtu.be/2pLT-olgUJs','Abs'),
  ('v_ct_l11','11 Line Abs','https://youtu.be/6TmQiugy_qw','Abs'),
  ('v_ct_lbb','Lower Body Burn Workout','https://youtu.be/I9nG-G4B5Bs','Muscles'),
  ('v_ct_tca','Tight Core & Arms Workout','https://youtu.be/3Pr6n-nKfMA','Abs'),
  ('v_ct_ari','Ariana Grande Abs','https://youtu.be/RO_0B8srLoA','Abs'),
  ('v_ct_cd','Full Body Cooldown','https://youtu.be/tXWh-dowiLg','Stretching')
  ) as v(id, title, url, type)
  where not exists (select 1 from public.videos x where x.url = v.url or x.id = v.id);
insert into public.exercises (id, name, intensity, minutes, kcal, default_video_id)
  select e.id, e.name, e.intensity, e.minutes, 0, (select x.id from public.videos x where x.url = e.url order by x.created_at limit 1) from (values
  ('e_ct_wu','Warm Up','Low',6,'https://youtu.be/-p0PA9Zt8zk'),
  ('e_ct_dte','Do This Everyday to Lose Weight','Moderate',14,'https://youtu.be/2MoGxae-zyo'),
  ('e_ct_a2w','Abs in 2 Weeks','Moderate',11,'https://youtu.be/2pLT-olgUJs'),
  ('e_ct_l11','11 Line Abs','Moderate',11,'https://youtu.be/6TmQiugy_qw'),
  ('e_ct_lbb','Lower Body Burn Workout','Moderate',13,'https://youtu.be/I9nG-G4B5Bs'),
  ('e_ct_tca','Tight Core & Arms Workout','Moderate',13,'https://youtu.be/3Pr6n-nKfMA'),
  ('e_ct_ari','Ariana Grande Abs','Moderate',3,'https://youtu.be/RO_0B8srLoA'),
  ('e_ct_cd','Full Body Cooldown','Low',11,'https://youtu.be/tXWh-dowiLg')
  ) as e(id, name, intensity, minutes, url)
  where not exists (select 1 from public.exercises x where x.id = e.id or lower(btrim(x.name)) = lower(btrim(e.name)));
commit;
-- checks (read-only):
--   select carb_type, p_min, p_max, c_min, c_max, p, c from public.targets_carb order by 1;      -- 100/110 everywhere; c_max 100 / 160 / 250, c_min only High 200
--   select count(*) from public.videos where url like 'https://youtu.be/%';                       -- expect >= 8
--   select count(*) from public.exercises where lower(name) in ('warm up','do this everyday to lose weight','abs in 2 weeks','11 line abs','lower body burn workout','tight core & arms workout','ariana grande abs','full body cooldown');  -- 8
