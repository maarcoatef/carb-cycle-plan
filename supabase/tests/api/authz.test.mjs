// End-to-end authorization tests against a LOCAL Supabase stack (real GoTrue + PostgREST + RLS).
//   supabase start -x storage-api && eval "$(supabase status -o env | sed 's/^/export /')" && node --test supabase/tests/api/
// Uses the local secret key ONLY to create throw-away test users; every assertion runs with a publishable key + the user's own JWT.
import test from 'node:test';
import assert from 'node:assert/strict';

const URL = process.env.API_URL || 'http://127.0.0.1:56421';
const PUB = process.env.PUBLISHABLE_KEY, SEC = process.env.SECRET_KEY || process.env.SERVICE_ROLE_KEY;
if (!PUB || !SEC) throw new Error('Set PUBLISHABLE_KEY and SECRET_KEY from `supabase status -o env` (local stack only).');
if (!/127\.0\.0\.1|localhost/.test(URL)) throw new Error('Refusing to run against a non-local URL.');

const j = async (path, opts = {}, key = PUB, token) => {
  const r = await fetch(URL + path, { ...opts, headers: { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(opts.headers || {}) } });
  let body = null; try { body = await r.json(); } catch {}
  return { status: r.status, body };
};
const ADMIN = { email: 'api.admin@test.invalid', password: 'ApiAdmin#2026' }, DODA = { email: 'api.doda@test.invalid', password: 'ApiDoda#2026' };
const TABLES = ['profiles','videos','foods','exercises','plan_days','plan_meals','plan_base_items','targets_carb','targets_day','doda_meal_items','meal_done','doda_workout_rows','doda_day_notes','hydration_entries','weight_entries','user_settings','migrations'];
let adminTok, dodaTok, dodaId;
const NOT_NIL = '/rest/v1/profiles?id=neq.00000000-0000-0000-0000-000000000000';

async function ensureUser(u) {
  const r = await j('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({ ...u, email_confirm: true }) }, SEC);
  if (r.status >= 400 && !/already|exists|registered/i.test(JSON.stringify(r.body))) throw new Error('create user failed ' + JSON.stringify(r.body));
}
const login = async u => { const r = await j('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify(u) }); assert.equal(r.status, 200, 'login ' + u.email); return r.body; };

test.before(async () => {
  await ensureUser(ADMIN); await ensureUser(DODA);
  const rb = await j('/rest/v1/rpc/bootstrap_roles', { method: 'POST', body: JSON.stringify({ admin_email: ADMIN.email, doda_email: DODA.email }) }, SEC);
  assert.ok(rb.status < 300, 'bootstrap_roles via secret key: ' + JSON.stringify(rb.body));
  adminTok = (await login(ADMIN)).access_token; const d = await login(DODA); dodaTok = d.access_token; dodaId = d.user.id;
  // seed one Doda row + one master row as the service role (RLS bypass) to have something to attack
  await j('/rest/v1/weight_entries?on_conflict=id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' }, body: JSON.stringify({ id: 'api_w1', user_id: dodaId, entry_date: '2026-01-01', kg: 70 }) }, SEC);
  await j('/rest/v1/foods?on_conflict=id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates' }, body: JSON.stringify({ id: 'api_f1', name: 'API test food', base_qty: 100, unit: 'g', kcal: 100 }) }, SEC);
});

