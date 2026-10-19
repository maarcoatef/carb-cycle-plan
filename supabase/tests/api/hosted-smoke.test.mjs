// Non-destructive smoke/security checks against the HOSTED project using ONLY the publishable key + the two real accounts.
// Writes: none to real data. The single allowed-write probe uses a unique throw-away id ('zz_smoke_<uuid>') in Doda's own weight table
// and is deleted again. All forbidden-write probes are expected to be denied.
//   API_URL=https://<ref>.supabase.co PUBLISHABLE_KEY=sb_publishable_... \
//   ADMIN_EMAIL=... ADMIN_PASSWORD=... DODA_EMAIL=... DODA_PASSWORD=... node --test supabase/tests/api/hosted-smoke.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
const { API_URL: URL, PUBLISHABLE_KEY: PUB, ADMIN_EMAIL, ADMIN_PASSWORD, DODA_EMAIL, DODA_PASSWORD } = process.env;
if (![URL, PUB, ADMIN_EMAIL, ADMIN_PASSWORD, DODA_EMAIL, DODA_PASSWORD].every(Boolean)) throw new Error('Missing env (see header).');
if (/sb_secret_|service_role/.test(PUB)) throw new Error('Never pass a secret key here.');
const j = async (path, opts = {}, token) => {
  const r = await fetch(URL + path, { ...opts, headers: { apikey: PUB, Authorization: `Bearer ${token || PUB}`, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(opts.headers || {}) } });
  let body = null; try { body = await r.json(); } catch {} return { status: r.status, body };
};
const login = async (email, password) => { const r = await j('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) }); return r; };
const TABLES = ['profiles','videos','foods','exercises','plan_days','plan_meals','plan_base_items','targets_carb','targets_day','doda_meal_items','meal_done','doda_workout_rows','doda_day_notes','hydration_entries','weight_entries','user_settings','migrations'];
let A, D;
test.before(async () => { A = await login(ADMIN_EMAIL, ADMIN_PASSWORD); D = await login(DODA_EMAIL, DODA_PASSWORD); });

test('both accounts can log in; wrong password is rejected', async () => {
  assert.equal(A.status, 200, 'admin login'); assert.equal(D.status, 200, 'doda login');
  assert.ok((await login(DODA_EMAIL, DODA_PASSWORD + 'x')).status >= 400);
});
test('roles are correct (from profiles, own row only)', async () => {
  const a = await j('/rest/v1/profiles?select=role', {}, A.body.access_token), d = await j('/rest/v1/profiles?select=role', {}, D.body.access_token);
  assert.deepEqual(a.body, [{ role: 'admin' }]); assert.deepEqual(d.body, [{ role: 'doda' }]);
});
test('anonymous users cannot access any table', async () => {
  for (const t of TABLES) { const r = await j(`/rest/v1/${t}?select=*&limit=1`); assert.ok([401, 403].includes(r.status), `${t} -> ${r.status}`); }
});
test('public sign-up is disabled', async () => {
  const r = await j('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email: `probe+${Date.now()}@example.invalid`, password: 'Probe#Pass2026x' }) });
  assert.ok(r.status >= 400, 'signup must be refused, got ' + r.status);
});
test('Doda cannot write master data; Admin cannot read Doda private data', async () => {
  const w = await j('/rest/v1/foods', { method: 'POST', body: JSON.stringify({ id: 'zz_smoke_denied', name: 'x', base_qty: 1, unit: 'g' }) }, D.body.access_token);
  assert.ok([401, 403].includes(w.status), 'doda insert -> ' + w.status);
  for (const t of ['weight_entries', 'hydration_entries', 'meal_done', 'doda_workout_rows', 'doda_meal_items', 'doda_day_notes', 'user_settings']) {
    const r = await j(`/rest/v1/${t}?select=*&limit=5`, {}, A.body.access_token); assert.equal(r.status, 200); assert.deepEqual(r.body, [], `admin sees ${t}`);
  }
});
test('role changes are impossible for everyone', async () => {
  for (const tok of [A.body.access_token, D.body.access_token]) {
    const r = await j('/rest/v1/profiles?id=neq.00000000-0000-0000-0000-000000000000', { method: 'PATCH', body: JSON.stringify({ role: 'admin' }) }, tok);
    assert.ok([401, 403].includes(r.status), 'role patch -> ' + r.status);
  }
});
test('Doda can write only to her own data (throw-away row, removed again)', async () => {
  const id = 'zz_smoke_' + crypto.randomUUID(), tok = D.body.access_token;
  const spoof = await j('/rest/v1/weight_entries', { method: 'POST', body: JSON.stringify({ id: id + 'x', user_id: A.body.user.id, entry_date: '2026-01-01', kg: 50 }) }, tok);
  assert.ok([401, 403].includes(spoof.status), 'spoofed user_id -> ' + spoof.status);
  const ins = await j('/rest/v1/weight_entries', { method: 'POST', body: JSON.stringify({ id, entry_date: '2026-01-01', kg: 50 }) }, tok);
  assert.equal(ins.status, 201);
  const del = await j(`/rest/v1/weight_entries?id=eq.${id}`, { method: 'DELETE' }, tok); assert.equal(del.status, 200);
});
