# Carb Cycle Plan

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

## Security note
The "doda" / "admin" account picker is a **local prototype only** — it is not authentication and does not protect data.
Before real use, add secure authentication and server-enforced roles (e.g. Supabase auth + row-level security), and move the
shared plan/catalog data to a database so changes sync across devices.