test('public sign-ups are disabled', async () => {
  const r = await j('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email: 'intruder@test.invalid', password: 'Intruder#2026' }) });
  assert.ok(r.status >= 400, 'signup must fail'); 
});

test('anonymous access is denied on every table', async () => {
  for (const t of TABLES) {
    const r = await j(`/rest/v1/${t}?select=*&limit=1`);
    assert.ok(r.status === 401 || r.status === 403 || (r.status === 200 && r.body.length === 0 && false), `anon read ${t} -> ${r.status}`);
  }
  assert.ok([401, 403].includes((await j('/rest/v1/foods', { method: 'POST', body: JSON.stringify({ id: 'anon', name: 'x', base_qty: 1, unit: 'g' }) })).status));
});

test('Doda cannot modify admin master data', async () => {
  let r = await j('/rest/v1/foods', { method: 'POST', body: JSON.stringify({ id: 'doda_hack', name: 'Hack', base_qty: 1, unit: 'g' }) }, PUB, dodaTok);
  assert.ok([401, 403].includes(r.status), 'insert -> ' + r.status);
  r = await j('/rest/v1/foods?id=eq.api_f1', { method: 'PATCH', body: JSON.stringify({ name: 'Hacked' }) }, PUB, dodaTok);
  assert.deepEqual(r.body, [], 'update must match no rows');
  r = await j('/rest/v1/foods?id=eq.api_f1', { method: 'DELETE' }, PUB, dodaTok);
  assert.deepEqual(r.body, [], 'delete must match no rows');
  const check = await j('/rest/v1/foods?id=eq.api_f1&select=name', {}, SEC);
  assert.equal(check.body[0].name, 'API test food');
  for (const t of ['videos', 'exercises', 'targets_carb', 'targets_day', 'plan_days', 'plan_meals', 'plan_base_items']) {
    const w = await j(`/rest/v1/${t}`, { method: 'POST', body: '{}' }, PUB, dodaTok);
    assert.ok([401, 403].includes(w.status), `Doda write ${t} -> ${w.status}`);
  }
});

test('Admin can manage master data', async () => {
  const r = await j('/rest/v1/foods?id=eq.api_f1', { method: 'PATCH', body: JSON.stringify({ kcal: 120 }) }, PUB, adminTok);
  assert.equal(r.status, 200); assert.equal(r.body[0].kcal, 120);
});

test('Admin cannot access Doda\'s private tracking', async () => {
  for (const t of ['weight_entries', 'hydration_entries', 'meal_done', 'doda_workout_rows', 'doda_meal_items', 'doda_day_notes', 'user_settings', 'migrations']) {
    const r = await j(`/rest/v1/${t}?select=*`, {}, PUB, adminTok);
    assert.equal(r.status, 200); assert.deepEqual(r.body, [], `admin must see no ${t} rows`);
  }
  let r = await j('/rest/v1/weight_entries', { method: 'POST', body: JSON.stringify({ id: 'adm_w', user_id: dodaId, entry_date: '2026-01-02', kg: 50 }) }, PUB, adminTok);
  assert.ok([401, 403].includes(r.status), 'admin write for Doda -> ' + r.status);
  r = await j('/rest/v1/weight_entries?id=eq.api_w1', { method: 'PATCH', body: JSON.stringify({ kg: 1 }) }, PUB, adminTok);
  assert.deepEqual(r.body, []);
  const mine = await j('/rest/v1/weight_entries?id=eq.api_w1&select=kg', {}, PUB, dodaTok);
  assert.equal(mine.body[0].kg, 70, 'Doda still sees her own untouched row');
});

test('users cannot change their own (or anyone\'s) role', async () => {
  for (const tok of [dodaTok, adminTok]) {
    let r = await j(NOT_NIL, { method: 'PATCH', body: JSON.stringify({ role: 'admin' }) }, PUB, tok);
    assert.ok([401, 403].includes(r.status), 'role update -> ' + r.status);
    r = await j('/rest/v1/profiles', { method: 'POST', body: JSON.stringify({ id: crypto.randomUUID(), role: 'admin' }) }, PUB, tok);
    assert.ok([401, 403].includes(r.status), 'profile insert -> ' + r.status);
    r = await j(NOT_NIL, { method: 'DELETE' }, PUB, tok);
    assert.ok([401, 403].includes(r.status), 'profile delete -> ' + r.status);
  }
  const me = await j('/rest/v1/profiles?select=role', {}, PUB, dodaTok);
  assert.deepEqual(me.body, [{ role: 'doda' }]);
  const rpc = await j('/rest/v1/rpc/bootstrap_roles', { method: 'POST', body: JSON.stringify({ admin_email: DODA.email, doda_email: ADMIN.email }) }, PUB, dodaTok);
  assert.ok([401, 403, 404].includes(rpc.status), 'bootstrap_roles must not be callable by users -> ' + rpc.status);
});

test.after(async () => {   // clean up test rows
  await j('/rest/v1/weight_entries?id=eq.api_w1', { method: 'DELETE' }, SEC); await j('/rest/v1/foods?id=eq.api_f1', { method: 'DELETE' }, SEC);
});
