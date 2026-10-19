# My Pretty Plan
Open `index.html` in a browser (no server needed). Data: `data/plan-data.js` (generated from the PDF), `data/plan.json`, `data/validation-report.md`.
Regenerate/validate: `pip install pdfplumber`, then `python3 tools/import_plan.py "<pdf>"` and `python3 tools/validate_plan.py "<pdf>"`.
