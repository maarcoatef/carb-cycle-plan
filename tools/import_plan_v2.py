#!/usr/bin/env python3
"""Plan v2: extract the 28-day carb-cycling plan from the landscape two-days-per-page PDF.
Usage: python3 tools/import_plan_v2.py "<pdf>"     (needs: pip install pdfplumber)
Writes data/plan.json, data/plan-data.js, data/validation-report.md, data/_flags.json.  The PDF is the source of truth:
nothing is invented; 'N/A' / '<0.5' fiber stays null (unknown, never zero) and is flagged.  The previous plan is archived in data/archive/."""
import sys, re, json, hashlib, pdfplumber
PDF = sys.argv[1]; V = 2; PFX = f'v{V}-'
NUM = r'-?\d+(?:\.\d+)?'
SECTIONS = {'Breakfast':'breakfast','Lunch':'lunch','Dinner':'dinner','Snacks + iced coffee':'snack'}
issues = []; checks = []
def flag(d,m,f,msg): issues.append(dict(day=d,meal=m,food=f,problem=msg))
def num(x): return float(x)
def halves(pdf):
    for pi,pg in enumerate(pdf.pages):
        w = pg.width
        for a,b in ((0,w/2),(w/2,w)):
            yield pi+1, [l.strip() for l in (pg.crop((a,0,b,pg.height)).extract_text() or '').split('\n') if l.strip()]

def parse_item(ln):
    if '|' not in ln: return None
    name, rest = [s.strip() for s in ln.split('|',1)]
    t = rest.split()
    if len(t) < 6: return None
    fi_raw = t[-1]; vals = t[-5:-1]
    if not all(re.fullmatch(NUM, v) for v in vals): return None
    if re.fullmatch(NUM, fi_raw): fi = num(fi_raw); fnote = None
    elif fi_raw == 'N/A': fi = None; fnote = 'N/A'
    elif re.fullmatch(r'<\s*'+NUM, fi_raw): fi = None; fnote = fi_raw
    else: return None
    qty = ' '.join(t[:-5])
    kcal,p,c,f = [num(v) for v in vals]
    return dict(name=name, quantity=qty, kcal=kcal, p=p, c=c, f=f, fiber=fi, fiberNote=fnote)

days = []; cur = None; sec = None; mode = None
with pdfplumber.open(PDF) as pdf:
    for page, lines in halves(pdf):
        cur = None; sec = None; mode = None
        if any(l.startswith('NUTRITION REFERENCE') for l in lines): continue
        for ln in lines:
            m = re.match(r'^Day (\d+) (\w+) / Week (\d+)$', ln)
            if m:
                cur = dict(dayNumber=int(m[1]), weekday=m[2], pdfWeekLabel=int(m[3]), carbType=None, sections={}, pdfDailyTotal=None, fiberNote=None, page=page); days.append(cur); sec=None; mode=None; continue
            if cur is None: continue
            m = re.match(r'^(LOW|MODERATE|HIGH) CARB DAY$', ln)
            if m: cur['carbType'] = m[1].capitalize(); continue
            if ln in SECTIONS:
                sec = dict(key=SECTIONS[ln], name=ln, items=[], total=None); cur['sections'][sec['key']] = sec; mode='meal'; continue
            if ln.startswith('INGREDIENT / QUANTITY') or ln.startswith('P = protein') or ln.startswith('CARB CYCLING') or ln.startswith('Low 80g'): continue
            if ln.startswith('MEAL TOTAL') and sec is not None:
                t = ln.split()[2:]; plus = [x.endswith('+') for x in t]
                sec['total'] = dict(zip(['kcal','p','c','f','fiber'], [num(x.rstrip('+')) for x in t])); sec['totalFiberIsSubtotal'] = any(plus); continue
            if ln == 'DAILY TOTAL': mode = 'daily'; continue
            if mode == 'daily':
                m = re.match(rf'^({NUM}) kcal P ({NUM})g C ({NUM})g F ({NUM})g$', ln)
                if m: cur['pdfDailyTotal'] = dict(kcal=num(m[1]),p=num(m[2]),c=num(m[3]),f=num(m[4]),fiber=None); continue
                m = re.match(rf'^Fiber: ({NUM})g known subtotal', ln)
                if m and cur['pdfDailyTotal']: cur['pdfDailyTotal']['fiber'] = num(m[1]); cur['fiberNote'] = ln; mode = None; continue
            if mode == 'meal' and sec is not None:
                it = parse_item(ln)
                if it: sec['items'].append(it)
                else: flag(cur['dayNumber'], sec['key'], '-', f'Unparsed line: {ln!r}')
    # reference table (pages 15-16): exact base values of the supplied foods
    ref = []
    for pg in pdf.pages:
        t = pg.extract_text() or ''
        if not t.startswith('NUTRITION REFERENCE'): continue
        for ln in t.split('\n'):
            m = re.match(rf'^(\d{{2}}) (.+?) (\d+(?:\.\d+)?(?:g|ml)(?: \+ \d+(?:\.\d+)?g)?) ({NUM}) ({NUM}) ({NUM}) ({NUM}) (N/A|<{NUM}|{NUM})$', ln)
            if m:
                fi_raw = m[8]; fi = num(fi_raw) if re.fullmatch(NUM, fi_raw) else None
                ref.append(dict(no=int(m[1]), name=m[2], quantity=m[3], kcal=num(m[4]), p=num(m[5]), c=num(m[6]), f=num(m[7]), fiber=fi, fiberNote=None if fi is not None else fi_raw))
