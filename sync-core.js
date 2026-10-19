/* Sync core: pure 3-way reconcile + compare-and-swap push loop. No DOM, no Supabase: the browser passes an adapter, tests pass a fake.
   Rows are flat objects keyed by `key`. B = shadow (last server snapshot), L = local rows, V = fresh server rows.        */
(function (root) {
  const isNil = v => v === null || v === undefined || v === '';
  function norm(v) {
    if (isNil(v)) return null;
    if (Array.isArray(v)) return JSON.stringify(v.slice().sort());
    if (typeof v === 'number') return v;
    if (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v.trim())) return Number(v);
    return v;
  }
  const rowEq = (a, b, fields) => fields.every(f => norm(a && a[f]) === norm(b && b[f]));

  // field-wise 3-way merge: local-only change wins, server-only change wins, same-field clash → server (newer) wins and is reported
  function merge3(b, l, v, fields) {
    const row = Object.assign({}, l, v); let conflict = false;
    for (const f of fields) {
      const bf = norm(b[f]), lf = norm(l[f]), vf = norm(v[f]);
      if (lf === vf) row[f] = v[f];
      else if (lf === bf) row[f] = v[f];
      else if (vf === bf) row[f] = l[f];
      else { row[f] = v[f]; conflict = true; }
    }
    return { row, conflict };
  }

  function reconcile({ B, L, V, fields, canWrite = true }) {
    const res = {}, ops = { insert: [], update: [], del: [] }, info = { conflicts: [], serverChanges: 0 };
    if (!canWrite) {                                   // read-only role: the server is authoritative
      for (const k of new Set([...Object.keys(L), ...Object.keys(V)])) {
        if (V[k]) { res[k] = V[k]; if (!L[k] || !rowEq(L[k], V[k], fields)) info.serverChanges++; } else info.serverChanges++;
      }
      return { res, ops, info };
    }
    for (const k of new Set([...Object.keys(B), ...Object.keys(L), ...Object.keys(V)])) {
      const b = B[k], l = L[k], v = V[k];
      if (!b) {                                        // never seen before
        if (l && !v) { res[k] = l; ops.insert.push(l); }
        else if (v && !l) { res[k] = v; info.serverChanges++; }
        else if (l && v) { if (!rowEq(l, v, fields)) { info.conflicts.push(k); info.serverChanges++; } res[k] = v; }
        continue;
      }
      if (!v) {                                        // deleted on the server
        if (!l) continue;
        if (rowEq(l, b, fields)) { info.serverChanges++; continue; }          // untouched locally → accept the deletion
        info.conflicts.push(k); res[k] = l; ops.insert.push(l); continue;     // edited locally → keep the edit (re-create)
      }
      if (!l) {                                        // deleted locally
        if (rowEq(v, b, fields)) { ops.del.push(v); continue; }               // server unchanged → delete
        info.conflicts.push(k); res[k] = v; info.serverChanges++; continue;   // server changed meanwhile → keep server
      }
      const m = merge3(b, l, v, fields); res[k] = m.row;
      if (m.conflict) info.conflicts.push(k);
      if (!rowEq(m.row, v, fields)) ops.update.push({ row: m.row, base: v });
      if (!rowEq(m.row, l, fields)) info.serverChanges++;
    }
    return { res, ops, info };
  }

  // One table: fetch → reconcile → apply locally → push with compare-and-swap. A CAS miss / duplicate means someone else
  // wrote in between, so we loop (re-fetch + re-merge) instead of overwriting newer data.
  async function syncTable(o) {
    const { fields, key, adapter, shadow } = o; let total = { conflicts: [], serverChanges: 0, pushed: 0 };
    for (let attempt = 0; attempt < 5; attempt++) {
      const V = await adapter.fetchAll(), L = o.getLocal();
      const { res, ops, info } = reconcile({ B: shadow.rows, L, V, fields, canWrite: o.canWrite });
      if (info.serverChanges || info.conflicts.length) o.setLocal(res);
      total.serverChanges += info.serverChanges; total.conflicts.push(...info.conflicts);
      const next = Object.assign({}, V); let miss = false;
      for (const r of ops.insert) { const out = await adapter.insert(r); if (out === 'dup') { miss = true; break; } next[String(r[key])] = out; total.pushed++; }
      if (!miss) for (const u of ops.update) {
        const patch = {}; for (const f of fields) if (norm(u.row[f]) !== norm(u.base[f])) patch[f] = isNil(u.row[f]) ? null : u.row[f];
        const out = await adapter.update(u.base, patch); if (out === 'miss') { miss = true; break; } next[String(u.base[key])] = out; total.pushed++;
      }
      if (!miss) for (const d of ops.del) { const out = await adapter.remove(d); if (out === 'miss') { miss = true; break; } delete next[String(d[key])]; total.pushed++; }
      shadow.rows = next;
      if (!miss) return total;
    }
    throw new Error('sync conflict could not be resolved (too many concurrent changes)');
  }
  const api = { norm, rowEq, merge3, reconcile, syncTable };
  if (typeof module !== 'undefined' && module.exports) module.exports = api; else root.CCSync = api;
})(typeof window !== 'undefined' ? window : globalThis);
