#!/usr/bin/env python3
"""Extract the 4-week carb cycle plan from the PDF into data/plan-data.js (+ data/plan.json, data/validation-report.md).
Usage: python3 tools/import_plan.py "<pdf>"     (needs: pip install pdfplumber)
The PDF is the source of truth: nothing is invented; missing values stay null and are flagged."""
import sys, re, json, pdfplumber

PDF = sys.argv[1]
NUM = re.compile(r'^-?\d+(\.\d+)?$')
MEALS = {'Breakfast':'breakfast','Lunch':'lunch','Dinner':'dinner','Snack':'snack'}
issues = []   # flagged for review
def flag(w,d,m,f,msg): issues.append(dict(week=w,day=d,meal=m,food=f,problem=msg))

def halves(pdf):
    for pi,pg in enumerate(pdf.pages):
        w = pg.width
        for a,b in ((0,w/2),(w/2,w)):
            yield pi+1, (pg.crop((a,0,b,pg.height)).extract_text() or '').split('\n')

def parse_item(line):
    """Returns (name, qty, nums[kcal,p,c,f,fi?]) using the trailing run of numeric tokens."""
    t = line.split()
    n = []
    while t and NUM.match(t[-1]) and len(n) < 6:
        n.insert(0, t.pop())
    head = ' '.join(t)
    if '|' in head:
        name, qty = [s.strip() for s in head.split('|',1)]
    else:
        # no pipe: quantity starts at first token that begins with a digit
        parts = head.split(); k = next((i for i,x in enumerate(parts) if x[0].isdigit()), len(parts))
        name, qty = ' '.join(parts[:k]), ' '.join(parts[k:])
    return name, qty, [float(x) for x in n]

days = []
cur = None; week = None
with pdfplumber.open(PDF) as pdf:
    for page, lines in halves(pdf):
        cur = None; meal = None; mode = None
        for ln in lines:
            ln = ln.strip()
            if not ln: continue
            m = re.match(r'^WEEK (\d+)$', ln)
            if m: week = int(m.group(1)); continue
            m = re.match(r'^Day (\d+) (\w+)$', ln)
            if m:
                cur = dict(week=week, dayNumber=int(m.group(1)), weekday=m.group(2), carbType=None, meals=[], coffee=None, pdfTotals=None, pdfMealTotals={}, page=page)
                days.append(cur); meal=None; mode=None; continue
            if cur is None: continue
            m = re.match(r'^(LOW|MODERATE|HIGH) CARB DAY$', ln)
            if m: cur['carbType']=m.group(1).capitalize(); continue
            if ln in MEALS:
                meal = dict(key=MEALS[ln], name=ln, items=[]); cur['meals'].append(meal); mode='meal'; continue
            if ln.startswith('ITEM / QUANTITY'): continue
            if ln.startswith('MEAL TOTAL'):
                v = [float(x) for x in ln.split()[2:]]
                cur['pdfMealTotals'][meal['key']] = v; continue
            if ln == 'DAILY TOTAL': mode='daily'; continue
            if mode=='daily' and 'kcal' in ln:
                m = re.match(r'^([\d.]+) kcal P ([\d.]+)g C ([\d.]+)g F ([\d.]+)g Fiber ([\d.]+)g$', ln)
                cur['pdfTotals'] = dict(kcal=float(m[1]),p=float(m[2]),c=float(m[3]),f=float(m[4]),fiber=float(m[5])); mode=None; continue
            if ln.startswith('SNACK ADD-ON'): mode='coffee'; cur['coffee']=dict(lines=[]); continue
            if mode=='coffee':
                if ln.startswith('A LITTLE PROGRESS') or ln.startswith('Estimated nutrition'): mode=None; continue
                cur['coffee']['lines'].append(ln); continue
            if mode=='meal' and meal is not None:
                name, qty, n = parse_item(ln)
                meal['items'].append(dict(name=name, qty=qty, nums=n, raw=ln))

# The PDF prints a "WEEK n" header once per page spread, which yields 8/6/8/6 days per printed week.
# The weekday sequence (Sat..Fri) and the repeating carb pattern show real weeks are days 1-7, 8-14, 15-21, 22-28,
# so weeks are derived from the day number; the printed label is kept as pdfWeekLabel and reported.
for d in days:
    d['pdfWeek']=d['week']; d['week']=(d['dayNumber']-1)//7+1
