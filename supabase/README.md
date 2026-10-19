# Supabase (Phase 2: schema, RLS, authentication)

Project ref `oxqcprgreelxfjhlqpxl`. The app (a static site) talks to Supabase with the **publishable key only**.
Never put the secret / service_role key in the repo, in `config.js`, in Vercel client settings, or in chat.

## Files
- `migrations/` — schema (`…0001`), role helpers + grants + RLS (`…0002`), private profile-photo bucket (`…0003`), `bootstrap_roles` (`…0004`).
- `tests/database/01_authz.test.sql` — 114 pgTAP assertions (`supabase test db`).
- `tests/api/authz.test.mjs` — end-to-end tests through the real API (GoTrue + PostgREST) on the local stack.
- `tests/api/phase3b.test.mjs` — water goal, catalog deletes, private photos (needs a running storage-api), workout video fields. Run: `node --test --test-concurrency=1 supabase/tests/api/authz.test.mjs supabase/tests/api/phase3b.test.mjs`.
- `support/local_storage_stub.sql` — local-only stand-in for `storage.*` when the local stack runs without the storage container.

## Run everything locally (does not touch hosted data)
```bash
supabase start -x storage-api
supabase db reset   # tests assume an empty local database (recreates it from the migrations)
docker exec -i supabase_db_carb-cycle-plan psql -U supabase_admin -d postgres < supabase/support/local_storage_stub.sql   # once
supabase test db
eval "$(supabase status -o env | sed 's/^/export /')" && node --test supabase/tests/api/authz.test.mjs
```
Local app login: copy the local publishable key from `supabase status` into the git-ignored `config.local.js` (already created; only loaded on localhost).

## Manual steps for the hosted project (in this order)
1. **Apply migrations**: `supabase link --project-ref oxqcprgreelxfjhlqpxl` then `supabase db push` (or paste the four files in the SQL editor, in order).
2. **Assign roles** (SQL editor, once — resolves the real UUIDs; the e-mails are not stored anywhere in the repo):
   `select * from public.bootstrap_roles('<admin e-mail>', '<doda e-mail>');`
   It never changes an existing role and refuses to give both roles to one account.
3. **Publishable key**: Dashboard → Settings → API Keys → copy the *publishable* key into `config.js` (`PASTE_YOUR_SUPABASE_PUBLISHABLE_KEY_HERE`).
4. **Auth settings** (Dashboard → Authentication): keep *Allow new users to sign up* OFF; Site URL `https://carb-cycle-plan.vercel.app`;
   minimum password length 8+ (12+ recommended); consider enabling MFA for the admin and leaked-password protection.
5. **Verify** on the hosted project: SQL editor `select tablename, rowsecurity from pg_tables where schemaname='public';` → every row `true`;
   Storage → bucket `profile-photos` exists and is **private**.
6. Deploy to Vercel only after 1–5 (the static site needs no environment variables; the URL/publishable key are public by design).

## Not done yet (next phases)
Seeding the PDF baseline + catalogs, the data-layer/sync adapter, the localStorage → Supabase import, and photo upload UI.
The app still reads/writes the browser's localStorage; only sign-in, roles and account switching use Supabase.

## Plan v2 (28-day PDF) — versioning and safe import
- `migrations/…0006_plan_versioning.sql` (hosted copy: `hosted/04b_plan_versioning.sql`): `plan_versions` (one active), version-scoped baseline ids (`v2-w1-d1…`), progress FKs `ON DELETE RESTRICT`, `doda_meal_overrides`.
- `tools/import_plan_v2.py <pdf>` → `data/plan.json` + `data/plan-data.js` (13 validation checks in `data/validation-report.md`; the v1 plan is archived in `data/archive/`). `tools/make_plan_sql.py` → `hosted/05*.sql`.
- Hosted order (each only after approval): `04_workout_video_fields.sql` → `04b_plan_versioning.sql` → `05b_plan_v2_backup.sql` (save the JSON) → `05a_plan_v2_dryrun.sql` (rolls back) → `05_plan_v2_import.sql` (refuses to run twice; activates v2 last).
- Old (v1) progress is never migrated: the app backs it up in `prettyplan.v1.progress-v1-backup` / `prettyplan.v1.plan-v1-backup`.
