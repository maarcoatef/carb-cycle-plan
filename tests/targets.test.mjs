// Boundary tests for the protein range and carb limits (logic is read straight out of index.html).
import test from 'node:test'; import assert from 'node:assert/strict'; import fs from 'node:fs'; import vm from 'node:vm';
const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const pick = (from, to, skip = 0) => { const a = html.indexOf(from), b = html.indexOf(to, a + skip); assert.ok(a > 0 && b > a, from); return html.slice(a, b); };
const code = [pick('const GOAL_TARGETS', '\n', 20), pick('const RK=', 'function inheritedSpecs'), pick('const r1d=', 'function targetRows')].join('\n');
const ctx = vm.createContext({ r1: x => Math.round(x * 10) / 10, nn: v => (v === null || v === undefined || v === '') ? null : +v });
vm.runInContext(code + '\nthis.api={GOAL_TARGETS,specOf,targetStatus,fmtTarget};', ctx);
const { GOAL_TARGETS, specOf, targetStatus, fmtTarget } = ctx.api, key = (k, a) => targetStatus(k, a, specOf(GOAL_TARGETS, k)).key;
test('protein 100–110 g every day; carbs have no limit', () => { assert.equal(key('p', 99.9), 'low'); assert.equal(key('p', 100), 'ok'); assert.equal(key('p', 110), 'ok'); assert.equal(key('p', 110.1), 'over'); assert.equal(fmtTarget(specOf(GOAL_TARGETS, 'p'), 'p'), '100–110g'); assert.equal(key('c', 500), 'none'); });
test('single-value targets keep the ±2% rule; no target = none', () => {
  assert.equal(targetStatus('kcal', 1500, { single: 1500 }).key, 'ok'); assert.equal(targetStatus('kcal', 1700, { single: 1500 }).key, 'over'); assert.equal(targetStatus('f', 10, null).key, 'none'); });