# ---- build structured plan ----
r = lambda x: None if x is None else round(x,1)
def mk_item(w,d,mk,idx,it):
    n = it['nums']; wk=w; dn=d
    if len(n)==5: kcal,p,c,f,fi = n
    elif len(n)==4: kcal,p,c,f = n; fi=None; flag(wk,dn,mk,it['name'],'Fiber value missing in PDF (only kcal/P/C/F printed); stored as null, shown as unavailable')
    else:
        kcal=p=c=f=fi=None; flag(wk,dn,mk,it['name'],f'Could not read nutrition values from line: {it["raw"]!r}')
    g = re.search(r'(\d+(?:\.\d+)?)\s*g\b', it['qty'])
    return dict(id=f'w{wk}-d{dn}-{mk}-i{idx+1}', name=it['name'], quantity=it['qty'], grams=float(g[1]) if g else None,
                kcal=kcal,p=p,c=c,f=f,fiber=fi)

plan = dict(version=1, source='Carb Cycle - 4 Weeks Plan.pdf', weeks=[])
for w in range(1,5):
    plan['weeks'].append(dict(id=f'w{w}', number=w, days=[]))
for d in days:
    w = d['week']; dn = d['dayNumber']
    meals=[]
    for m in d['meals']:
        meals.append(dict(id=f'w{w}-d{dn}-{m["key"]}', key=m['key'], name=m['name'],
            items=[mk_item(w,dn,m['key'],i,it) for i,it in enumerate(m['items'])],
            pdfTotal=dict(zip(['kcal','p','c','f','fiber'], d['pdfMealTotals'].get(m['key'],[None]*5)))))
    # iced coffee: only calories are specified in the PDF
    cl = d['coffee']['lines'] if d['coffee'] else []
    txt = ' '.join(cl)
    cm = re.search(r'(\d+)\s*g\s+(.+?)\s*\((\d+) kcal\)\s*\+\s*(\d+)\s*ml\s+(.+?)\s*\(~(\d+) kcal\)', txt)
    dm = re.search(r'Drink: ~(\d+) kcal', txt); um = re.search(r'Updated calories: (\d+) kcal \(previous (\d+) \+ (\d+)\)', txt)
    coffee=None
    if cm and dm:
        items=[dict(id=f'w{w}-d{dn}-coffee-i1',name=cm[2],quantity=f'{cm[1]} g',grams=float(cm[1]),kcal=float(cm[3]),p=None,c=None,f=None,fiber=None),
               dict(id=f'w{w}-d{dn}-coffee-i2',name=cm[5],quantity=f'{cm[4]} ml',grams=None,kcal=float(cm[6]),p=None,c=None,f=None,fiber=None)]
        coffee=dict(id=f'w{w}-d{dn}-coffee',key='coffee',name='Daily Iced Coffee',items=items,
            pdfTotal=dict(kcal=float(dm[1]),p=None,c=None,f=None,fiber=None),
            pdfUpdatedCalories=dict(updated=float(um[1]),previous=float(um[2]),added=float(um[3])) if um else None, rawText=txt)
        flag(w,dn,'coffee','Daily iced coffee','Only calories are specified in the PDF (approximate, "~"); protein/carbs/fats/fiber unavailable (null)') if dn==1 else None
    else:
        flag(w,dn,'coffee','-',f'Iced coffee block not parsed: {txt!r}')
    plan['weeks'][w-1]['days'].append(dict(id=f'w{w}-d{dn}', dayNumber=dn, weekNumber=w, weekday=d['weekday'], carbType=d['carbType'], pdfWeekLabel=d['pdfWeek'],
        meals=meals, coffee=coffee, pdfDailyTotal=d['pdfTotals'], pdfPage=d['page']))

json.dump(plan, open('data/plan.json','w'), indent=1)
open('data/plan-data.js','w').write('/* generated by tools/import_plan.py from the PDF - do not edit by hand */\nwindow.NUTRITION_PLAN = '+json.dumps(plan,separators=(',',':'))+';\n')
json.dump(issues, open('data/_flags.json','w'), indent=1)
print('weeks',len(plan['weeks']),'days',len(days),'flags',len(issues))
