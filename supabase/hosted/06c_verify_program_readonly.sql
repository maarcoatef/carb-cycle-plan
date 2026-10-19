-- READ-ONLY. Verifies the Chloe Ting program end to end. Run in the SQL editor (project oxqcprgreelxfjhlqpxl). Changes nothing.
-- 1) Catalog: the 5 REQUIRED exercises (+3 optional) and their videos.  Expect 5+ rows with a youtu.be link in `url`.
select e.id, e.name, e.minutes, v.url
from public.exercises e left join public.videos v on v.id = e.default_video_id
where lower(btrim(e.name)) in ('do this everyday to lose weight','abs in 2 weeks','11 line abs','lower body burn workout','tight core & arms workout',
                               'warm up','full body cooldown','ariana grande abs')
order by e.name;
-- 2) Doda's workout rows per program day (day_index 0..13 = program day 1..14).  Expected counts: 2,2,4,3,0,3,4,3,0,4,2,4,3,4  (rest days 5 and 9 have none)
select r.day_index + 1 as program_day, count(*) as workouts, string_agg(r.name, ' | ' order by r.sort) as names
from public.doda_workout_rows r where r.day_index <= 13 group by r.day_index order by r.day_index;
-- 3) Rest-day notes (days 5 and 9) and the completion marker (written only after the app verified every slot)
select day_index + 1 as program_day, left(notes, 40) as note from public.doda_day_notes where day_index in (4, 8) order by 1;
select name, applied_at from public.migrations where name like 'chloe_2019_two_week_shred%' order by applied_at;
-- 4) Duplicates (expect 0 rows)
select day_index + 1 as program_day, exercise_id, count(*) from public.doda_workout_rows where exercise_id is not null group by day_index, exercise_id having count(*) > 1;
