// Boundary tests for the protein range and carb limits (logic is read straight out of index.html).
import test from 'node:test'; import assert from 'node:assert/strict'; import fs from 'node:fs'; import vm from 'node:vm';
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const pick = (from, to, skip = 0) => { const a = html.indexOf(from), b = html.indexOf(to, a + skip); assert.ok(a > 0 && b > a, from); return html.slice(a, b); };
const code = [pick('const GOAL_TARGETS', '\n', 20), pick('const RK=', 'function inheritedSpecs'), pick('const r1d=', 'function targetRows')].join('\n');
const ctx = vm.createContext({ r1: x => Math.round(x * 10) / 10, nn: v => (v === null || v === undefined || v === '') ? null : +v });
vm.runInContext(code + '\nthis.api={GOAL_TARGETS,specOf,targetStatus,fmtTarget};', ctx);
const { GOAL_TARGETS, specOf, targetStatus, fmtTarget } = ctx.api, key = (k, a, t) => targetStatus(k, a, specOf(GOAL_TARGETS[t], k)).key;
test('protein 100–110 g on every carb type', () => { for (const t of ['Low', 'Moderate', 'High']) { assert.equal(key('p', 99.9, t), 'low'); assert.equal(key('p', 100, t), 'ok'); assert.equal(key('p', 110, t), 'ok'); assert.equal(key('p', 110.1, t), 'over'); } assert.equal(fmtTarget(specOf(GOAL_TARGETS.Low, 'p'), 'p'), '100–110g'); });
test('Low ≤ 100 g and Moderate ≤ 160 g carbs: never "below", exceeded only above the limit', () => {
  assert.equal(key('c', 0, 'Low'), 'ok'); assert.equal(key('c', 100, 'Low'), 'ok'); assert.equal(key('c', 100.1, 'Low'), 'over');
  assert.equal(key('c', 80, 'Moderate'), 'ok'); assert.equal(key('c', 160, 'Moderate'), 'ok'); assert.equal(key('c', 160.1, 'Moderate'), 'over'); });
test('High carbs 200–250 g: below under 200, exceeded only above 250', () => {
  assert.equal(key('c', 199.9, 'High'), 'low'); assert.equal(key('c', 200, 'High'), 'ok'); assert.equal(key('c', 250, 'High'), 'ok'); assert.equal(key('c', 250.1, 'High'), 'over'); });
test('single-value targets keep the ±2% rule; no target = none', () => {
  assert.equal(targetStatus('kcal', 1500, { single: 1500 }).key, 'ok'); assert.equal(targetStatus('kcal', 1700, { single: 1500 }).key, 'over'); assert.equal(targetStatus('f', 10, null).key, 'none'); });
