import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { reconcile, merge3, syncTable } = createRequire(import.meta.url)('../sync-core.js');
const F = ['name', 'qty'];
const row = (id, name, qty, ts = 1) => ({ id, name, qty, _ts: ts });
const map = (...rs) => Object.fromEntries(rs.map(r => [r.id, r]));

test('new local row → insert; new server row → pulled', () => {
  const r = reconcile({ B: {}, L: map(row('a', 'A', 1)), V: map(row('b', 'B', 2)), fields: F });
  assert.deepEqual(r.ops.insert.map(x => x.id), ['a']); assert.ok(r.res.b && r.res.a);
});
test('local-only edit → update op; server-only edit → taken locally', () => {
  const b = row('a', 'A', 1);
  let r = reconcile({ B: map(b), L: map(row('a', 'A', 5)), V: map(b), fields: F });
  assert.equal(r.ops.update.length, 1); assert.equal(r.ops.update[0].row.qty, 5);
  r = reconcile({ B: map(b), L: map(b), V: map(row('a', 'A', 9, 2)), fields: F });
  assert.equal(r.res.a.qty, 9); assert.equal(r.ops.update.length, 0); assert.equal(r.info.serverChanges, 1);
});
test('edits to different fields merge without loss', () => {
  const b = row('a', 'A', 1);
  const r = reconcile({ B: map(b), L: map(row('a', 'Local', 1)), V: map(row('a', 'A', 7, 2)), fields: F });
  assert.deepEqual([r.res.a.name, r.res.a.qty], ['Local', 7]); assert.equal(r.info.conflicts.length, 0);
  assert.equal(r.ops.update.length, 1, 'merged result still has to be pushed');
});
test('same-field clash: newer server value wins and is reported (stale local never overwrites)', () => {
  const b = row('a', 'A', 1);
  const r = reconcile({ B: map(b), L: map(row('a', 'A', 2)), V: map(row('a', 'A', 3, 2)), fields: F });
  assert.equal(r.res.a.qty, 3); assert.deepEqual(r.info.conflicts, ['a']); assert.equal(r.ops.update.length, 0);
});
test('deletions: clean local delete pushes; delete vs server edit keeps server; server delete vs local edit re-creates', () => {
  const b = row('a', 'A', 1);
  assert.equal(reconcile({ B: map(b), L: {}, V: map(b), fields: F }).ops.del.length, 1);
  let r = reconcile({ B: map(b), L: {}, V: map(row('a', 'A', 4, 2)), fields: F }); assert.equal(r.res.a.qty, 4); assert.equal(r.ops.del.length, 0);
  r = reconcile({ B: map(b), L: map(row('a', 'A', 8)), V: {}, fields: F }); assert.equal(r.ops.insert.length, 1); assert.equal(r.info.conflicts.length, 1);
  r = reconcile({ B: map(b), L: map(b), V: {}, fields: F }); assert.equal(Object.keys(r.res).length, 0);
});
test('read-only role: server is authoritative, never pushes', () => {
  const r = reconcile({ B: {}, L: map(row('x', 'local junk', 1)), V: map(row('a', 'A', 1)), fields: F, canWrite: false });
  assert.deepEqual(Object.keys(r.res), ['a']); assert.equal(r.ops.insert.length + r.ops.update.length + r.ops.del.length, 0);
});

// ── engine against a fake server with compare-and-swap, including a write that sneaks in between fetch and push ──
function fakeServer(initial) {
  const rows = {}; let ts = 10; for (const r of initial) rows[r.id] = { ...r, _ts: ts++ };
  const hooks = { beforeUpdate: null };
  const ad = {
    rows, hooks, log: [],
    async fetchAll() { return JSON.parse(JSON.stringify(rows)); },
    async insert(r) { if (rows[r.id]) return 'dup'; rows[r.id] = { ...r, _ts: ++ts }; ad.log.push('insert ' + r.id); return { ...rows[r.id] }; },
    async update(base, patch) { if (hooks.beforeUpdate) { const h = hooks.beforeUpdate; hooks.beforeUpdate = null; h(rows, () => ++ts); }
      const cur = rows[base.id]; if (!cur || cur._ts !== base._ts) return 'miss'; Object.assign(cur, patch, { _ts: ++ts }); ad.log.push('update ' + base.id + ' ' + JSON.stringify(patch)); return { ...cur }; },
    async remove(base) { const cur = rows[base.id]; if (!cur || cur._ts !== base._ts) return 'miss'; delete rows[base.id]; ad.log.push('delete ' + base.id); return 'ok'; }
  };
  return ad;
}
const mk = (adapter, local, shadow = {}) => { const st = { local, shadow: { rows: shadow } };
  return { st, o: { fields: F, key: 'id', canWrite: true, adapter, shadow: st.shadow, getLocal: () => st.local, setLocal: m => { st.local = m; } } }; };

test('engine: stale writer cannot overwrite a newer server value (CAS miss → re-merge)', async () => {
  const srv = fakeServer([{ id: 'a', name: 'A', qty: 1 }]);
  const shadow = map({ ...srv.rows.a });                          // device 1 last saw qty 1
  const { st, o } = mk(srv, map({ id: 'a', name: 'A', qty: 2 }), shadow);   // device 1 edits qty → 2
  srv.hooks.beforeUpdate = (rows, bump) => { rows.a.qty = 99; rows.a._ts = bump(); };   // device 2 saves qty 99 right before device 1 pushes
  const res = await syncTable(o);
  assert.equal(srv.rows.a.qty, 99, 'newer server value must survive');
  assert.equal(st.local.a.qty, 99, 'local adopts the newer value');
  assert.ok(res.conflicts.includes('a'));
});
test('engine: concurrent edit of a different field is merged and both survive', async () => {
  const srv = fakeServer([{ id: 'a', name: 'A', qty: 1 }]);
  const { st, o } = mk(srv, map({ id: 'a', name: 'Renamed', qty: 1 }), map({ ...srv.rows.a }));
  srv.hooks.beforeUpdate = (rows, bump) => { rows.a.qty = 5; rows.a._ts = bump(); };
  await syncTable(o);
  assert.deepEqual([srv.rows.a.name, srv.rows.a.qty], ['Renamed', 5]); assert.deepEqual([st.local.a.name, st.local.a.qty], ['Renamed', 5]);
});
test('engine: insert collision (duplicate id created elsewhere) resolves without data loss', async () => {
  const srv = fakeServer([]); const ad = srv; const realInsert = ad.insert;
  ad.insert = async r => { ad.rows[r.id] = { id: r.id, name: 'from other device', qty: 3, _ts: 50 }; ad.insert = realInsert; return 'dup'; };
  const { st, o } = mk(ad, map({ id: 'n', name: 'mine', qty: 1 }));
  await syncTable(o);
  assert.equal(srv.rows.n.name, 'from other device'); assert.equal(st.local.n.name, 'from other device');
});
test('engine: second pull is a no-op and offline/network errors propagate for retry', async () => {
  const srv = fakeServer([{ id: 'a', name: 'A', qty: 1 }]); const { o } = mk(srv, {});
  await syncTable(o); const n = srv.log.length; await syncTable(o); assert.equal(srv.log.length, n);
  o.adapter = { ...srv, fetchAll: async () => { throw new TypeError('Failed to fetch'); } };
  await assert.rejects(syncTable(o), /fetch/);
});
