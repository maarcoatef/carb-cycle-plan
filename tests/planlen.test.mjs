import test from 'node:test'; import assert from 'node:assert/strict'; import fs from 'node:fs'; import vm from 'node:vm';
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const a = html.indexOf("const PLAN_END="), b = html.indexOf('function clampUi');
const days = Array.from({ length: 56 }, (_, i) => ({ dayNumber: i + 1 })), PLAN = { weeks: Array.from({ length: 8 }, (_, w) => ({ days: days.slice(w * 7, w * 7 + 7) })) };
const ctx = vm.createContext({ S: { planStart: '2026-11-17' }, PLAN_DAYS: days, PLAN });
vm.runInContext(html.slice(a, b) + '\nthis.api={planLen,visWeeks};', ctx);
test('plan ends on 1 Jan 2027', () => {
  assert.equal(ctx.api.planLen('2026-11-17'), 46);                       // Day 1 = 17 Nov, Day 46 = 1 Jan
  const w = ctx.api.visWeeks(); assert.equal(w.length, 7); assert.equal(w[6].days.length, 4);
  assert.equal(ctx.api.planLen('2026-12-25'), 8); assert.equal(ctx.api.planLen('2027-01-01'), 1); assert.equal(ctx.api.planLen('2027-03-01'), 1);
  assert.equal(ctx.api.planLen(''), 56);
});
