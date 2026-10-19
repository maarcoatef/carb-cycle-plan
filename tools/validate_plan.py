#!/usr/bin/env python3
"""Independent validation of data/plan.json against the PDF. Writes data/validation-report.md.
Usage: python3 tools/validate_plan.py "<pdf>"   (needs pdfplumber)"""
import sys, re, json, collections, pdfplumber
PDF=sys.argv[1]; plan=json.load(open('data/plan.json'))
res=[]; ok=lambda n,c,detail='': res.append((n,bool(c),detail))
days=[d for w in plan['weeks'] for d in w['days']]
meals=[m for d in days for m in d['meals']]
items=[i for m in meals for i in m['items']]
citems=[i for d in days for i in d['coffee']['items']]

# raw PDF text (column-wise) for second, independent pass
raw=[]
with pdfplumber.open(PDF) as pdf:
    for pg in pdf.pages:
        w=pg.width
        for a,b in ((0,w/2),(w/2,w)): raw+= [l.strip() for l in (pg.crop((a,0,b,pg.height)).extract_text() or '').split('\n')]
text='\n'.join(raw)
pdf_day_hdrs=re.findall(r'^Day (\d+) (\w+)$',text,re.M)
pdf_types=re.findall(r'^(LOW|MODERATE|HIGH) CARB DAY$',text,re.M)
pdf_weeks=re.findall(r'^WEEK (\d)$',text,re.M)
item_lines=[l for l in raw if re.search(r'\d+(\.\d+)?$',l) and not l.startswith(('MEAL TOTAL','Day ','WEEK','Updated','Drink','Estimated')) and '| ' in l or (re.search(r'\s\d+(\.\d+)?\s\d+(\.\d+)?\s\d+(\.\d+)?\s\d+(\.\d+)?(\s\d+(\.\d+)?)?$',l) and not l.startswith(('MEAL TOTAL','DAILY','ITEM')) and 'kcal' not in l)]

ok('1. Exactly 4 weeks',len(plan['weeks'])==4,f"{len(plan['weeks'])} weeks")
ok('2. Exactly 28 days',len(days)==28,f"{len(days)} days")
ok('3. Each week has 7 days',all(len(w['days'])==7 for w in plan['weeks']),[len(w['days']) for w in plan['weeks']])
ok('3b. Day numbers 1..28 in order',[d['dayNumber'] for d in days]==list(range(1,29)))
ok('3c. Day/weekday headers equal PDF',[(str(d['dayNumber']),d['weekday']) for d in days]==pdf_day_hdrs)
ok('4. Carb type of every day equals PDF',[d['carbType'].upper() for d in days]==pdf_types,collections.Counter(d['carbType'] for d in days))
ok('5. Every day has breakfast, lunch, dinner, snack',all([m['key'] for m in d['meals']]==['breakfast','lunch','dinner','snack'] for d in days))
ok('13. Daily iced coffee on every day',all(d['coffee'] for d in days))
ok('17. No skipped days/meals (28 days x 4 meals + 28 coffees)',len(meals)==112 and len(days)==28,f'{len(meals)} meals + 28 coffees')
ok('16. No duplicate ids',len({i['id'] for i in items+citems})==len(items+citems) and len({m['id'] for m in meals})==len(meals))
ok('16b. No duplicate food within a meal',all(len({(i['name'],i['quantity']) for i in m['items']})==len(m['items']) for m in meals))

pat=[[d['carbType'] for d in w['days']] for w in plan['weeks']]
ok('3d. Carb cycle pattern identical in all 4 weeks (supports 7-day week grouping)',all(p==pat[0] for p in pat),pat[0])
ok('3e. Weekday sequence continuous Sat..Fri',[d['weekday'] for d in days]==(['Saturday','Sunday','Monday','Tuesday','Wednesday','Thursday','Friday']*4))
# 6-12: every item's raw PDF line round-trips exactly
def fmt(x): return '' if x is None else (f'{x:.1f}' if x!=int(x) or True else str(int(x)))
bad=[]
for d in days:
    for m in d['meals']:
        for i in m['items']:
            nums=[str(int(i['kcal']))]+[f"{i[k]:.1f}" for k in ('p','c','f')]+([f"{i['fiber']:.1f}"] if i['fiber'] is not None else [])
            tail=' '.join(nums)
            if not any(l.endswith(tail) and i['name'] in l and (i['quantity'] in l) for l in raw): bad.append((d['id'],m['key'],i['name'],i['quantity'],tail))
ok('6-12. Every food item (name, quantity, kcal, P, C, F, fiber) found verbatim in PDF',not bad,bad[:5])
ok('6b. Item count equals PDF item-line count',len(items)==len([l for l in raw if re.search(r'\s\d+ \d+\.\d \d+\.\d \d+\.\d( \d+\.\d)?$',l) and not l.startswith(('MEAL TOTAL','DAILY'))]),f'{len(items)} items')

# 14: meal totals: sum of items vs printed meal total
mm=[]
for d in days:
    for m in d['meals']:
        s=dict(kcal=sum(i['kcal'] for i in m['items']),p=sum(i['p'] for i in m['items']),c=sum(i['c'] for i in m['items']),f=sum(i['f'] for i in m['items']),fiber=sum(i['fiber'] or 0 for i in m['items']))
        t=m['pdfTotal']
        for k in s:
            tol=1.0 if k=='kcal' else 0.15
            if abs(s[k]-t[k])>tol+1e-9: mm.append(dict(week=d['weekNumber'],day=d['dayNumber'],meal=m['name'],field=k,sumOfItems=round(s[k],1),pdfMealTotal=t[k]))
