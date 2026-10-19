// Phase 3B API tests (LOCAL stack only): water goal, deleting catalog items referenced by Doda rows, private profile photos.
//   supabase start && supabase db reset && psql … "select public.setup_profile_photo_storage()"   (storage-api must be running)
//   eval "$(supabase status -o env | sed 's/^/export /')" && node --test --test-concurrency=1 supabase/tests/api/
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
let adminTok, dodaTok, dodaId, adminId, storageUp = false;
const login = async u => { const r = await j('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify(u) }); assert.equal(r.status, 200, 'login ' + u.email); return r.body; };
async function ensureUser(u) { const r = await j('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({ ...u, email_confirm: true }) }, SEC); if (r.status >= 400 && !/already|exists|registered/i.test(JSON.stringify(r.body))) throw new Error('create user failed'); }

// 1x1 JPEG
const JPEG = Buffer.from('/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=', 'base64');
const st = async (method, path, token, body, ct) => {
  const r = await fetch(`${URL}/storage/v1${path}`, { method, headers: { apikey: PUB, ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(ct ? { 'Content-Type': ct } : {}) }, body });
  let b = null; const text = await r.text(); try { b = JSON.parse(text); } catch { b = text; }
  return { status: r.status, body: b };
};
const up = (token, path, buf = JPEG, ct = 'image/jpeg') => st('POST', `/object/profile-photos/${path}`, token, buf, ct);

test.before(async () => {
  await ensureUser(ADMIN); await ensureUser(DODA);
  const rb = await j('/rest/v1/rpc/bootstrap_roles', { method: 'POST', body: JSON.stringify({ admin_email: ADMIN.email, doda_email: DODA.email }) }, SEC);
  assert.ok(rb.status < 300, 'bootstrap_roles');
  const a = await login(ADMIN), d = await login(DODA); adminTok = a.access_token; adminId = a.user.id; dodaTok = d.access_token; dodaId = d.user.id;
  for (const q of ['doda_workout_rows?id=eq.x3b','exercises?id=eq.e3b','videos?id=eq.v3b']) await j('/rest/v1/' + q, { method: 'DELETE' }, SEC);   // idempotent re-runs
  storageUp = (await st('GET', '/bucket', SEC)).status === 200;
});

test('water goal: Doda can store 500–10000 ml, out-of-range rejected, Admin cannot read it', async () => {
  const mk = ml => j('/rest/v1/user_settings?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' }, body: JSON.stringify({ user_id: dodaId, hydration_goal_ml: ml }) }, PUB, dodaTok);
  const ok = await mk(2500); assert.ok(ok.status < 300, JSON.stringify(ok.body)); assert.equal(ok.body[0].hydration_goal_ml, 2500);
  assert.ok((await mk(499)).status >= 400); assert.ok((await mk(10001)).status >= 400);
  const back = await j('/rest/v1/user_settings?select=hydration_goal_ml', {}, PUB, dodaTok); assert.equal(back.body[0].hydration_goal_ml, 2500);
  const adm = await j('/rest/v1/user_settings?select=*', {}, PUB, adminTok); assert.deepEqual(adm.body, []);
});

test('deleting Admin catalog items referenced by Doda rows keeps the rows (FK set null)', async () => {
  const v = await j('/rest/v1/videos', { method: 'POST', body: JSON.stringify({ id: 'v3b', title: '3B video', url: 'https://youtu.be/x3b', type: 'HIIT' }) }, PUB, adminTok); assert.ok(v.status < 300, JSON.stringify(v.body));
  const e = await j('/rest/v1/exercises', { method: 'POST', body: JSON.stringify({ id: 'e3b', name: '3B exercise', intensity: 'Moderate', minutes: 20, kcal: 100, default_video_id: 'v3b' }) }, PUB, adminTok); assert.ok(e.status < 300, JSON.stringify(e.body));
  const r = await j('/rest/v1/doda_workout_rows', { method: 'POST', body: JSON.stringify({ id: 'x3b', day_index: 1, sort: 0, exercise_id: 'e3b', video_id: 'v3b', name: '3B exercise', minutes: 20, notes: 'keep me', done: true }) }, PUB, dodaTok); assert.ok(r.status < 300, JSON.stringify(r.body));
  assert.equal((await j('/rest/v1/videos?id=eq.v3b', { method: 'DELETE' }, PUB, adminTok)).status, 200);
  assert.equal((await j('/rest/v1/exercises?id=eq.e3b', { method: 'DELETE' }, PUB, adminTok)).status, 200);
  const row = await j('/rest/v1/doda_workout_rows?id=eq.x3b&select=*', {}, PUB, dodaTok);
  assert.equal(row.body.length, 1); assert.equal(row.body[0].exercise_id, null); assert.equal(row.body[0].video_id, null);
  assert.equal(row.body[0].name, '3B exercise'); assert.equal(row.body[0].notes, 'keep me'); assert.equal(row.body[0].done, true);
  assert.deepEqual((await j('/rest/v1/doda_workout_rows?select=*', {}, PUB, adminTok)).body, []);
});

test('profile photos: Doda upload/read/replace/delete; Admin and anonymous denied; bucket private', { skip: false }, async t => {
  if (!storageUp) { t.skip('storage-api is not running locally'); return; }
  const mine = `${dodaId}/avatar-a.jpg`, mine2 = `${dodaId}/avatar-b.jpg`;
  const u1 = await up(dodaTok, mine); assert.ok(u1.status < 300, JSON.stringify(u1.body));
  const g = await fetch(`${URL}/storage/v1/object/authenticated/profile-photos/${mine}`, { headers: { apikey: PUB, Authorization: `Bearer ${dodaTok}` } });
  assert.equal(g.status, 200); assert.equal(Buffer.from(await g.arrayBuffer()).length, JPEG.length);
  // replace = upload a new name, then delete the old one
  assert.ok((await up(dodaTok, mine2)).status < 300);
  const del = await st('DELETE', `/object/profile-photos/${mine}`, dodaTok); assert.ok(del.status < 300, JSON.stringify(del.body));
  assert.ok([400, 404].includes((await st('GET', `/object/authenticated/profile-photos/${mine}`, dodaTok)).status));
  // denied: Admin read/write, anonymous read, public URL, other folder, bad mime, oversize
  assert.ok([400, 403, 404].includes((await st('GET', `/object/authenticated/profile-photos/${mine2}`, adminTok)).status), 'admin read');
  assert.ok((await up(adminTok, `${dodaId}/avatar-evil.jpg`)).status >= 400, 'admin write into Doda folder');
  assert.ok((await up(adminTok, `${adminId}/avatar.jpg`)).status >= 400, 'admin write into own folder');
  assert.ok((await st('GET', `/object/authenticated/profile-photos/${mine2}`, null)).status >= 400, 'anon read');
  assert.ok((await st('GET', `/object/public/profile-photos/${mine2}`, null)).status >= 400, 'public url');
  assert.ok((await up(dodaTok, `${adminId}/avatar.jpg`)).status >= 400, "Doda into someone else's folder");
  assert.ok((await up(dodaTok, `${dodaId}/x.txt`, Buffer.from('hi'), 'text/plain')).status >= 400, 'bad mime');
  assert.ok((await up(dodaTok, `${dodaId}/big.jpg`, Buffer.alloc(2 * 1024 * 1024 + 10, 1))).status >= 400, 'oversize');
  assert.ok((await st('DELETE', `/object/profile-photos/${mine2}`, adminTok)).status >= 400 || true);
  const still = await st('GET', `/object/authenticated/profile-photos/${mine2}`, dodaTok); assert.equal(still.status, 200, 'admin delete must not remove it');
  const list = await st('POST', '/object/list/profile-photos', adminTok, JSON.stringify({ prefix: `${dodaId}/`, limit: 10 }), 'application/json'); assert.ok(!Array.isArray(list.body) || list.body.length === 0, 'admin list');
  assert.equal((await st('DELETE', `/object/profile-photos/${mine2}`, dodaTok)).status < 300, true);
});

test('workout rows keep video label + url (migration 0005); non-http(s) links rejected; invisible to Admin', async () => {
  const base = { id: 'x3b_vid', day_index: 2, sort: 0, name: 'Link row', minutes: 10 };
  await j('/rest/v1/doda_workout_rows?id=eq.x3b_vid', { method: 'DELETE' }, SEC);
  const ok = await j('/rest/v1/doda_workout_rows', { method: 'POST', body: JSON.stringify({ ...base, video_label: 'Legacy video', video_url: 'https://youtu.be/legacy' }) }, PUB, dodaTok);
  assert.ok(ok.status < 300, JSON.stringify(ok.body)); assert.equal(ok.body[0].video_label, 'Legacy video'); assert.equal(ok.body[0].video_url, 'https://youtu.be/legacy');
  const def = await j('/rest/v1/doda_workout_rows', { method: 'POST', body: JSON.stringify({ ...base, id: 'x3b_def' }) }, PUB, dodaTok);
  assert.equal(def.body[0].video_label, ''); assert.equal(def.body[0].video_url, '');
  assert.ok((await j('/rest/v1/doda_workout_rows?id=eq.x3b_vid', { method: 'PATCH', body: JSON.stringify({ video_url: 'javascript:alert(1)' }) }, PUB, dodaTok)).status >= 400);
  assert.ok((await j('/rest/v1/doda_workout_rows?id=eq.x3b_vid', { method: 'PATCH', body: JSON.stringify({ video_label: 'x'.repeat(201) }) }, PUB, dodaTok)).status >= 400);
  assert.deepEqual((await j('/rest/v1/doda_workout_rows?select=video_url', {}, PUB, adminTok)).body, []);
  for (const id of ['x3b_vid', 'x3b_def']) await j(`/rest/v1/doda_workout_rows?id=eq.${id}`, { method: 'DELETE' }, SEC);
});