r1 = lambda x: None if x is None else round(x,1)

# ---- build ----
COFFEE_NAME = 'Ehrmann Protein Caffe Latte'
plan = dict(version=V, source='28-day-carb-cycling-meal-plan.pdf', sourceSha256=hashlib.sha256(open(PDF,'rb').read()).hexdigest(),
            carbTargets=dict(Low=80, Moderate=140, High=210), weeks=[dict(id=f'{PFX}w{w}', number=w, days=[]) for w in range(1,5)], foodReference=ref)
for d in sorted(days, key=lambda x: x['dayNumber']):
    n = d['dayNumber']; w = (n-1)//7 + 1; did = f'{PFX}w{w}-d{n}'; meals = []; coffee = None
    for key in ('breakfast','lunch','dinner','snack'):
        s = d['sections'].get(key)
        if s is None: flag(n,key,'-','Section missing in PDF'); continue
        items = []
        for i,it in enumerate(s['items']):
            g = re.match(r'^(\d+(?:\.\d+)?)\s*g\b', it['quantity'])
            rec = dict(id=f'{did}-{key}-i{i+1}', name=it['name'], quantity=it['quantity'], grams=float(g[1]) if g else None, kcal=it['kcal'], p=it['p'], c=it['c'], f=it['f'], fiber=it['fiber'])
            if it['fiber'] is None: rec['fiberNote'] = it['fiberNote']; flag(n,key,it['name'],f"Fiber printed as {it['fiberNote']!r}: stored as null (unknown), never 0")
            if key == 'snack' and it['name'] == COFFEE_NAME:
                if coffee: flag(n,key,it['name'],'Second latte line ignored'); continue
                coffee = dict(id=f'{did}-coffee', key='coffee', name='Daily Iced Coffee', items=[dict(rec, id=f'{did}-coffee-i1')],
                              pdfTotal=dict(kcal=it['kcal'],p=it['p'],c=it['c'],f=it['f'],fiber=it['fiber']))
            else: items.append(rec)
        tot = s['total'] or dict(kcal=None,p=None,c=None,f=None,fiber=None)
        m = dict(id=f'{did}-{key}', key=key, name={'snack':'Snack'}.get(key, s['name']), items=items, pdfTotal=tot)
        if key == 'snack': m['pdfTotalIncludesCoffee'] = True
        if s.get('totalFiberIsSubtotal'): m['pdfTotalFiberIsKnownSubtotal'] = True
        meals.append(m)
    if coffee is None: flag(n,'coffee','-','No iced coffee line found'); coffee = dict(id=f'{did}-coffee', key='coffee', name='Daily Iced Coffee', items=[], pdfTotal=dict(kcal=None,p=None,c=None,f=None,fiber=None))
    day = dict(id=did, dayNumber=n, weekNumber=w, weekday=d['weekday'], carbType=d['carbType'], pdfWeekLabel=d['pdfWeekLabel'], meals=meals, coffee=coffee, pdfDailyTotal=d['pdfDailyTotal'], pdfPage=d['page'])
    if d['fiberNote']: day['pdfDailyFiberNote'] = d['fiberNote']
    plan['weeks'][w-1]['days'].append(day)

