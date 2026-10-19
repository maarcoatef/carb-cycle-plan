#!/usr/bin/env python3
"""Generate the plan-v2 import SQL from data/plan.json (no DB access).  Writes:
  supabase/hosted/05_plan_v2_import.sql   – the import (single transaction, refuses to run twice, switches the active version last)
  supabase/hosted/05a_plan_v2_dryrun.sql  – same statements + checks, ends with ROLLBACK (changes nothing)
  supabase/hosted/05b_plan_v2_backup.sql  – read-only: returns one JSON document with the current data to save before importing
Run: python3 tools/make_plan_sql.py"""
import json, re, hashlib
P = json.load(open('data/plan.json')); V = P['version']
q = lambda s: 'null' if s is None else "'" + str(s).replace("'", "''") + "'"
n = lambda x: 'null' if x is None else repr(float(x)) if not isinstance(x, int) else str(x)
UNIT = {'g':'g','gram':'g','grams':'g','ml':'ml','pc':'piece','pcs':'piece','piece':'piece','pieces':'piece','slice':'slice','slices':'slice','serving':'serving','servings':'serving'}
def parse_qty(s):
    m = re.match(r'^\s*(\d+(?:[.,]\d+)?)\s*([a-zA-Z]*)', s or '')
    if not m: return None, 'serving'
    w = m[2].lower(); return float(m[1].replace(',', '.')), ('piece' if w == '' else UNIT.get(w, 'serving'))
days = [d for w in P['weeks'] for d in w['days']]
rows_d, rows_m, rows_i = [], [], []
cats = {}
for d in days:
    rows_d.append(f"({q(d['id'])},{d['weekNumber']},{d['dayNumber']},{q(d['weekday'])},{q(d['carbType'])},{V},{q(json.dumps(d['pdfDailyTotal']))}::jsonb,null)")
    for si, m in enumerate(d['meals'] + [d['coffee']]):
        coffee = m['key'] == 'coffee'
        rows_m.append(f"({q(m['id'])},{q(d['id'])},{q(m['key'])},{q(m['name'])},{si},{'true' if coffee else 'false'},{q(json.dumps(m['pdfTotal']))}::jsonb)")
        for ii, it in enumerate(m['items']):
            qty, unit = parse_qty(it['quantity']); cats.setdefault(it['name'].lower(), set()).add(m['key'])
            rows_i.append(f"({q(it['id'])},{q(m['id'])},{ii},{q(it['name'])},{q(it['quantity'])},{n(it['grams'])},{n(it['kcal'])},{n(it['p'])},{n(it['c'])},{n(it['f'])},{n(it['fiber'])},{n(qty)},{q(unit)})")
rows_f = []
for r in P['foodReference']:
    qty, unit = parse_qty(r['quantity']); c = sorted(cats.get(r['name'].lower(), []))
    rows_f.append(f"({q('f_ref%02d' % r['no'])},{q(r['name'])},{n(qty)},{q(unit)},{n(r['kcal'])},{n(r['p'])},{n(r['c'])},{n(r['f'])},{n(r['fiber'])},array[{','.join(q(x) for x in c)}]::text[])")
body = f"""-- Plan v{V} import · source {P['source']} · sha256 {P['sourceSha256']}
-- {len(days)} days · {len(rows_m)} meals (incl. iced coffee) · {len(rows_i)} baseline items · {len(rows_f)} reference foods
-- Nothing is deleted or updated: version {V} gets its own ids, existing rows/progress stay untouched, existing foods/targets win ("on conflict do nothing").
do $$ begin
  if exists (select 1 from public.plan_versions where version = {V}) then raise exception 'plan version {V} is already imported - nothing done'; end if;
end $$;
insert into public.plan_versions (version, label, source_file, source_sha256, is_active)
  values ({V}, '28-day carb cycling plan (v{V})', {q(P['source'])}, {q(P['sourceSha256'])}, false);
insert into public.plan_days (day_id, week_no, day_number, weekday, carb_type, version, pdf_total, pdf_updated_kcal) values
{(','+chr(10)).join(rows_d)};
insert into public.plan_meals (meal_id, day_id, key, name, sort, is_coffee, pdf_total) values
{(','+chr(10)).join(rows_m)};
insert into public.plan_base_items (id, meal_id, sort, name, quantity, grams, kcal, p, c, f, fiber, qty, unit) values
{(','+chr(10)).join(rows_i)};
insert into public.foods (id, name, base_qty, unit, kcal, p, c, f, fiber, cats) values
{(','+chr(10)).join(rows_f)}
  on conflict do nothing;
insert into public.targets_carb (carb_type, c) values ('Low',{P['carbTargets']['Low']}),('Moderate',{P['carbTargets']['Moderate']}),('High',{P['carbTargets']['High']})
  on conflict do nothing;
"""
activate = f"""update public.plan_versions set is_active = false where is_active;
update public.plan_versions set is_active = true where version = {V};
"""
checks = f"""select 'version' as what, version::text as a, is_active::text as b from public.plan_versions order by version;
select 'days' as what, count(*)::text as n from public.plan_days where version = {V};                                    -- expect {len(days)}
select 'meals' as what, count(*)::text as n from public.plan_meals m join public.plan_days d using (day_id) where d.version = {V};   -- expect {len(rows_m)}
select 'items' as what, count(*)::text as n from public.plan_base_items i join public.plan_meals m using (meal_id) join public.plan_days d using (day_id) where d.version = {V};   -- expect {len(rows_i)}
select 'foods' as what, count(*)::text as n from public.foods where id like 'f_ref%';                                       -- expect {len(rows_f)} on an empty catalog
select 'active versions' as what, count(*)::text as n from public.plan_versions where is_active;                           -- expect 1
"""
open('supabase/hosted/05_plan_v2_import.sql', 'w').write(f"-- NOT APPLIED. Run only after explicit approval, after 05b (backup) and 05a (dry run).\nbegin;\n{body}{activate}commit;\n")
open('supabase/hosted/05a_plan_v2_dryrun.sql', 'w').write(f"-- DRY RUN: executes the whole import and ends with ROLLBACK, so nothing is kept. Read the result of each check.\nbegin;\n{body}{activate}{checks}rollback;\n")
open('supabase/hosted/05b_plan_v2_backup.sql', 'w').write("""-- READ-ONLY backup: run in the SQL editor and save the single JSON value it returns (Export / copy cell) before importing.
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
""")
print('days', len(days), 'meals', len(rows_m), 'items', len(rows_i), 'foods', len(rows_f))