ok('14. Meal totals: sum of items equals PDF MEAL TOTAL (tol ±1 kcal / ±0.15 g, rounding)',not mm,f'{len(mm)} mismatches')
# 15: daily totals
dm=[]
for d in days:
    s=dict(kcal=0,p=0,c=0,f=0,fiber=0)
    for m in d['meals']:
        for i in m['items']:
            for k in s: s[k]+=i[k] or 0
    t=d['pdfDailyTotal']
    for k in s:
        tol=2.0 if k=='kcal' else 0.5
        if abs(s[k]-t[k])>tol+1e-9: dm.append(dict(week=d['weekNumber'],day=d['dayNumber'],field=k,sumOfItems=round(s[k],1),pdfDailyTotal=t[k]))
ok('15. Daily totals: sum of items equals PDF DAILY TOTAL (tol ±2 kcal / ±0.5 g, rounding)',not dm,f'{len(dm)} mismatches')
cm=[(d['id'],d['coffee']['pdfUpdatedCalories']) for d in days if not (d['coffee']['pdfUpdatedCalories']['previous']+d['coffee']['pdfUpdatedCalories']['added']==d['coffee']['pdfUpdatedCalories']['updated'] and d['coffee']['pdfUpdatedCalories']['previous']==d['pdfDailyTotal']['kcal'] and sum(i['kcal'] for i in d['coffee']['items'])==130==d['coffee']['pdfTotal']['kcal'])]
ok('Coffee: PDF "previous" = DAILY TOTAL, previous+130 = updated, items 70+60 = 130 (no double count)',not cm,cm[:3])

passed=sum(1 for r in res if r[1])
L=['# Phase 1 – Nutrition import validation report','',f'Source: `{PDF.split("/")[-1]}` · {passed}/{len(res)} checks passed','','## Counts',
 f'- Weeks: {len(plan["weeks"])}',f'- Days: {len(days)}',f'- Meals (breakfast/lunch/dinner/snack): {len(meals)}',f'- Daily iced coffee entries: {len(days)} ({len(citems)} coffee components)',
 f'- Food items in meals: {len(items)} (+ {len(citems)} coffee components = {len(items)+len(citems)} total)','','## Checks','| Result | Check | Detail |','|---|---|---|']
for n,c,dt in res: L.append(f"| {'PASS' if c else '**FAIL**'} | {n} | {str(dt)[:160].replace('|','/')} |")
L+=['','## PDF inconsistencies / items for review (nothing was silently corrected)','']
L.append(f'### A. Totals that do not add up ({len(mm)+len(dm)})')
for x in mm: L.append(f"- Week {x['week']} Day {x['day']} {x['meal']}: {x['field']} items sum {x['sumOfItems']} vs PDF MEAL TOTAL {x['pdfMealTotal']}")
for x in dm: L.append(f"- Week {x['week']} Day {x['day']} DAILY TOTAL: {x['field']} items sum {x['sumOfItems']} vs PDF {x['pdfDailyTotal']}")
if not (mm or dm): L.append('- none')
fl=json.load(open('data/_flags.json')); miss=[f for f in fl if 'Fiber value missing' in f['problem']]
L+=['',f'### B. Food items with NO fiber value printed in the PDF ({len(miss)})','Stored as `null` and shown as "n/a"; counted as 0 only for the fiber *sum* (flagged in the UI).','',
    '| Week | Day | Meal | Food item |','|---|---|---|---|']
for f in miss: L.append(f"| {f['week']} | {f['day']} | {f['meal']} | {f['food']} |")
lab=[d for d in days if d['pdfWeekLabel']!=d['weekNumber']]
L+=['','### 0. Week grouping (decision needed? – applied as below)',f"- The PDF prints a WEEK header per page spread, so printed weeks hold 8/6/8/6 days (Day 8 *Saturday* is printed under WEEK 1; Day 22 *Saturday* under WEEK 3; Days 9-14 under WEEK 2 etc.). The requirement and the repeating Sat-Fri cycle say 7 days per week, so the app groups Days 1-7, 8-14, 15-21, 22-28. The PDF's own label is kept per day (`pdfWeekLabel`). Days whose printed label differs from the app week: {', '.join(str(d['dayNumber']) for d in lab)}. Day content and order are unchanged."]
L+=['','### C. Iced coffee','- The PDF specifies calories only (25 g cilantro frappe 70 kcal + 170 ml skimmed milk ~60 kcal = ~130 kcal). Protein/carbs/fats/fiber are **unavailable (null)** – not estimated.','- PDF DAILY TOTAL excludes the coffee; "Updated calories" = DAILY TOTAL + 130. The app plans meals + coffee once (no double count) and keeps the PDF totals for reference.','- Footnote on every page: *"Estimated nutrition. Digestive Choco is approximate…"* – no "Digestive Choco" item appears in the plan; nothing imported for it.']
open('data/validation-report.md','w').write('\n'.join(L)+'\n')
for n,c,dt in res: print('PASS' if c else 'FAIL',n,'' if c else dt)
print(len(mm),'meal mismatches',len(dm),'daily mismatches')
