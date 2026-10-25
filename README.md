# Weight Loss Challenge

A static, single-page tracker (no build step, no backend): 28-day carb-cycle nutrition plan imported from the PDF, workouts and videos,
hydration, weight tracking, daily targets, plus an Admin area with master catalogs.

## Run / deploy
- Local: open `index.html`, or serve the folder (`python3 -m http.server`).
- Vercel: import the repo as a **static site** (Framework preset "Other", no build command, output directory = repo root).
- Files needed at runtime: `index.html` and `data/plan-data.js` (Inter font loads from Google Fonts).

## Data
- All user data lives in the browser's `localStorage` (keys `prettyplan.v1*`). It is **per device/browser** and is not synced.
- `data/plan-data.js` / `data/plan.json` — the 28-day plan generated from the PDF; `data/validation-report.md` — import validation.
- Regenerate/validate: `pip install pdfplumber`, then `python3 tools/import_plan.py "<pdf>"` and `python3 tools/validate_plan.py "<pdf>"`.

## Authentication
Sign-in uses Supabase email/password (roles from `public.profiles`, enforced by Row Level Security). Setup, tests and the manual hosted steps are in `supabase/README.md`. Add the publishable key to `config.js` before deploying.

## Security note
Until the data-layer phase lands, app data still lives in each browser's localStorage (not synced), so the UI role gate is a convenience —
the real protection is the database RLS, which already enforces who may read and write what.
