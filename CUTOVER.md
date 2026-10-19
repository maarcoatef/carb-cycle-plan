# Production cutover (cloud sync) — nothing here deploys by itself
1. **Local test against hosted:** `cp config.hosted.example.js config.local.hosted.js`, paste the publishable key (`sb_publishable_…`, never a secret key), run `python3 -m http.server 8080`, open `http://localhost:8080/index.html?cfg=hosted`, sign in as Admin and Doda.
2. **Stage the key:** put the same publishable key into `config.js` (keep `syncEnabled:false`), run `node tools/cutover_check.mjs --staged`.
3. **Flip:** set `syncEnabled:true` in `config.js`, run `node tools/cutover_check.mjs` (must print "All checks passed").
4. **Approve → commit/push/deploy** (Vercel). Existing browsers keep their `prettyplan.v1*` data untouched: cloud mode never reads, writes or deletes it.
5. **Rollback:** set `syncEnabled:false` again and redeploy; cloud data stays in Supabase, legacy mode resumes from the untouched localStorage.
Hosted DB already has: migrations 0005 + 0006 and the active Plan v2 baseline. Old (v1) browser progress is never migrated automatically.