# ---- validation ----
def chk(name, ok, detail=''): checks.append((bool(ok), name, detail))
D = [x for wk in plan['weeks'] for x in wk['days']]
chk('1. Exactly 4 weeks / 28 days / 7 per week', len(plan['weeks'])==4 and len(D)==28 and all(len(w['days'])==7 for w in plan['weeks']), f'{len(D)} days')
chk('2. Day numbers 1..28 in order', [x['dayNumber'] for x in D]==list(range(1,29)))
chk('3. Carb type present on every day', all(x['carbType'] for x in D))
cyc = [x['carbType'] for x in D[:7]]
chk('4. Carb cycle identical in all 4 weeks (Sat Mod, Sun Low, Mon Low, Tue Mod, Wed Low, Thu Mod, Fri High)', all([y['carbType'] for y in D[i*7:(i+1)*7]]==cyc for i in range(4)) and cyc==['Moderate','Low','Low','Moderate','Low','Moderate','High'], str(cyc))
chk('5. Every day has breakfast, lunch, dinner, snack and an iced coffee', all([m['key'] for m in x['meals']]==['breakfast','lunch','dinner','snack'] and x['coffee']['items'] for x in D))
chk('6. Daily total printed on every day', all(x['pdfDailyTotal'] and all(v is not None for v in x['pdfDailyTotal'].values()) for x in D))
items_n = sum(len(m['items']) for x in D for m in x['meals']) + sum(len(x['coffee']['items']) for x in D)
ids = [i['id'] for x in D for m in x['meals']+[x['coffee']] for i in m['items']]
chk('7. No duplicate item ids', len(ids)==len(set(ids)), f'{items_n} items')
bad = []
for x in D:
    for m in x['meals']:
        extra = x['coffee']['items'] if m['key']=='snack' else []
        for k in ('kcal','p','c','f'):
            s = sum((i[k] or 0) for i in m['items']+extra); t = m['pdfTotal'][k]
            if t is None or abs(s-t) > (1.0 if k=='kcal' else 0.15): bad.append((x['dayNumber'],m['key'],k,round(s,2),t))
chk('8. Meal totals: items (+ iced coffee for the snack section) equal the printed MEAL TOTAL (±1 kcal / ±0.15 g)', not bad, str(bad[:8]))
bad = []
for x in D:
    for k in ('kcal','p','c','f'):
        s = sum((i[k] or 0) for m in x['meals']+[x['coffee']] for i in m['items']); t = x['pdfDailyTotal'][k]
        if abs(s-t) > (1.5 if k=='kcal' else 0.3): bad.append((x['dayNumber'],k,round(s,2),t))
chk('9. Daily totals: sum of all items equals the printed DAILY TOTAL (±1.5 kcal / ±0.3 g)', not bad, str(bad[:8]))
chk('10. Carbs of each day vs. carb-type target (Low 80 / Moderate 140 / High 210 g)', all(abs(x['pdfDailyTotal']['c']-plan['carbTargets'][x['carbType']])<=0.5 for x in D), str([(x['dayNumber'],x['pdfDailyTotal']['c']) for x in D if abs(x['pdfDailyTotal']['c']-plan['carbTargets'][x['carbType']])>0.5]))
chk('11. Reference table has 32 foods', len(ref)==32 and [r['no'] for r in ref]==list(range(1,33)), f'{len(ref)}')
# every plan item equals the reference food scaled by quantity (bread is the "balancing portion", shown to 0.01 g)
refn = {r['name'].lower(): r for r in ref}; mism = []; unknown = set()
for x in D:
    for m in x['meals']+[x['coffee']]:
        for i in m['items']:
            r = refn.get(i['name'].lower())
            if not r: unknown.add(i['name']); continue
            q = re.match(r'^(\d+(?:\.\d+)?)', i['quantity']); rq = re.match(r'^(\d+(?:\.\d+)?)', r['quantity'])
            if not q or not rq: continue
            k = float(q[1])/float(rq[1])
            for f in ('kcal','p','c','f'):
                if abs(r[f]*k - i[f]) > (1.0 if f=='kcal' else 0.2): mism.append((x['dayNumber'], i['name'], i['quantity'], f, round(r[f]*k,2), i[f]))
chk('12. Every food name exists in the reference table', not unknown, str(sorted(unknown)))
chk('13. Every item equals the reference food scaled by quantity (kcal ±1, macros ±0.2)', not mism, f'{len(mism)} differences: {mism[:6]}')

json.dump(plan, open('data/plan.json','w'), indent=1)
open('data/plan-data.js','w').write('/* generated by tools/import_plan_v2.py from the PDF - do not edit by hand */\nwindow.NUTRITION_PLAN = '+json.dumps(plan,separators=(',',':'))+';\n')
json.dump(issues, open('data/_flags.json','w'), indent=1)
rep = ['# Plan v2 – import validation report', '', f"Source: `{plan['source']}` (sha256 `{plan['sourceSha256']}`) · {sum(c[0] for c in checks)}/{len(checks)} checks passed", '',
       '## Counts', f'- Weeks: {len(plan["weeks"])}', f'- Days: {len(D)}', f'- Food items (meals + iced coffee): {items_n}', f'- Reference foods: {len(ref)}', f'- Flags: {len(issues)} (see data/_flags.json; mostly unknown fiber)', '', '## Checks', '| Result | Check | Detail |', '|---|---|---|']
rep += [f"| {'PASS' if ok else '**FAIL**'} | {n} | {d} |" for ok,n,d in checks]
open('data/validation-report.md','w').write('\n'.join(rep)+'\n')
print('days', len(D), 'items', items_n, 'ref', len(ref), 'flags', len(issues), 'checks', sum(c[0] for c in checks), '/', len(checks))
for ok,n,d in checks:
    if not ok: print('FAIL', n, d)
